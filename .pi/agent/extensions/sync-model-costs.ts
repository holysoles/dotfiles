// Sync configured providers' model costs from the cached catalog at session startup.
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { chmod, readFile, realpath, rename, stat, unlink, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { isDeepStrictEqual } from "node:util";

// Add target/catalog pairs here; model IDs must match exactly.
const providers = [{ target: "enmaas", catalog: "openai" }];

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
    const store = JSON.parse(storeText);
    const updated: string[] = [];
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
          notify(`Cost sync: no ${catalog} catalog pricing for ${target}/${model.id}, left unchanged`, "warning");
          continue;
        }
        if (!isDeepStrictEqual(model.cost, match.cost)) {
          model.cost = match.cost;
          updated.push(`${target}/${model.id}`);
        }
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
    notify(`Model pricing synced with the catalog: ${updated.join(", ")}`);
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") return;
    notify(`Model cost sync failed: ${error instanceof Error ? error.message : String(error)}`, "warning");
  }
}
