import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, existsSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { createConfig, instancePaths, readConfig, saveNewConfig, validateConfig } from "../lib/config.mjs";

test("V2 create: codigo seguro e regras do motor", () => {
  const c = createConfig();
  assert.equal(c.version, 2);
  assert.equal(c.host, "127.0.0.1");
  assert.match(c.roomCode, /^[a-f0-9]{36}$/);
  assert.deepEqual(validateConfig(c), c);
});
test("V2 bloqueia host publico e 0.0.0.0", () => {
  for (const host of ["0.0.0.0", "8.8.8.8", "169.254.10.2", "::", "localhost", "192.168.1.256"]) {
    assert.throws(() => createConfig({ host }), /IP proibido/);
  }
  assert.equal(createConfig({ host: "192.168.1.25" }).host, "192.168.1.25");
  assert.equal(createConfig({ host: "100.70.1.3", mode: "vpn" }).mode, "vpn");
  assert.throws(() => createConfig({ host: "100.70.1.3", mode: "lan" }), /IP proibido/);
});
test("V2 rejeita porta, bots, versao e codigo fora dos limites", () => {
  for (const port of [0, 1023, 65535, 8080.5, NaN]) assert.throws(() => createConfig({ port }), /port/);
  for (const bots of [-1, 9, 2.5, NaN]) assert.throws(() => createConfig({ bots }), /bots/);
  assert.throws(() => validateConfig({ ...createConfig(), version: 1 }), /V2/);
  assert.throws(() => validateConfig({ ...createConfig(), roomCode: "abc" }), /roomCode/);
});
test("V2 nao sobrescreve a configuracao; dados isolados", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "mooio-v2-config-"));
  try {
    const file = path.join(dir, "first", "server.json");
    const config = createConfig({ bots: 2 });
    saveNewConfig(file, config);
    assert.equal(existsSync(file), true);
    assert.deepEqual(readConfig(file), config);
    assert.throws(() => saveNewConfig(file, createConfig()), /EEXIST/);
    assert.equal(JSON.parse(readFileSync(file, "utf8")).roomCode, config.roomCode);
    assert.equal(instancePaths(file).data, path.join(dir, "first", "data"));
    assert.notEqual(instancePaths(path.join(dir, "second", "server.json")).data, instancePaths(file).data);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
