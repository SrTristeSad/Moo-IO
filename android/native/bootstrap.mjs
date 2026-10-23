// SPDX-License-Identifier: AGPL-3.0-only
// Native Android Node.js bootstrap. Record startup failures in private app data.
// This is NOT a substitute for the authoritative Moo-IO server (offline.mjs).
import fs from "node:fs";
import path from "node:path";

const dir = process.env.DATA_DIR || process.cwd();
const logFile = path.join(dir, "node-boot.log");
try { fs.mkdirSync(dir, { recursive: true }); } catch {}
function note(phase, info = "") {
    const msg = new Date().toISOString() + " " + phase +
      (info ? " " + String(info).slice(0, 16000) : "") + "\n";
    try { fs.appendFileSync(logFile, msg); } catch {}
    try { console.log("[Moo-IO Android] " + msg.trim()); } catch {}
}
function errorDetails(error) {
    return error && error.stack ? error.stack : String(error);
}

note("BOOTSTRAP", "Node " + process.versions.node + " (" + process.platform + ")");
process.on("exit", (code) => note("NODE_EXIT", String(code)));
process.on("uncaughtException", (error) => {
    note("UNCAUGHT_EXCEPTION", errorDetails(error));
    process.exitCode = 1;
    // Keep the diagnostic process alive rather than restarting the service silently.
    setInterval(() => {}, 60000);
});
process.on("unhandledRejection", (error) => {
    note("UNHANDLED_REJECTION", errorDetails(error));
    process.exitCode = 1;
});

try {
    note("IMPORTING_MOOIO_SERVER");
    await import("./offline.mjs");
    note("MOOIO_SERVER_IMPORTED");
} catch (error) {
    note("SERVER_BOOT_FAILED", errorDetails(error));
    process.exitCode = 1;
    setInterval(() => {}, 60000);
}
