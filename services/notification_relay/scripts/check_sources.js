import { readdirSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

for (const directory of ["src", "test"]) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (!entry.isFile() || !entry.name.endsWith(".js")) {
      continue;
    }
    const file = join(directory, entry.name);
    const result = spawnSync(process.execPath, ["--check", file], {
      stdio: "inherit",
    });
    if (result.status !== 0) {
      process.exit(result.status ?? 1);
    }
  }
}

const functions = await import("../src/index.js");
if (!functions.notificationRelay || !functions.retryNotificationDeliveries) {
  throw new Error("Notification relay Functions exports are incomplete.");
}
