// SPDX-License-Identifier: AGPL-3.0-only
// Room settings are independent from gameplay mod definitions.
import fs from "node:fs";
import path from "node:path";
import { randomBytes } from "node:crypto";
import { allowedRoomInterface } from "../../../windows/server/src/mooio/network.js";
import { validRoomCode } from "../../../windows/server/src/mooio/invite.js";

export const V2_ROOT = path.resolve(import.meta.dirname || path.dirname(new URL(import.meta.url).pathname), "..");
export const DEFAULT_ROOM = path.join(V2_ROOT, "rooms", "principal.json");
export const MOD_DIR = path.join(V2_ROOT, "mods");
export const MOD_ID = /^[a-z0-9][a-z0-9-]{1,47}$/;
export const DEFAULTS = {schemaVersion:1,name:"Minha sala",preset:"traditional",host:"127.0.0.1",port:8080,network:"lan",capacity:40,bots:0,difficulty:"normal",mods:[]};

function jsonFile(filename, limit=65536) {
  const stat = fs.lstatSync(filename);
  if (!stat.isFile() || stat.size > limit) throw new Error("Arquivo invalido/grande demais: " + filename);
  return JSON.parse(fs.readFileSync(filename,"utf8"));
}
export function validateRoom(room) {
  if (!room || typeof room !== "object" || Array.isArray(room)) throw new Error("Sala deve ser um objeto JSON.");
  const keys=["schemaVersion","name","preset","host","port","network","capacity","bots","difficulty","roomCode","mods"];
  for (const key of Object.keys(room)) if (!keys.includes(key)) throw new Error("Opcao desconhecida na sala: "+key);
  if(room.schemaVersion!==1) throw new Error("schemaVersion deve ser 1");
  if(typeof room.name!=="string" || !room.name.trim() || room.name.length>60) throw new Error("name invalido");
  if(!["traditional","custom"].includes(room.preset)) throw new Error("preset deve ser traditional ou custom");
  if(!["lan","vpn"].includes(room.network)) throw new Error("network deve ser lan ou vpn (VPS publica ainda requer proxy seguro)");
  if(!allowedRoomInterface(room.host,room.network)) throw new Error("host deve ser endereco IPv4 privado atribuido a interface LAN/VPN; nao use IP publico nem 0.0.0.0");
  if(!Number.isInteger(room.port)||room.port<1024||room.port>65534) throw new Error("port deve estar entre 1024 e 65534");
  if(!Number.isInteger(room.capacity)||room.capacity<1||room.capacity>40) throw new Error("capacity deve estar entre 1 e 40");
  if(!Number.isInteger(room.bots)||room.bots<0||room.bots>8) throw new Error("bots deve estar entre 0 e 8");
  if(!["normal","dificil","extremo"].includes(room.difficulty||"normal"))throw new Error("difficulty invalida");
  if(room.difficulty===undefined)room={...room,difficulty:"normal"};
  if(!validRoomCode(room.roomCode)) throw new Error("roomCode invalido");
  if(!Array.isArray(room.mods)||room.mods.length>32||room.mods.some(id=>typeof id!=="string"||!MOD_ID.test(id))||new Set(room.mods).size!==room.mods.length) throw new Error("mods: lista invalida ou repetida");
  if(room.preset==="traditional"&&room.mods.length) throw new Error("Sala traditional nao ativa mods; escolha preset custom");
  return room;
}
export function newRoom(fields={}) {
  return validateRoom({...DEFAULTS,...fields, roomCode:randomBytes(18).toString("hex")});
}
export function readRoom(filename=DEFAULT_ROOM) { return validateRoom(jsonFile(filename)); }
export function createRoom(filename,room) {
  validateRoom(room);
  fs.mkdirSync(path.dirname(filename), {recursive:true});
  fs.writeFileSync(filename,JSON.stringify(room,null,2)+"\n",{flag:"wx",mode:0o600});
}
export function updateRoom(filename,room) {
  validateRoom(room);
  const folder=path.dirname(filename);
  const temp=path.join(folder,"."+path.basename(filename)+"."+process.pid+".tmp");
  fs.writeFileSync(temp, JSON.stringify(room,null,2)+"\n", {flag:"wx",mode:0o600});
  try { fs.renameSync(temp,filename); } finally { if(fs.existsSync(temp)) fs.unlinkSync(temp); }
}
export function roomDataPath(filename) {
  return path.resolve(path.dirname(filename),"data",path.basename(filename,".json"));
}
export function readModFile(id) {
  if(!MOD_ID.test(id)) throw new Error("ID de mod invalido");
  const file=path.join(MOD_DIR,id+".json");
  const stat=fs.lstatSync(file);
  if(!stat.isFile()||stat.isSymbolicLink()||stat.size>65536) throw new Error("Mod invalido: "+id);
  return jsonFile(file);
}
export function listMods() {
  if(!fs.existsSync(MOD_DIR)) return [];
  return fs.readdirSync(MOD_DIR).filter(p=>p.endsWith(".json")&&MOD_ID.test(p.slice(0,-5))).map(p=>p.slice(0,-5)).sort();
}
