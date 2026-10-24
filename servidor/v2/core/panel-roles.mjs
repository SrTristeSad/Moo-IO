// SPDX-License-Identifier: AGPL-3.0-only
// Staff grants for the localhost panel; owner is always a separate account.
import fs from "node:fs";
import path from "node:path";
import {randomBytes} from "node:crypto";
import {normalizeEmail} from "../../../windows/server/src/api/credentials.js";
export const STAFF_ROLES=["viewer","moderator"];
export const OWNER_EMAIL="admin@panel.invalid";
const ID=/^[a-z0-9_.+%-]+@[a-z0-9.-]+\.[a-z]{2,}$/;
export function readStaffRoles(privateDir){
  const file=path.join(privateDir,"staff-roles.json");
  if(!fs.existsSync(file))return {};
  const stat=fs.lstatSync(file);
  if(!stat.isFile()||stat.isSymbolicLink()||stat.size>16384||
     (process.platform!=="win32"&&(stat.mode&0o077)!==0))
    throw Error("Papeis administrativos armazenados de forma insegura");
  const data=JSON.parse(fs.readFileSync(file,"utf8"));
  if(data?.schemaVersion!==1||!data.roles||typeof data.roles!=="object"||Array.isArray(data.roles))
    throw Error("Formato de papeis administrativos invalido");
  for(const [key,role] of Object.entries(data.roles))
    if(!ID.test(key)||key===OWNER_EMAIL||!STAFF_ROLES.includes(role))
      throw Error("Papeis administrativos invalidos");
  return data.roles;
}
export function setStaffRole(privateDir,email,role){
  const key=normalizeEmail(email);
  if(!key||key===OWNER_EMAIL||!STAFF_ROLES.includes(role)&&role!=="revoke")
    throw Error("Email ou permissao invalida (viewer/moderator/revoke)");
  const roles=readStaffRoles(privateDir);
  if(role==="revoke")delete roles[key];else roles[key]=role;
  if(Object.keys(roles).length>20)throw Error("Limite de 20 contas de equipe");
  const file=path.join(privateDir,"staff-roles.json");
  const tmp=file+"."+randomBytes(6).toString("hex")+".tmp";
  fs.writeFileSync(tmp,JSON.stringify({schemaVersion:1,roles},null,2)+"\n",{flag:"wx",mode:0o600});
  try{fs.renameSync(tmp,file);}finally{if(fs.existsSync(tmp))fs.unlinkSync(tmp)}
}
export const CAN={
  viewer:new Set(["overview","players","history"]),
  moderator:new Set(["overview","players","history","bans","kick","ban","unban"]),
  owner:new Set(["overview","players","history","bans","kick","ban","unban","rooms","mods","restart","start","stop","events"])
};
export function can(role,permission){return !!CAN[role]?.has(permission);}
