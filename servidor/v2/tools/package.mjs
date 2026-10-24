#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Build once, deliver a self-contained Node.js dedicated server source+dependencies.
// A Node.js runtime is still required; no downloads occur when starting the server.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../../../", import.meta.url));
const source = path.join(root, "servidor/v2");
const target = path.join(source, "dist/Moo-IO-Servidor-V2");
const server = path.join(root, "windows/server");

for (const expected of [
  "src/index.js", "package.json", "node_modules/express/package.json", "node_modules/ws/package.json"
]) {
  if (!fs.existsSync(path.join(server, expected))) {
    throw new Error("Falta " + expected + ". Instale dependencias em windows/server ANTES de empacotar.");
  }
}
fs.rmSync(target, { force: true, recursive: true });
fs.mkdirSync(path.join(target, "windows/server"), { recursive: true });
fs.mkdirSync(path.join(target, "windows/shared"), { recursive: true });
fs.mkdirSync(path.join(target, "servidor/v2"), { recursive: true });
fs.cpSync(path.join(server, "src"), path.join(target, "windows/server/src"), { recursive: true });
fs.cpSync(path.join(server, "node_modules"), path.join(target, "windows/server/node_modules"), { recursive: true });
fs.copyFileSync(path.join(server, "package.json"), path.join(target, "windows/server/package.json"));
// Keep the parent CommonJS package boundary: windows/shared/*.js uses module.exports.
// Without windows/package.json, Node 22 syntax-detects these files as ESM.
fs.copyFileSync(path.join(root, "windows/package.json"), path.join(target, "windows/package.json"));
fs.cpSync(path.join(root, "windows/shared"), path.join(target, "windows/shared"), { recursive: true });
for (const name of ["cli.mjs", "package.json", "README.md"]) {
  fs.copyFileSync(path.join(source, name), path.join(target, "servidor/v2", name));
}
fs.cpSync(path.join(source, "lib"), path.join(target, "servidor/v2/lib"), { recursive: true });
fs.cpSync(path.join(source, "tests"), path.join(target, "servidor/v2/tests"), { recursive: true });
// Preserve upstream and project redistribution notices in every offline artifact.
for (const name of ["LICENSE", "NOTICE.md"]) {
  fs.copyFileSync(path.join(root, name), path.join(target, name));
}
fs.cpSync(path.join(root, "windows/licenses"), path.join(target, "windows/licenses"), { recursive: true });
for (const [name, command] of [
  ["CRIAR-SERVIDOR.cmd", "init"],
  ["INICIAR-SERVIDOR.cmd", "start"],
  ["DIAGNOSTICAR-SERVIDOR.cmd", "doctor"]
]) {
  fs.writeFileSync(path.join(target, name),
    '@echo off\r\ncd /d "%~dp0"\r\nnode servidor\\v2\\cli.mjs ' + command + ' %*\r\nif errorlevel 1 pause\r\n');
}
for (const [name, command] of [
  ["criar-servidor.sh", "init"],
  ["iniciar-servidor.sh", "start"]
]) {
  const dest = path.join(target, name);
  fs.writeFileSync(dest, '#!/bin/sh\ncd "$(dirname "$0")"\nexec node servidor/v2/cli.mjs ' + command + ' "$@"\n');
  fs.chmodSync(dest, 0o755);
}
fs.writeFileSync(path.join(target, "LEIA-ME.txt"),
  "MOO-IO SERVIDOR V2\n\nRequer Node.js >=20 instalado.\n" +
  "1) node servidor/v2/cli.mjs init --host 127.0.0.1\n" +
  "2) node servidor/v2/cli.mjs doctor\n" +
  "3) node servidor/v2/cli.mjs start\n\n" +
  "Para LAN, informe no init o IPv4 privado do seu computador.\n" +
  "Nao exponha esta versao diretamente a internet.\n");
console.log("Pacote pronto: " + target);
