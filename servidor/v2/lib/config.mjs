// SPDX-License-Identifier: AGPL-3.0-only
// Dedicated V2 instance configuration. Rules stay aligned with the actual engine.
import fs from "node:fs";
import path from "node:path";
import { randomBytes } from "node:crypto";
import { allowedRoomInterface } from "../../../windows/server/src/mooio/network.js";
import { validRoomCode } from "../../../windows/server/src/mooio/invite.js";

export const DEFAULTS = Object.freeze({ version: 2, host: "127.0.0.1", port: 8080, mode: "lan", bots: 0 });

export function validateConfig(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("Configuracao invalida.");
  const c = { ...input };
  if (c.version !== 2) throw new Error("A configuracao precisa ser da V2.");
  if (!["lan", "vpn"].includes(c.mode)) throw new Error("mode deve ser lan ou vpn.");
  if (!allowedRoomInterface(c.host, c.mode)) {
    throw new Error("IP proibido: use IPv4 de loopback/LAN ou interface VPN privada permitida, nunca IP publico ou 0.0.0.0.");
  }
  if (!Number.isInteger(c.port) || c.port < 1024 || c.port > 65534) {
    throw new Error("port deve ser inteiro entre 1024 e 65534.");
  }
  if (!Number.isInteger(c.bots) || c.bots < 0 || c.bots > 8) {
    throw new Error("bots deve ser inteiro entre 0 e 8.");
  }
  if (!validRoomCode(c.roomCode)) throw new Error("roomCode deve ter 8 a 64 letras, numeros ou hifens.");
  return { version: 2, host: c.host, port: c.port, mode: c.mode, bots: c.bots, roomCode: c.roomCode };
}

export function createConfig(input = {}) {
  return validateConfig({ ...DEFAULTS, ...input, roomCode: randomBytes(18).toString("hex") });
}

export function readConfig(filename) {
  let value;
  try { value = JSON.parse(fs.readFileSync(filename, "utf8")); }
  catch (error) { throw new Error("Nao foi possivel ler configuracao " + filename + ": " + error.message); }
  return validateConfig(value);
}

export function saveNewConfig(filename, config) {
  const value = validateConfig(config);
  fs.mkdirSync(path.dirname(filename), { recursive: true });
  // wx: never overwrite a room code or another server's configuration.
  fs.writeFileSync(filename, JSON.stringify(value, null, 2) + "\n", { encoding: "utf8", flag: "wx", mode: 0o600 });
  return filename;
}

export function instancePaths(filename) {
  const data = path.join(path.dirname(path.resolve(filename)), "data");
  return { data, protocol: path.join(data, "protocol-build.json") };
}
