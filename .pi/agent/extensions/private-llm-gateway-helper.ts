// Sync model costs and route matching EnMaaS models to OpenAI on failure.
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { randomUUID } from "node:crypto";
import { chmod, mkdir, readFile, realpath, rename, rm, stat, unlink, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";
import { isDeepStrictEqual } from "node:util";
import { chooseFallbackRoute } from "./fallback-model-routing.mjs";

// Add target/catalog pairs here; model IDs must match exactly.
const providers = [{ target: "enmaas", catalog: "openai" }];
const fallbackModels = ["gpt-6-sol", "gpt-6-luna", "gpt-6-astra", "gpt-5.6-terra"];
const modelsLockWaitMs = 30_000;
const modelsLockStaleMs = 30_000;

export default function (pi: ExtensionAPI) {
  for (const id of fallbackModels) {
    pi.registerVirtualModel<boolean>({
      provider: "fallback",
      id,
      name: `${id} (EnMaaS → OpenAI)`,
      thinkingLevels: ["off", "minimal", "low", "medium", "high", "xhigh"],
      contextWindow: 272000,
      maxTokens: 128000,
      route(request, ctx) {
        const downstream = ctx.modelRegistry.find("enmaas", id);
        const upstream = ctx.modelRegistry.find("openai", id);
        // shortcut: compaction retries also switch providers; distinguish overflow if it becomes a problem.
        const failedDownstream = request.reason === "retry" && request.failed?.model.provider === "enmaas";
        const preferUpstream = request.state === true ||
          (failedDownstream && !!upstream && ctx.modelRegistry.hasConfiguredAuth(upstream));
        const route = chooseFallbackRoute(id, ctx, preferUpstream);
        return { ...route, thinkingLevel: request.thinkingLevel };
      },
    });
  }
  pi.on("session_start", (_event, ctx) => {
    void sync(ctx);
  });
}

async function readModelsLockOwner(ownerPath: string): Promise<string | undefined> {
  try {
    return await readFile(ownerPath, "utf8");
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") return undefined;
    throw error;
  }
}

async function acquireModelsLock(targetPath: string): Promise<() => Promise<void>> {
  const lockPath = `${targetPath}.lock`;
  const ownerPath = join(lockPath, "owner");
  const token = `${process.pid}:${randomUUID()}`;
  const deadline = Date.now() + modelsLockWaitMs;

  while (true) {
    let created = false;
    try {
      await mkdir(lockPath, { mode: 0o700 });
      created = true;
      await writeFile(ownerPath, token, { flag: "wx", mode: 0o600 });
      return async () => {
        if (await readModelsLockOwner(ownerPath) === token) {
          await rm(lockPath, { recursive: true });
        }
      };
    } catch (error) {
      if (created) await rm(lockPath, { recursive: true, force: true }).catch(() => {});
      if (!error || typeof error !== "object" || !("code" in error) || error.code !== "EEXIST") throw error;

      if (await removeStaleModelsLock(lockPath)) continue;
      if (Date.now() >= deadline) throw new Error(`Timed out waiting for model config lock: ${targetPath}`);
      await sleep(25);
    }
  }
}

async function removeStaleModelsLock(lockPath: string): Promise<boolean> {
  const ownerPath = join(lockPath, "owner");
  const owner = await readModelsLockOwner(ownerPath);
  let lockStat;
  try {
    lockStat = await stat(lockPath);
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") return false;
    throw error;
  }

  if (owner !== undefined) {
    const pid = Number(owner.slice(0, owner.indexOf(":")));
    if (Number.isSafeInteger(pid) && pid > 0) {
      try {
        process.kill(pid, 0);
        return false;
      } catch (error) {
        if (!error || typeof error !== "object" || !("code" in error) || error.code !== "ESRCH") return false;
      }
    } else if (Date.now() - lockStat.mtimeMs < modelsLockStaleMs) {
      return false;
    }
  } else if (Date.now() - lockStat.mtimeMs < modelsLockStaleMs) {
    return false;
  }

  if (await readModelsLockOwner(ownerPath) !== owner) return false;
  const stalePath = `${lockPath}.${process.pid}.${randomUUID()}.stale`;
  try {
    await rename(lockPath, stalePath);
    await rm(stalePath, { recursive: true, force: true });
    return true;
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") return false;
    throw error;
  }
}

async function sync(ctx: ExtensionContext): Promise<void> {
  const notify = (message: string, type: "info" | "warning" = "info") =>
    ctx.ui?.notify(message, type);
  try {
    const agentDir = resolve(process.env.PI_CODING_AGENT_DIR ?? join(homedir(), ".pi", "agent"));
    const modelsPath = join(agentDir, "models.json");
    const [storeText, targetPath] = await Promise.all([
      readFile(join(agentDir, "models-store.json"), "utf8"),
      realpath(modelsPath),
    ]);
    const store = JSON.parse(storeText);
    const releaseLock = await acquireModelsLock(targetPath);
    const missingPricing = new Set<string>();
    let updated: string[] = [];
    try {
      while (true) {
        const configText = await readFile(targetPath, "utf8");
        const config = JSON.parse(configText);
        updated = [];
        for (const { target, catalog } of providers) {
          const models = config?.providers?.[target]?.models;
          const catalogModels = store?.[catalog]?.models;
          if (!Array.isArray(models) || !Array.isArray(catalogModels)) continue;

          for (const model of models) {
            if (typeof model?.id !== "string") continue;
            const match = catalogModels.find(
              (entry) => entry?.type === "chat" && entry.id === model.id,
            );
            if (!match) continue;
            if (!match.cost) {
              if (!missingPricing.has(`${target}/${model.id}`)) {
                notify(`Cost sync: no ${catalog} catalog pricing for ${target}/${model.id}, left unchanged`, "warning");
                missingPricing.add(`${target}/${model.id}`);
              }
              continue;
            }
            if (!isDeepStrictEqual(model.cost, match.cost)) {
              model.cost = match.cost;
              updated.push(`${target}/${model.id}`);
            }
          }
        }
        if (updated.length === 0) return;

        const mode = (await stat(targetPath)).mode & 0o777;
        const tempPath = `${targetPath}.${process.pid}.tmp`;
        try {
          await writeFile(tempPath, `${JSON.stringify(config, null, 2)}\n`, { mode });
          await chmod(tempPath, mode);
          if (await readFile(targetPath, "utf8") !== configText) {
            await unlink(tempPath).catch(() => {});
            continue;
          }
          await rename(tempPath, targetPath);
          break;
        } catch (error) {
          await unlink(tempPath).catch(() => {});
          throw error;
        }
      }
    } finally {
      await releaseLock();
    }

    await ctx.modelRegistry.refresh({ allowNetwork: false });
    notify(`Model pricing synced with the catalog: ${updated.join(", ")}`);
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") return;
    notify(`Model cost sync failed: ${error instanceof Error ? error.message : String(error)}`, "warning");
  }
}
