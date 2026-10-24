import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs";
import os from "node:os";
import { buildPlan, applyPlan, validateManifest } from "../core/mods.mjs";
import { newRoom, validateRoom, readModFile, listMods, createRoom, readRoom } from "../core/config.mjs";

const root=fileURLToPath(new URL("../../../",import.meta.url));
const requireConfig=createRequire(path.join(root,"windows/shared/config.js"));
const reference=requireConfig(path.join(root,"windows/shared/config.js"));
const items=requireConfig(path.join(root,"windows/shared/config/items.js"));
const {AI_TYPES}=await import(new URL("../../../windows/server/src/moomoo/modules/aiManager.js",import.meta.url));
function clone(){
  return {config: { ...reference, server:{...reference.server,animalSpawnPlan:reference.server.animalSpawnPlan.map(x=>({...x}))}},
    items: {weapons:items.weapons.map(x=>({...x})),list:items.list.map(x=>({...x}))}, aiTypes:AI_TYPES.map(x=>({...x}))};
}
test("presets e codigo seguro; tradicional imutavel",()=>{
  const room=newRoom();
  assert.match(room.roomCode,/^[0-9a-f]{36}$/);
  assert.equal(room.capacity,40);
  assert.equal(room.preset,"traditional");
  assert.throws(()=>validateRoom({...room,mods:["mais-lobos"]}),/traditional/);
  assert.throws(()=>validateRoom({...room,host:"0.0.0.0"}),/host/);
  assert.throws(()=>validateRoom({...room,host:"8.8.8.8"}),/host/);
  assert.throws(()=>validateRoom({...room,capacity:400}),/capacity/);
});
test("mods reais no motor: mundo, vaca, wolf, plano de spawn",()=>{
  const catalog=clone(), plans=buildPlan([readModFile("colheita-farta"),readModFile("mais-lobos")],catalog);
  const result=applyPlan(plans);
  assert.equal(catalog.config.treesPerArea,15);
  assert.equal(catalog.config.totalRocks,60);
  assert.equal(catalog.aiTypes[0].health,650);
  assert.equal(catalog.aiTypes[4].health,1000);
  assert.equal(catalog.config.server.animalSpawnPlan.find(x=>x.index===4).desired,15);
  assert.equal(result.length,7);
  assert.equal(reference.treesPerArea,9,"referencia nao deve ser modificada por teste");
});
test("nao aplica parcialmente mods invalidos ou conflitos",()=>{
  const catalog=clone();
  const m=readModFile("colheita-farta");
  const conflicting={schemaVersion:1,id:"outro-mod",name:"Outro",requiresClient:"base",changes:{world:{treesPerArea:2}}};
  assert.throws(()=>buildPlan([m,conflicting],catalog),/Conflito/);
  assert.equal(catalog.config.treesPerArea,9);
  assert.throws(()=>buildPlan([{...m,changes:{world:{foo:4}}}],catalog),/nao suportada/);
  assert.throws(()=>buildPlan([{...m,changes:{weapons:{"999":{dmg:1}}}}],catalog),/inexistente/);
  assert.throws(()=>buildPlan([{...m,changes:{animals:{"0":{health:-2}}}}],catalog),/intervalo/);
  assert.throws(()=>buildPlan([{...m,changes:{scripts:{"x":{evil:1}}}}],catalog),/desconhecido/);
  assert.throws(()=>validateManifest({...m, requiresClient:"dynamic"}),/base/);
  assert.throws(()=>validateManifest({...m, entrypoint:"run.js"}),/desconhecido/);
});
test("mods/arquivos nao podem escapar da pasta",()=>{
  assert.ok(listMods().includes("mais-lobos"));
  assert.throws(()=>readModFile("../private"),/invalido/);
  assert.throws(()=>readModFile("__proto__"),/invalido/);
});
test("cria sala e nao sobrescreve configuracao existente",()=>{
  const folder=fs.mkdtempSync(path.join(os.tmpdir(),"mooio-v2-"));
  try{
    const filename=path.join(folder,"sala.json"),r=newRoom({preset:"custom"});
    createRoom(filename,r);
    assert.deepEqual(readRoom(filename),r);
    assert.throws(()=>createRoom(filename,newRoom()),/EEXIST/);
  }finally{fs.rmSync(folder,{recursive:true,force:true});}
});
