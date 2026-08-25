// Project Resources Extension for Pi
// Adds the ability to specify additional project level paths to load skills and prompts from.
// Useful for remapping skills/commands from claude directories.
//
import { readFile, access } from "node:fs/promises";
import { join, resolve } from "node:path";
import { homedir } from "node:os";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default async function (pi: ExtensionAPI) {
  const settingsPath = join(homedir(), ".pi", "agent", "settings.json");
  let projectPrompts: string[] = [];
  let projectSkills: string[] = [];

  try {
    const raw = await readFile(settingsPath, "utf8");
    const settings = JSON.parse(raw);
    projectPrompts = settings.projectPrompts ?? [];
    projectSkills = settings.projectSkills ?? [];
  } catch {
    // no settings or missing keys — nothing to contribute
  }

  pi.on("resources_discover", async (event, ctx) => {
    if (!ctx.isProjectTrusted()) return {};

    const exists = (p: string) => access(p).then(() => true, () => false);
    const resolve_ = (rel: string) => resolve(event.cwd, rel);

    const skillPaths = (
      await Promise.all(projectSkills.map(resolve_).map(async (p) => (await exists(p) ? p : null)))
    ).filter(Boolean) as string[];

    const promptPaths = (
      await Promise.all(projectPrompts.map(resolve_).map(async (p) => (await exists(p) ? p : null)))
    ).filter(Boolean) as string[];

    return { skillPaths, promptPaths };
  });
}
