// SPDX-License-Identifier: AGPL-3.0-only
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import net from "node:net";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { newRoom, createRoom, updateRoom } from "../core/config.mjs";
import { discoverRooms, checkRooms, probeRoom } from "../core/supervisor.mjs";

const root=fileURLToPath(new URL("../../../",import.meta.url));
const manager=path.join(root,"servidor/v2/manager.mjs");
const WebSocket=createRequire(path.join(root,"windows/server/package.json"))("ws");
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function freePort(){
  const server=net.createServer();
  await new Promise((resolve,reject)=>server.once("error",reject).listen(0,"127.0.0.1",resolve));
  const port=server.address().port;
  await new Promise(resolve=>server.close(resolve));
  return port;
}
function command(args){
  const p=spawnSync(process.execPath,[manager,...args],{cwd:root,encoding:"utf8",timeout:12000});
  return {exit:p.status,output:p.stdout+"\n"+p.stderr};
}
test("Supervisor preflight: config valida, duas portas distintas, nao expoe codigos",async()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"mooio-v2-manager-preflight-"));
  try{
    const config1=newRoom({name:"Normal",capacity:25,port:await freePort()});
    createRoom(path.join(dir,"normal.json"),config1);
    const original=await checkRooms(discoverRooms(dir));
    assert.equal(original.length,1);
    assert.equal(original[0].room.name,"Normal");
    const status=command(["check","--rooms",dir]);
    assert.equal(status.exit,0,status.output);
    assert.match(status.output,/Configuracao de 1 sala/);
    assert.doesNotMatch(status.output,new RegExp(config1.roomCode));
    const second=newRoom({name:"Mods",preset:"custom",capacity:40,port:config1.port,mods:["mais-lobos"]});
    createRoom(path.join(dir,"mods.json"),second);
    assert.throws(()=>discoverRooms(dir),/Porta duplicada/);
    assert.notEqual(command(["check","--rooms",dir]).exit,0);
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
test("Supervisor: duas salas reais em paralelo, mods isolados, convite e desligamento", {timeout:50000},async()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"mooio-v2-manager-"));
  const firstPort=await freePort();
  let secondPort=await freePort();
  while(secondPort===firstPort)secondPort=await freePort();
  const normal=newRoom({name:"Normal",port:firstPort,capacity:15});
  const modded=newRoom({name:"Mundo dos Lobos",port:secondPort,capacity:24,preset:"custom",mods:["mais-lobos"],publicAccess:true});
  const normalFile=path.join(dir,"normal.json"),moddedFile=path.join(dir,"lobos.json");
  createRoom(normalFile,normal);
  createRoom(moddedFile,modded);
  const pass="correct-horse-battery-454",accounts=[
    {file:normalFile,email:"normal@example.org"},
    {file:moddedFile,email:"lobos@example.org"}
  ];
  for(const {file,email} of accounts){
    const run=spawnSync(process.execPath,[path.join(root,"servidor/v2/accounts.mjs"),
      "set-password","--file",file,"--email",email],{
      cwd:root,input:pass+"\n",encoding:"utf8",timeout:20000
    });
    assert.equal(run.status,0,run.stderr);
  }
  const entries=await checkRooms(discoverRooms(dir));
  let child,logs="",normalSocket;
  const a="http://127.0.0.1:"+firstPort,b="http://127.0.0.1:"+secondPort;
  try{
    child=spawn(process.execPath,[manager,"start","--rooms",dir],{cwd:root,stdio:["ignore","pipe","pipe"]});
    child.stdout.on("data",c=>logs+=c);
    child.stderr.on("data",c=>logs+=c);
    let ready=false,report=[];
    for(let i=0;i<110;i++){
      if(child.exitCode!==null)break;
      report=await Promise.all(entries.map(entry=>probeRoom(entry,{timeout:400})));
      if(report.every(row=>row.online)){ready=true;break;}
      await sleep(160);
    }
    assert.equal(ready,true,"Duas salas nao iniciaram: "+logs.slice(-2500)+" "+JSON.stringify(report));
    const [normStatus,modsStatus]=await Promise.all([fetch(a+"/mooio/status").then(r=>r.json()),fetch(b+"/mooio/status").then(r=>r.json())]);
    assert.deepEqual(normStatus.v2.mods,[]);
    assert.deepEqual(modsStatus.v2.mods,["mais-lobos"]);
    assert.equal(normStatus.v2.animals.wolfHealth,300); // Exact original value from aiManager.js
    assert.equal(modsStatus.v2.animals.wolfHealth,1000);
    assert.equal(normStatus.v2.world.treesPerArea,9);
    assert.equal(modsStatus.v2.world.treesPerArea,9);
    assert.equal(normStatus.v2.capacity,15);
    assert.equal(modsStatus.v2.capacity,24);
    const [normalPing,modifiedPing]=await Promise.all([fetch(a+"/ping").then(r=>r.json()),fetch(b+"/ping").then(r=>r.json())]);
    assert.equal(normalPing.servers.length,1);
    assert.equal(modifiedPing.servers.length,1);
    assert.equal(normalPing.servers[0].playerCapacity,15);
    assert.equal(modifiedPing.servers[0].playerCapacity,24);
    const publicDirectory=await fetch(a+"/api/public/rooms").then(r=>r.json());
    assert.equal(publicDirectory.serverType,"Moo-IO-V2");
    assert.equal(publicDirectory.currentId,"normal");
    assert.deepEqual(publicDirectory.rooms.map(x=>x.id),["lobos","normal"]);
    const open=publicDirectory.rooms.find(x=>x.id==="lobos");
    const gated=publicDirectory.rooms.find(x=>x.id==="normal");
    assert.equal(open.inviteCode,modded.roomCode,"public room advertised intentionally");
    assert.equal(Object.hasOwn(gated,"inviteCode"),false,"private room code never published");
    assert.equal(JSON.stringify(publicDirectory).includes(normal.roomCode),false);
    assert.equal(open.players,0);
    assert.equal(open.capacity,24);
    assert.equal(open.preset,"custom");
    const login=async(url,email)=>{
      const res=await fetch(url+"/api/auth/password",{
        method:"POST",headers:{"content-type":"application/json"},
        body:JSON.stringify({email,password:pass})
      });
      assert.equal(res.status,200);
      return (await res.json()).token;
    };
    const normalToken=await login(a,accounts[0].email);
    const modifiedToken=await login(b,accounts[1].email);
    assert.equal((await fetch(b+"/api/auth/password",{
      method:"POST",headers:{"content-type":"application/json"},
      body:JSON.stringify({email:accounts[0].email,password:pass})
    })).status,400);
    const ticket=async(url,code,auth)=>fetch(url+"/api/join",{
      method:"POST",headers:{"content-type":"application/json","x-mooio-code":code},
      body:JSON.stringify({host:url+"/s/LC",auth})
    });
    assert.equal((await ticket(a,modded.roomCode,normalToken)).status,403);
    assert.equal((await ticket(b,normal.roomCode,modifiedToken)).status,403);
    assert.equal((await ticket(a,normal.roomCode,null)).status,403);
    assert.equal((await ticket(b,modded.roomCode,null)).status,403);
    assert.equal((await ticket(a,normal.roomCode,normalToken)).status,200);
    assert.equal((await ticket(b,modded.roomCode,modifiedToken)).status,200);
    const status=command(["status","--rooms",dir]);
    assert.equal(status.exit,0,status.output);
    assert.match(status.output,/ONLINE normal/);
    assert.match(status.output,/ONLINE lobos/);
    assert.match(status.output,/0\/15 jogadores/);
    assert.match(status.output,/0\/24 jogadores/);
    assert.doesNotMatch(status.output,new RegExp(normal.roomCode));
    const jsonStatus=command(["status","--rooms",dir,"--json"]);
    assert.equal(jsonStatus.exit,0,jsonStatus.output);
    const statusReport=JSON.parse(jsonStatus.output);
    assert.deepEqual(statusReport.totals,{rooms:2,online:2,offline:0,players:0,capacity:39});
    assert.equal(statusReport.healthy,true);
    assert.deepEqual(statusReport.rooms.map(room=>room.id),["lobos","normal"]);
    assert.doesNotMatch(jsonStatus.output,new RegExp(normal.roomCode+"|"+modded.roomCode));
    const health=command(["health","--rooms",dir,"--json"]);
    assert.equal(health.exit,0,health.output);
    assert.equal(JSON.parse(health.output).healthy,true);

    // Keep a LIVE authenticated websocket on the normal room. Reload only
    // the other room's mods and confirm this connection survives unchanged.
    const normalJoin=await ticket(a,normal.roomCode,normalToken);
    assert.equal(normalJoin.status,200);
    const normalJoinToken=(await normalJoin.json()).ticket;
    normalSocket=await new Promise((resolve,reject)=>{
      const ws=new WebSocket("ws://127.0.0.1:"+firstPort+"/s/LC?b="+normalPing.build+
        "&token=tk:"+normalJoinToken,{headers:{Origin:a}});
      const timeout=setTimeout(()=>{ws.terminate();reject(Error("Handshake normal timeout"));},3500);
      ws.once("message",()=>{clearTimeout(timeout);resolve(ws);});
      ws.once("error",error=>{clearTimeout(timeout);reject(error);});
    });

    // Invalid mods: the restart MUST fail BEFORE touching the working room.
    updateRoom(moddedFile,{...modded,mods:["mod-inexistente"]});
    const invalid=command(["restart","lobos","--rooms",dir]);
    assert.notEqual(invalid.exit,0,"invalid mod cannot stop working server");
    assert.equal((await fetch(b+"/mooio/status").then(r=>r.json())).v2.animals.wolfHealth,1000);

    // Changed port/host would break the gateway: refuse hot reload.
    updateRoom(moddedFile,{...modded,port:secondPort+1});
    const portEdit=command(["restart","lobos","--rooms",dir]);
    assert.notEqual(portEdit.exit,0,"port change requires planned full restart");
    assert.equal((await fetch(b+"/mooio/status").then(r=>r.json())).v2.capacity,24);

    // Valid mod change is picked up by a SINGLE worker restart.
    const changed={...modded,mods:["colheita-farta"]};
    updateRoom(moddedFile,changed);
    const restarted=command(["restart","lobos","--rooms",dir]);
    assert.equal(restarted.exit,0,restarted.output);
    assert.match(restarted.output,/lobos.*restarted/);
    const unknown=command(["restart","sala-fantasma","--rooms",dir]);
    assert.notEqual(unknown.exit,0,"unknown room refused");
    let updated=false;
    for(let i=0;i<90;i++){
      try{
        const cur=await fetch(b+"/mooio/status",{signal:AbortSignal.timeout(500)}).then(r=>r.json());
        if(cur.v2?.mods?.length===1&&cur.v2.mods[0]==="colheita-farta"){
          assert.equal(cur.v2.animals.wolfHealth,300);
          assert.equal(cur.v2.animals.cowHealth,650);
          assert.equal(cur.v2.world.treesPerArea,15);
          updated=true;break;
        }
      }catch{}
      await sleep(120);
    }
    assert.equal(updated,true,"new mod only in the restarted room; logs: "+logs.slice(-2000));
    assert.equal(normalSocket.readyState,WebSocket.OPEN,"neighboring room remains connected");
    // Exact authenticated websocket player appears only in the correct V2 room,
    // without exposing IP, account email or any access tokens.
    const rosterResult=command(["players","normal","--rooms",dir]);
    assert.equal(rosterResult.exit,0,rosterResult.output);
    const roster=JSON.parse(rosterResult.output);
    assert.equal(roster.players.length,1);
    const victim=roster.players[0];
    assert.match(victim.id,/^[a-f0-9]{16}$/);
    assert.equal(victim.role,"player");
    assert.equal(Object.hasOwn(victim,"ip"),false);
    assert.equal(Object.hasOwn(victim,"email"),false);
    const otherRoster=command(["players","lobos","--rooms",dir]);
    assert.equal(otherRoster.exit,0,otherRoster.output);
    assert.deepEqual(JSON.parse(otherRoster.output).players,[]);
    const unaffected=await fetch(a+"/mooio/status").then(r=>r.json());
    assert.deepEqual(unaffected.v2.mods,[]);
    assert.equal(unaffected.v2.world.treesPerArea,9);
    // Adding a THIRD room must not require a global restart. The normal
    // room keeps its authenticated WebSocket connection throughout.
    let thirdPort=await freePort();
    while([firstPort,secondPort].includes(thirdPort))thirdPort=await freePort();
    const third=newRoom({name:"Arena extra",port:thirdPort,capacity:12,
      preset:"custom",mods:["mais-lobos"]});
    const thirdFile=path.join(dir,"arena.json");
    createRoom(thirdFile,third);
    const added=command(["start-room","arena","--rooms",dir]);
    assert.equal(added.exit,0,added.output);
    assert.match(added.output,/arena: starting/);
    let thirdOnline=false;
    for(let i=0;i<100;i++){
      const res=await probeRoom({id:"arena",file:thirdFile,room:third},{timeout:500});
      if(res.online){thirdOnline=true;break;}
      await sleep(120);
    }
    assert.equal(thirdOnline,true,"Terceira sala nao iniciou: "+logs.slice(-1700));
    assert.equal(normalSocket.readyState,WebSocket.OPEN,
      "Adicionar sala nao deve desconectar jogadores de outra partida");
    const thirdData=await fetch("http://127.0.0.1:"+thirdPort+"/mooio/status").then(r=>r.json());
    assert.deepEqual(thirdData.v2.mods,["mais-lobos"]);
    assert.equal(thirdData.v2.capacity,12);
    const secondStart=command(["start-room","arena","--rooms",dir]);
    assert.notEqual(secondStart.exit,0,"Sala ativa nao inicia em duplicidade");
    const live=command(["status","--rooms",dir,"--json"]);
    assert.equal(live.exit,0,live.output);
    const liveReport=JSON.parse(live.output);
    assert.equal(liveReport.totals.rooms,3);
    assert.equal(liveReport.totals.online,3);
    assert.equal(liveReport.totals.capacity,51);
    assert.doesNotMatch(live.output,new RegExp(third.roomCode));
    // Stop only arena. Verify it stays stopped (no supervisor auto-restart),
    // keeps neighbors connected, and can subsequently start again.
    const stopped=command(["stop-room","arena","--rooms",dir]);
    assert.equal(stopped.exit,0,stopped.output);
    assert.match(stopped.output,/arena: stopped/);
    for(let i=0;i<35;i++){
      const row=await probeRoom({id:"arena",file:thirdFile,room:third},{timeout:180});
      if(!row.online)break;
      await sleep(90);
    }
    await sleep(1400);
    assert.equal((await probeRoom({id:"arena",file:thirdFile,room:third},{timeout:400})).online,false,
      "Supervisor should not auto-restart an intentionally stopped room");
    assert.equal(normalSocket.readyState,WebSocket.OPEN,"Normal room must survive arena shutdown");
    assert.equal((await probeRoom({id:"lobos",file:moddedFile,room:changed},{timeout:500})).online,true);
    const stoppedEvents=command(["events","arena","--rooms",dir]);
    assert.equal(stoppedEvents.exit,0,stoppedEvents.output);
    const activity=JSON.parse(stoppedEvents.output);
    assert.equal(activity.id,"arena");
    assert.equal(activity.stopped,true);
    assert.ok(activity.events.some(x=>x.kind==="stopped"));
    assert.doesNotMatch(stoppedEvents.output,new RegExp(third.roomCode+"|"+normal.roomCode));
    assert.ok(activity.events.length<=20);
    assert.ok(activity.events.every(x=>["started","stopped","restarting","crashed","watchdog","disabled"].includes(x.kind)));
    const again=command(["start-room","arena","--rooms",dir]);
    assert.equal(again.exit,0,again.output);
    let resumed=false;
    for(let i=0;i<90;i++){
      if((await probeRoom({id:"arena",file:thirdFile,room:third},{timeout:350})).online){
        resumed=true;break;
      }
      await sleep(100);
    }
    assert.equal(resumed,true,"Arena failed to start after intentional stop");
    assert.equal(normalSocket.readyState,WebSocket.OPEN);
    // Do not allow a new room to bind on an already active neighbor's port.
    createRoom(path.join(dir,"collision.json"),newRoom({port:firstPort}));
    const conflict=command(["start-room","collision","--rooms",dir]);
    assert.notEqual(conflict.exit,0);
    fs.unlinkSync(path.join(dir,"collision.json"));
    assert.equal(normalSocket.readyState,WebSocket.OPEN);
    const newStatus=command(["status","--rooms",dir,"--json"]);
    assert.equal(newStatus.exit,0,newStatus.output);
    assert.equal(JSON.parse(newStatus.output).healthy,true);
    // Actual kick targets this socket only; the other room survives.
    const closed=new Promise(resolve=>normalSocket.once("close",resolve));
    const kicked=command(["kick","normal",victim.id,"--rooms",dir]);
    assert.equal(kicked.exit,0,kicked.output);
    assert.match(kicked.output,/Jogador .* expulso desta sala/);
    await Promise.race([closed,sleep(4000)]);
    assert.equal(normalSocket.readyState,WebSocket.CLOSED);
    assert.equal((await probeRoom({id:"lobos",file:moddedFile,room:changed},{timeout:500})).online,true);
    const empty=command(["players","normal","--rooms",dir]);
    assert.equal(empty.exit,0,empty.output);
    assert.equal(JSON.parse(empty.output).players.length,0);
  }finally{
    normalSocket?.terminate();
    if(child&&child.exitCode===null){
      if(process.platform==="win32")spawnSync("taskkill",["/PID",String(child.pid),"/T","/F"],{stdio:"ignore"});
      else child.kill("SIGTERM");
      await Promise.race([new Promise(resolve=>child.once("close",resolve)),sleep(7000)]);
      if(child.exitCode===null&&process.platform!=="win32")child.kill("SIGKILL");
    }
    for(let i=0;i<20;i++){
      if((await Promise.all(entries.map(e=>probeRoom(e,{timeout:120})))).every(r=>!r.online))break;
      await sleep(150);
    }
    assert.equal((await Promise.all(entries.map(e=>probeRoom(e,{timeout:120})))).every(r=>!r.online),true,"Salas continuaram ativas apos fechar o controlador");
    fs.rmSync(dir,{recursive:true,force:true});
  }
});
