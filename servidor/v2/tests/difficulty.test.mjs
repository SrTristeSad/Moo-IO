import test from "node:test";
import assert from "node:assert/strict";
import {createRequire} from "node:module";
import {fileURLToPath} from "node:url";
import path from "node:path";
import {applyDifficulty} from "../core/difficulty.mjs";
import {newRoom,validateRoom} from "../core/config.mjs";
const root=fileURLToPath(new URL("../../../",import.meta.url));
const requireEngine=createRequire(path.join(root,"windows/shared/config.js"));
const config=requireEngine(path.join(root,"windows/shared/config.js"));
const {AI_TYPES}=await import(new URL("../../../windows/server/src/moomoo/modules/aiManager.js",import.meta.url));
function clone(){
 return {config:{...config,server:{...config.server,
   animalSpawnPlan:config.server.animalSpawnPlan.map(row=>({...row}))}},
   aiTypes:AI_TYPES.map(type=>({...type}))};
}
test("dificuldades validas e sala V2 legada recebe normal",()=>{
 const base=newRoom();
 assert.equal(base.difficulty,"normal");
 assert.equal(validateRoom({...base,difficulty:"extremo"}).difficulty,"extremo");
 assert.throws(()=>validateRoom({...base,difficulty:"caos"}),/difficulty/);
 const legacy={...base};delete legacy.difficulty;
 assert.equal(validateRoom(legacy).difficulty,"normal");
});
test("normal preserva estatisticas originais",()=>{
 const game=clone(),before=JSON.stringify(game);
 assert.deepEqual(applyDifficulty("normal",game),[]);
 assert.equal(JSON.stringify(game),before);
});
test("mais mobs e agressividade nos presets, sem alterar boss ou dados globais",()=>{
 const a=clone(),b=clone();
 applyDifficulty("dificil",a);
 applyDifficulty("extremo",b);
 assert.ok(a.aiTypes[4].dmg>AI_TYPES[4].dmg);
 assert.ok(b.aiTypes[4].dmg>a.aiTypes[4].dmg);
 assert.ok(b.aiTypes[4].viewRange>a.aiTypes[4].viewRange);
 const wolves=entry=>entry.config.server.animalSpawnPlan.find(row=>row.index===4).desired;
 assert.ok(wolves(a)>=wolves(clone()));
 assert.ok(wolves(b)>=wolves(a));
 assert.equal(b.aiTypes[11].health,AI_TYPES[11].health);
 assert.equal(b.aiTypes[11].dmg,AI_TYPES[11].dmg);
 assert.equal(config.server.animalSpawnPlan.find(row=>row.index===4).desired,wolves(clone()));
});
