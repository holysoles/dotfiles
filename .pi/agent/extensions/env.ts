// Env Pi extension: inject env variables to subprocesses.
// Useful for ensuring commands are run non-interactively.
// Set a map in settings.json under env:
// {
//   "env": {
//     "GIT_EDITOR": "true"
//   }
// }
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

function loadEnv(): Record<string, string> {
  try {
    const raw = readFileSync(join(homedir(), ".pi", "agent", "settings.json"), "utf-8");
    const settings = JSON.parse(raw);
    return settings.env ?? {};
  } catch {
    return {};
  }
}

export default function (_pi: ExtensionAPI) {
  const env = loadEnv();
  for (const [k, v] of Object.entries(env)) {
    process.env[k] = v;
  }
}
