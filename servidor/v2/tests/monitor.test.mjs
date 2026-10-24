// SPDX-License-Identifier: AGPL-3.0-only
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { createRoom, newRoom } from "../core/config.mjs";
import { RoomSupervisor } from "../core/supervisor.mjs";
import { scanRooms, summarizeStatus, statusKey, statusText } from "../core/monitor.mjs";

const root=fileURLToPath(new URL("../../../",import.meta.url));
const manager=path.join(root,"servidor/v2/manager.mjs");
const makeDir=()=>fs.mkdtempSync(path.join(os.tmpdir(),"mooio-v2-monitor-"));

test("status totals, offline and JSON are stable and never show room code",async()=>{
  const entries=[
    {id:"normal",room:newRoom({name:"Normal",port:14550,capacity:40})},
    {id:"mods",room:newRoom({name:"Modded",port:14551,capacity:25,preset:"custom",mods:["mais-lobos"]})}
  ];
  const report=await scanRooms(entries,{probe:async entry=>{
    if(entry.id==="normal")return {id:entry.id,name:entry.room.name,host:entry.room.host,port:entry.room.port,online:true,
      players:10,capacity:40,mods:0,bots:0};
    throw Error("Conexao recusada");
  }});
  assert.deepEqual(report.totals,{rooms:2,online:1,offline:1,players:10,capacity:65});
  assert.equal(report.healthy,false);
  assert.equal(report.rooms[1].reason,"Conexao recusada");
  assert.match(statusText(report),/ONLINE normal/);
  assert.match(statusText(report),/OFFLINE mods/);
  assert.doesNotMatch(JSON.stringify(report),new RegExp(entries[0].room.roomCode+"|"+entries[1].room.roomCode));
  assert.equal(statusKey(report),statusKey({...report,timestamp:"2100-01-01T00:00:00Z"}));
  const good=summarizeStatus(report.rooms.map(item=>({...item,online:true})),{time:new Date("2026-10-23T00:00:00Z")});
  assert.equal(good.healthy,true);
  assert.equal(good.timestamp,"2026-10-23T00:00:00.000Z");
});

test("CLI status --json retorna relatorio offline, health --json sai com erro verificavel",()=>{
  const dir=makeDir();
  try{
    const room=newRoom({name:"Teste fora do ar",port:15889});
    createRoom(path.join(dir,"normal.json"),room);
    const invoke=(cmd,extra=[])=>spawnSync(process.execPath,[manager,cmd,"--rooms",dir,"--json",...extra],{cwd:root,encoding:"utf8",timeout:15000});
    const status=invoke("status");
    assert.equal(status.status,0,status.stderr);
    const json=JSON.parse(status.stdout);
    assert.equal(json.healthy,false);
    assert.equal(json.totals.offline,1);
    assert.equal(json.rooms[0].id,"normal");
    assert.doesNotMatch(status.stdout,new RegExp(room.roomCode));
    const health=invoke("health");
    assert.equal(health.status,1,health.stderr);
    assert.equal(JSON.parse(health.stdout).healthy,false);
    const invalid=invoke("status",["--interval","2"]);
    assert.notEqual(invalid.status,0);
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

test("watchdog distinguishes failed health checks, resets on success, and restarts only unhealthy worker",async()=>{
  const rooms=[
    {id:"normal",room:{host:"127.0.0.1",port:18011,capacity:20}},
    {id:"broken",room:{host:"127.0.0.1",port:18012,capacity:30}}
  ];
  const terminated=[],logs=[],sequence=[false,false,true,false,false,false];
  const supervisor=new RoomSupervisor(rooms,{
    clock:()=>50000,startupGraceMs:0,watchdogFailures:3,
    logger:msg=>logs.push(msg),
    terminateProcess:(child,force)=>terminated.push({id:child.id,force:!!force}),
    probe:async entry=>({online:entry.id==="normal"?true:sequence.shift()??false})
  });
  for(const state of supervisor.states.values()){
    state.child={id:state.entry.id,exitCode:null,signalCode:null};
    state.startedAt=0;
  }
  const broken=supervisor.states.get("broken");
  for(let i=0;i<3;i++)await supervisor.pollHealth();
  assert.equal(terminated.length,0,"successful third probe must reset misses");
  for(let i=0;i<3;i++)await supervisor.pollHealth();
  assert.deepEqual(terminated,[{id:"broken",force:false}]);
  assert.equal(broken.restartRequested,true);
  await supervisor.pollHealth();
  assert.equal(terminated.length,1,"restart should happen only once per process");
  assert.equal(supervisor.states.get("normal").misses,0);
  assert.ok(logs.some(msg=>msg.includes("Watchdog")));
  if(broken.forceTimer)clearTimeout(broken.forceTimer);
  supervisor.closing=true;
});

test("watchdog discards stale probes from a process that exited or was replaced",async()=>{
  const entry={id:"old",room:{host:"127.0.0.1",port:18044,capacity:40}};
  let resolveProbe;
  const sup=new RoomSupervisor([entry],{
    clock:()=>1000,startupGraceMs:0,watchdogFailures:1,
    probe:()=>new Promise(resolve=>{resolveProbe=resolve;}),
    terminateProcess:()=>assert.fail("stale response must not kill a new worker")
  });
  const state=sup.states.get("old"),old={id:"old",exitCode:null,signalCode:null};
  state.child=old;
  state.startedAt=0;
  const poll=sup.pollHealth();
  state.child={id:"new",exitCode:null,signalCode:null};
  resolveProbe({online:false});
  await poll;
  assert.equal(state.misses,0);
  sup.closing=true;
});
