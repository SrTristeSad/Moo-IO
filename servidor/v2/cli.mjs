#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Independent dedicated server control, without changing Windows/Android clients.
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { createConfig, instancePaths, readConfig, saveNewConfig } from "./lib/config.mjs";

const ROOT = fileURLToPath(new URL("../../", import.meta.url));
const ENGINE = path.join(ROOT, "windows/server/src/index.js");
const DEFAULT_FILE = fileURLToPath(new URL("./instance/server.json", import.meta.url));

function options(args) {
  const out = {};
  for (let i = 0; i < args.length; i += 2) {
    const key = args[i], value = args[i + 1];
    if (!key?.startsWith("--") || !value || value.startsWith("--")) {
      throw new Error("Use pares --opcao valor. Ex.: --host 192.168.1.10");
    }
    const name = key.slice(2);
    if (!["config", "host", "port", "mode", "bots"].includes(name) || Object.hasOwn(out, name)) {
      throw new Error("Opcao desconhecida ou repetida: " + key);
    }
    out[name] = value;
  }
  return out;
}
function filename(opts) { return path.resolve(opts.config || DEFAULT_FILE); }
function noExtras(opts) {
  for (const key of ["host", "port", "mode", "bots"]) {
    if (opts[key] !== undefined) throw new Error("--" + key + " so pode ser usado no init.");
  }
}
function init(opts) {
  const configFile = filename(opts);
  const values = {};
  if (opts.host !== undefined) values.host = opts.host;
  if (opts.mode !== undefined) values.mode = opts.mode;
  if (opts.port !== undefined) values.port = Number(opts.port);
  if (opts.bots !== undefined) values.bots = Number(opts.bots);
  const config = createConfig(values);
  saveNewConfig(configFile, config);
  console.log("Servidor V2 criado: " + configFile);
  console.log("Endereco: " + config.host + ":" + config.port + " (" + config.mode + ")");
  console.log("Bots: " + config.bots);
  console.log("Codigo privado da sala: " + config.roomCode);
  console.log("Iniciar: node servidor/v2/cli.mjs start --config " + JSON.stringify(configFile));
}
function doctor(opts) {
  noExtras(opts);
  const config = readConfig(filename(opts));
  const checks = [
    ["Motor da partida", ENGINE],
    ["Dependencia Express", path.join(ROOT, "windows/server/node_modules/express")],
    ["Configuracao compartilhada", path.join(ROOT, "windows/shared/config.js")]
  ];
  for (const [name, file] of checks) {
    const exists = fs.existsSync(file);
    console.log((exists ? "[OK] " : "[FALTA] ") + name);
    if (!exists) process.exitCode = 1;
  }
  console.log("Interface: " + config.host + ":" + config.port + " (" + config.mode + "), bots: " + config.bots);
  console.log("Codigo de convite: configurado (nao exibido).");
}
function start(opts) {
  noExtras(opts);
  const config = readConfig(filename(opts));
  if (!fs.existsSync(ENGINE)) throw new Error("Motor de partida ausente; gere o pacote dedicado completo.");
  const paths = instancePaths(filename(opts));
  fs.mkdirSync(paths.data, { recursive: true, mode: 0o700 });
  const env = {
    ...process.env,
    HOST: config.host,
    PORT: String(config.port),
    MOO_IO_NETWORK_MODE: config.mode,
    MOO_IO_ROOM_CODE: config.roomCode,
    MOO_IO_BOT_COUNT: String(config.bots),
    DATA_DIR: paths.data,
    PROTOCOL_BUILD_FILE: paths.protocol,
    MOO_IO_GUI_HOST: "0"
  };
  // Keep each V2 instance isolated, including accounts, bans, tickets and protocol build.
  console.log("Moo-IO Servidor V2 | " + config.host + ":" + config.port + " | bots " + config.bots);
  console.log("Convite da sala: " + config.roomCode);
  const child = spawn(process.execPath, [ENGINE], { cwd: ROOT, env, stdio: "inherit" });
  for (const signal of ["SIGINT", "SIGTERM"]) {
    process.on(signal, () => { if (!child.killed) child.kill(signal); });
  }
  child.on("error", error => { console.error(error.message); process.exitCode = 1; });
  child.on("exit", (code, signal) => { process.exitCode = code === 0 || signal === "SIGINT" || signal === "SIGTERM" ? 0 : (code || 1); });
}
function help() {
  console.log(`Moo-IO — servidor dedicado V2 (Node >=20)
  node servidor/v2/cli.mjs init [--host 127.0.0.1] [--port 8080] [--mode lan|vpn] [--bots 0..8] [--config arquivo]
  node servidor/v2/cli.mjs doctor [--config arquivo]
  node servidor/v2/cli.mjs start [--config arquivo]

Use um IPv4 realmente atribuido ao PC para aceitar amigos na LAN/VPN.
Sem --host, apenas este computador podera conectar (127.0.0.1).
Nao exponha esta versao na internet publica.`);
}

try {
  const command = process.argv[2] || "help";
  const opts = options(process.argv.slice(3));
  if (command === "init" || command === "create") init(opts);
  else if (command === "start") start(opts);
  else if (command === "doctor") doctor(opts);
  else if (command === "help") help();
  else throw new Error("Comando desconhecido: " + command);
} catch (error) {
  console.error("ERRO Servidor V2: " + error.message);
  process.exitCode = 1;
}
