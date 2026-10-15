// Sync EnMaaS GPT model costs in models.json with OpenAI catalog pricing
// cached in models-store.json. Runs once per session at startup, off the
// critical path; notifies when prices change and reloads the registry so
// the new costs are visible without restarting Pi.
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { chmod, readFile, realpath, rename, stat, unlink, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { isDeepStrictEqual } from "node:util";

export default function (pi: ExtensionAPI) {
  pi.on("session_start", (_event, ctx) => {
    void sync(ctx);
  });
}

async function sync(ctx: ExtensionContext): Promise<void> {
  const notify = (message: string, type: "info" | "warning" = "info") =>
    ctx.ui?.notify(message, type);
  try {
    const agentDir = resolve(process.env.PI_CODING_AGENT_DIR ?? join(homedir(), ".pi", "agent"));
    const modelsPath = join(agentDir, "models.json");
    const [configText, storeText] = await Promise.all([
      readFile(modelsPath, "utf8"),
      readFile(join(agentDir, "models-store.json"), "utf8"),
    ]);
    const config = JSON.parse(configText);
    const openaiModels = JSON.parse(storeText)?.openai?.models;
    const enmaasModels = config?.providers?.enmaas?.models;
    if (!Array.isArray(enmaasModels) || !Array.isArray(openaiModels)) return;

    const updated: string[] = [];
    for (const model of enmaasModels) {
      if (typeof model?.id !== "string" || !model.id.startsWith("gpt-")) continue;
      const catalog = openaiModels.find(
        (entry) => entry.type === "chat" && entry.id === model.id,
      );
      if (!catalog?.cost) {
        notify(`EnMaaS cost sync: no OpenAI catalog pricing for ${model.id}, left unchanged`, "warning");
        continue;
      }
      if (!isDeepStrictEqual(model.cost, catalog.cost)) {
        model.cost = catalog.cost;
        updated.push(model.id);
      }
    }
    if (updated.length === 0) return;

    const targetPath = await realpath(modelsPath);
    const mode = (await stat(targetPath)).mode & 0o777;
    const tempPath = `${targetPath}.${process.pid}.tmp`;
    try {
      await writeFile(tempPath, `${JSON.stringify(config, null, 2)}\n`, { mode });
      await chmod(tempPath, mode);
      await rename(tempPath, targetPath);
    } catch (error) {
      await unlink(tempPath).catch(() => {});
      throw error;
    }

    await ctx.modelRegistry.refresh({ allowNetwork: false });
    notify(`EnMaaS pricing synced with the OpenAI catalog: ${updated.join(", ")}`);
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") return;
    notify(`EnMaaS cost sync failed: ${error instanceof Error ? error.message : String(error)}`, "warning");
  }
}
