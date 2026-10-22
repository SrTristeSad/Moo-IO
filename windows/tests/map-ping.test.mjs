import test from "node:test";
import assert from "node:assert/strict";
import { handlePacket } from "../server/src/network/packets.js";
import { config } from "../server/src/moomoo/config.js";

test("map point ping reaches only owner and teammates and uses cooldown",()=>{
  const got=[];
  const make=(id,team)=>({id,team,alive:true,pingCooldown:0,
    send:(name,...args)=>got.push({id,name,args}),
    anticheat:{invalid:()=>{throw Error("unexpected invalid")}}});
  const sender=make(1,"alpha");
  const friend=make(2,"alpha");
  const rival=make(3,"beta");
  const ctx={game:{players:[sender,friend,rival]}};
  handlePacket(ctx,sender,"U",[config.mapScale*.25,config.mapScale*.75]);
  assert.deepEqual(got.map(v=>v.id),[1,2]);
  assert.ok(got.every(v=>v.name==="9"));
  assert.deepEqual(got[0].args,[
    Math.round(config.mapScale*.25),
    Math.round(config.mapScale*.75)]);
  assert.equal(sender.pingCooldown,config.mapPingTime);
  handlePacket(ctx,sender,"U",[10,10]);
  assert.equal(got.length,2);
});
test("map point ping rejects forged coordinates before cooldown",()=>{
  let strikes=0;
  const player={alive:true,pingCooldown:0,team:null,
    anticheat:{invalid:()=>{strikes++}},
    send:()=>{throw Error("should not send")}};
  const ctx={game:{players:[player]}};
  for(const args of [
    [-1,1],[config.mapScale+1,5],
    [1,Infinity],["5",3],[3],[NaN,3]
  ]) handlePacket(ctx,player,"U",args);
  assert.equal(strikes,6);
  assert.equal(player.pingCooldown,0);
});
