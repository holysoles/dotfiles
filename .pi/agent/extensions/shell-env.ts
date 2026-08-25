// Shell Env Pi extension: simple injection of env variables for bash invocations.
// Useful for ensuring commands are run non-interactively.
// Set a map in settings.json under shellEnv:
// {
//   "shellEnv": {
//     "GIT_EDITOR": "true"
//   }
// }
//
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { isToolCallEventType, createLocalBashOperations } from "@earendil-works/pi-coding-agent";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

function loadEnv(): Record<string, string> {
  try {
    const raw = readFileSync(join(homedir(), ".pi", "agent", "settings.json"), "utf-8");
    const settings = JSON.parse(raw);
    return settings.shellEnv ?? {};
  } catch {
    return {};
  }
}

export default function (pi: ExtensionAPI) {
  const env = loadEnv();

  const exports = Object.entries(env)
    .map(([k, v]) => `export ${k}=${JSON.stringify(v)}`)
    .join("\n");
  if (!exports) return;

  pi.on("tool_call", (event) => {
    if (!isToolCallEventType("bash", event)) return;
    event.input.command = `${exports}\n${event.input.command}`;
  });

  pi.on("user_bash", () => {
    const local = createLocalBashOperations();
    return {
      operations: {
        exec(command, cwd, options) {
          return local.exec(`${exports}\n${command}`, cwd, options);
        },
      },
    };
  });
}
