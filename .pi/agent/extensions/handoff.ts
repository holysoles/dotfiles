/**
 * Seamless Handoff Extension
 *
 * Generates a context summary from the current session, then seamlessly opens
 * a new session with that context pre-loaded and the LLM auto-started.
 *
 * Usage:
 *   /handoff                                  — handoff using current model
 *   /handoff anthropic-vertex/claude-haiku-4-5 — handoff and switch model
 *
 * Tab-completes model names from the enabled models list.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const SUMMARY_REQUEST = `Summarize this session for handoff to a new session. Output only the summary, no preamble. Use exactly this format:

## Project Goal
What we are currently trying to achieve.

## Current Status
What was just completed and what is still in progress.

## Key Decisions
Important architectural or logic choices made in this session (bullet list).

## Active Files
Paths to files that were recently read or modified (bullet list).

## Immediate Next Steps
Exactly what the next task should be, in priority order (bullet list).`;

export default function (pi: ExtensionAPI) {
	let cachedModels: string[] = [];
	let pendingResolveSummary: ((text: string | null) => void) | null = null;
	let capturedSummaryText: string | null = null;

	pi.on("session_start", async (_event, ctx) => {
		const scoped = ctx.scopedModels;
		if (scoped && scoped.length > 0) {
			cachedModels = scoped.map(({ model }) => `${model.provider}/${model.id}`);
		} else {
			cachedModels = ctx.modelRegistry
				.getAvailable()
				.map((m) => `${m.provider}/${m.id}`);
		}
	});

	// Capture text at agent_end; resolve only at agent_settled so navigateTree
	// is safe to call immediately after the promise resolves.
	pi.on("agent_end", (event) => {
		if (!pendingResolveSummary) return;
		const msg = [...event.messages].reverse().find((m) => m.role === "assistant");
		if (!msg) return;
		const content = (msg as { content: Array<{ type: string; text?: string }> })
			.content;
		capturedSummaryText =
			content
				.filter((c) => c.type === "text" && c.text)
				.map((c) => c.text!)
				.join("\n")
				.trim() || null;
	});

	pi.on("agent_settled", () => {
		if (!pendingResolveSummary) return;
		const resolve = pendingResolveSummary;
		pendingResolveSummary = null;
		resolve(capturedSummaryText);
		capturedSummaryText = null;
	});

	pi.registerCommand("handoff", {
		description: "Save context and continue seamlessly in a new session",
		argumentHint: "[provider/model]",

		getArgumentCompletions: (prefix: string) => {
			const items = cachedModels.map((id) => ({ value: id, label: id }));
			return prefix ? items.filter((i) => i.value.includes(prefix)) : items;
		},

		handler: async (args, ctx) => {
			if (ctx.mode !== "tui") {
				ctx.ui.notify("handoff requires interactive mode", "error");
				return;
			}

			if (!ctx.model) {
				ctx.ui.notify("No model selected", "error");
				return;
			}

			// --- Step 1: Parse and validate optional model arg ---
			const modelArg = args.trim();
			let targetProvider: string | undefined;
			let targetModelId: string | undefined;

			if (modelArg) {
				const slashIdx = modelArg.indexOf("/");
				if (slashIdx < 1) {
					ctx.ui.notify("Invalid model format. Use: provider/model-id", "error");
					return;
				}
				targetProvider = modelArg.slice(0, slashIdx);
				targetModelId = modelArg.slice(slashIdx + 1);

				const found = ctx.modelRegistry.find(targetProvider, targetModelId);
				if (!found) {
					ctx.ui.notify(`Model not found: ${modelArg}`, "error");
					return;
				}
			}

			// --- Step 2: Check session has content ---
			const branch = ctx.sessionManager.getBranch();
			if (!branch.some((e) => e.type === "message")) {
				ctx.ui.notify("Nothing to hand off — session is empty", "info");
				return;
			}
			const currentSessionFile = ctx.sessionManager.getSessionFile();
			// Capture the leaf before the summary exchange so we can rewind after.
			const preHandoffLeafId = branch.at(-1)?.id;

			// --- Step 3: Generate summary through the current session's agent loop ---
			// Sending as a real turn reuses the provider's existing KV cache for the
			// conversation, rather than rebuilding it in a separate completion call.
			if (pendingResolveSummary) {
				ctx.ui.notify("Handoff already in progress", "error");
				return;
			}
			const summaryPromise = new Promise<string | null>((resolve) => {
				pendingResolveSummary = resolve;
			});
			pi.sendUserMessage(SUMMARY_REQUEST);
			await ctx.waitForIdle();
			const summary = await summaryPromise;

			// --- Step 4: Rewind session to before the summary exchange ---
			// Leaves the original conversation intact for future resumption.
			if (preHandoffLeafId) {
				await ctx.navigateTree(preHandoffLeafId);
			}

			// --- Step 5: Handle cancellation or empty summary ---
			if (!summary?.trim()) {
				ctx.ui.notify(
					summary === null ? "Handoff cancelled" : "Handoff failed: empty summary",
					summary === null ? "info" : "error",
				);
				return;
			}

			// --- Step 5: Create new session, inject context, optionally switch model ---
			let newSessionResult: Awaited<ReturnType<typeof ctx.newSession>>;
			try {
				newSessionResult = await ctx.newSession({
					parentSession: currentSessionFile,
					setup: async (sm) => {
						sm.appendCustomMessageEntry(
							"handoff",
							`# Context from previous session\n\n${summary}`,
							false, // hidden from TUI, present in LLM context
						);
						if (targetProvider && targetModelId) {
							sm.appendModelChange(targetProvider, targetModelId);
						}
					},
					withSession: async (replacementCtx) => {
						await replacementCtx.sendUserMessage(
							"Resume our work from where we left off. Context from the previous session has been loaded.",
						);
					},
				});
			} catch (err) {
				ctx.ui.notify(`Failed to open new session: ${String(err)}`, "error");
				return;
			}

			if (newSessionResult.cancelled) {
				ctx.ui.notify("New session cancelled", "info");
			}
		},
	});
}
