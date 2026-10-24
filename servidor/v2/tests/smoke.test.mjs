// Integration: dedicated CLI -> actual authoritative Node -> API / ticket / WebSocket.
import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:net";
import { mkdtempSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const root = fileURLToPath(new URL("../../../", import.meta.url));
const cli = path.join(root, "servidor/v2/cli.mjs");
const requireServer = createRequire(path.join(root, "windows/server/package.json"));
const WebSocket = requireServer("ws");
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function unusedPort() {
  const net = createServer();
  await new Promise((resolve, reject) => net.once("error", reject).listen(0, "127.0.0.1", resolve));
  const port = net.address().port;
  await new Promise(resolve => net.close(resolve));
  return port;
}
async function command(args) {
  const child = spawn(process.execPath, [cli, ...args], { cwd: root, stdio: ["ignore", "pipe", "pipe"] });
  let output = "";
  child.stdout.on("data", d => output += d);
  child.stderr.on("data", d => output += d);
  const code = await new Promise(resolve => child.on("close", resolve));
  return { code, output };
}
test("V2: cria sala isolada, inicia motor real, controla ingresso e desliga", { timeout: 45000 }, async () => {
  const dir = mkdtempSync(path.join(tmpdir(), "mooio-v2-smoke-"));
  const config = path.join(dir, "server.json");
  const port = await unusedPort();
  let child;
  try {
    const created = await command(["init", "--host", "127.0.0.1", "--port", String(port), "--bots", "0", "--config", config]);
    assert.equal(created.code, 0, created.output);
    assert.match(created.output, /Codigo privado da sala:/);
    assert.equal((await command(["doctor", "--config", config])).code, 0);
    const address = "http://127.0.0.1:" + port;
    const roomCode = (await import("../lib/config.mjs")).readConfig(config).roomCode;
    child = spawn(process.execPath, [cli, "start", "--config", config],
      { cwd: root, stdio: ["ignore", "pipe", "pipe"] });
    let logs = "";
    child.stdout.on("data", d => logs += d);
    child.stderr.on("data", d => logs += d);
    let ready = false;
    for (let i = 0; i < 70; i++) {
      if (child.exitCode !== null) break;
      try {
        const response = await fetch(address + "/mooio/status", { signal: AbortSignal.timeout(350) });
        if (response.ok && (await response.json()).project === "Moo-IO") { ready = true; break; }
      } catch {}
      await sleep(200);
    }
    assert.equal(ready, true, "Servidor V2 nao subiu: " + logs.slice(-2000));
    const ping = await (await fetch(address + "/ping")).json();
    const protocol = await (await fetch(address + "/mooio/protocol")).json();
    assert.equal(protocol.buildId, ping.build);
    assert.equal(protocol.constants.length, 8);
    assert.equal(existsSync(path.join(dir, "data", "protocol-build.json")), true);
    const join = code => fetch(address + "/api/join", {
      method: "POST",
      headers: { "content-type": "application/json", ...(code ? { "x-mooio-code": code } : {}) },
      body: JSON.stringify({ host: address + "/s/LC", captcha: true })
    });
    assert.equal((await join()).status, 403);
    assert.equal((await join("invalido")).status, 403);
    const admitted = await join(roomCode);
    assert.equal(admitted.status, 200);
    const { ticket } = await admitted.json();
    assert.ok(ticket);
    const ws = await new Promise((resolve, reject) => {
      const socket = new WebSocket("ws://127.0.0.1:" + port + "/s/LC?b=" + ping.build + "&token=tk:" + ticket,
        { headers: { Origin: address } });
      const timeout = setTimeout(() => { socket.terminate(); reject(new Error("WebSocket nao recebeu handshake")); }, 3500);
      socket.once("message", frame => { clearTimeout(timeout); assert.ok(frame.length > 8); resolve(socket); });
      socket.once("error", reject);
    });
    ws.terminate();
  } finally {
    if (child && child.exitCode === null) {
      child.kill("SIGTERM");
      await Promise.race([new Promise(resolve => child.once("close", resolve)), sleep(3500)]);
      if (child.exitCode === null) child.kill("SIGKILL");
    }
    rmSync(dir, { recursive: true, force: true });
  }
});
