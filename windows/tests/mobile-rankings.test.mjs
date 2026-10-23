import test from "node:test";
import assert from "node:assert/strict";
import { buildCategoryRanking, RANK_CATEGORIES } from "../server/src/moomoo/mobileRankings.js";
import { handlePacket } from "../server/src/network/packets.js";

function member(sid,values={}) {
  return {sid,spawned:true,alive:true,points:0,health:100,food:0,wood:0,
    stone:0,kills:0,shadowed:false,anon:false,role:0,
    shownName(viewer) { return this.anon && this !== viewer ? "Anon" : "Player"+sid; },
    send:()=>{},anticheat:{invalid:()=>{throw Error("unexpected invalid")}},
    ...values};
}
test("Top 10 per gold health food wood stone kills and points uses server values",()=>{
  const viewer=member(1,{points:20,health:70,wood:5});
  const second=member(2,{points:300,health:22,wood:200,food:99,stone:15,kills:6});
  for (const category of RANK_CATEGORIES) {
    const result=buildCategoryRanking([viewer,second],viewer,category);
    assert.equal(result.length,6);
    assert.ok(result[0]===1 || result[0]===2);
    if(category==="wood") assert.deepEqual(result.slice(0,3),[2,"Player2",200]);
    if(category==="health") assert.deepEqual(result.slice(0,3),[1,"Player1",70]);
  }
});
test("Top 10 hides shadowed, respects anonymous display, maximum 10",()=>{
  const viewer=member(1);
  const hidden=member(10,{points:999999,shadowed:true});
  const anonymous=member(11,{points:500,anon:true});
  const others=Array.from({length:20},(_,i)=>member(20+i,{points:100+i}));
  const entries=buildCategoryRanking([viewer,hidden,anonymous,...others],viewer,"gold");
  assert.equal(entries.length,30);
  assert.ok(!entries.includes(10));
  assert.equal(entries[1],"Anon");
  assert.throws(()=>buildCategoryRanking([viewer],viewer,"password"),RangeError);
});
test("ranking request returns only requested category and enforces one-second cooldown",()=>{
  const viewer=member(1,{points:99}),ally=member(2,{food:80,points:88});
  const sent=[];
  viewer.send=(...args)=>sent.push(args);
  const ctx={game:{players:[viewer,ally]}};
  handlePacket(ctx,viewer,"Y",["food"]);
  assert.deepEqual(sent[0],[ "n","food",[2,"Player2",80,1,"Player1",0] ]);
  handlePacket(ctx,viewer,"Y",["wood"]);
  assert.equal(sent.length,1);
});
