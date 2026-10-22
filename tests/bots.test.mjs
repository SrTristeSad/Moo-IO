import test from "node:test";
import assert from "node:assert/strict";
import { Game } from "../server/src/moomoo/server.js";
import { parseBotCount,RoomBots,BOT_LIMIT } from "../server/src/mooio/bots.js";

test("Bot configuration is disabled by default and rejects oversized values",()=>{
  assert.equal(parseBotCount(undefined),0);
  assert.equal(parseBotCount("0"),0);
  assert.equal(parseBotCount("3"),3);
  assert.equal(parseBotCount("8"),BOT_LIMIT);
  for (const value of ["-1","9","1.5","x","",undefined].filter(v=>v!==""
      && v!==undefined)) {
    assert.throws(()=>parseBotCount(value),/MOO_IO_BOT_COUNT/);
  }
});
test("Room bots spawn as real authoritative players with unique sids",()=>{
  const game=new Game({key:"TEST",name:"TEST",capacity:40,membersOnly:false,botCount:3});
  try{
    assert.ok(game.bots instanceof RoomBots);
    assert.equal(game.bots.agents.length,3);
    assert.equal(game.players.length,3);
    assert.equal(game.playerCount(),0,"Artificial players must not consume human capacity");
    const ids=new Set(game.bots.agents.map(a=>a.p.sid));
    assert.equal(ids.size,3);
    for(const agent of game.bots.agents){
      assert.equal(agent.p.isBot,true);
      assert.equal(agent.p.alive,true);
      assert.equal(agent.p.spawned,true);
      assert.match(agent.p.name,/^Bot /);
      assert.ok(agent.p.isPlayer);
      assert.equal(typeof agent.p.gather,"function");
      assert.equal(typeof agent.p.buildItem,"function");
    }
    const human=game.addPlayer({send:()=>{},ip:"127.0.0.1",id:"human-for-test"});
    assert.ok(human);
    human.setUserData({name:"Human Tester"});
    human.spawn(false);
    assert.equal(game.playerCount(),1);
    const a=game.bots.agents[0];
    human.x=a.p.x+110;human.y=a.p.y+5;
    for(const enemy of game.ais){enemy.active=false;}
    game.game_objects.length=0;
    game.bots.tick(300);
    assert.ok(Number.isFinite(a.p.dir),"Bot must aim at a real nearby player");
    assert.ok(a.p.moveDir!==undefined,"Bot must actively navigate near its opponent");
    a.p.health=24;a.p.food=20;
    game.bots.tick(300);
    assert.equal(a.p.moveDir!==undefined,true,"Low health should trigger retreat");
    a.p.health=0;a.p.alive=false;
    game.bots.tick(5000);
    assert.ok(a.p.alive,"Dead bot must respawn in same authoritative player slot");
    assert.equal(a.p.sid,[...ids][0]);
  }finally{game.stop();}
});
