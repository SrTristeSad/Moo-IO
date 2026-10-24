// SPDX-License-Identifier: AGPL-3.0-only
// Shared, read-only mod preflight for the CLI and the multi-room supervisor.
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { buildPlan } from "./mods.mjs";
import { readModFile } from "./config.mjs";

const root=fileURLToPath(new URL("../../../",import.meta.url));
const requireShared=createRequire(path.join(root,"windows/shared/config.js"));

export async function planRoom(room){
  const config=requireShared(path.join(root,"windows/shared/config.js"));
  const items=requireShared(path.join(root,"windows/shared/config/items.js"));
  const { AI_TYPES }=await import(new URL("../../../windows/server/src/moomoo/modules/aiManager.js",import.meta.url));
  const mods=room.mods.map(id=>{
    const manifest=readModFile(id);
    if(manifest.id!==id)throw Error("ID do arquivo e do manifesto nao coincidem: "+id);
    return manifest;
  });
  return {plan:buildPlan(mods,{config,items,aiTypes:AI_TYPES}),mods};
}
