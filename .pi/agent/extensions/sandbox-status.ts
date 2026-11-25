import { readFileSync } from "node:fs";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const sandboxed = (() => {
  let pid = process.ppid;
  while (pid > 1) {
    try {
      if (readFileSync(`/proc/${pid}/comm`, "utf8").trim() === "bwrap") return true;
      pid = Number(readFileSync(`/proc/${pid}/status`, "utf8").match(/^PPid:\s+(\d+)/m)?.[1]);
    } catch {
      return false;
    }
  }
  return false;
})();

export default function (pi: ExtensionAPI) {
  pi.on("session_start", (_event, ctx) => {
    ctx.ui.setStatus("sandbox-status", sandboxed ? "🔒 bwrap" : "🚪 non-isolated");
  });
}
