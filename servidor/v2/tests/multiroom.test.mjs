// SPDX-License-Identifier: AGPL-3.0-only
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import net from "node:net";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { newRoom, createRoom } from "../core/config.mjs";
import { discoverRooms, checkRooms, probeRoom } from "../core/supervisor.mjs";

const root=fileURLToPath(new URL("../../../",import.meta.url));
const manager=path.join(root,"servidor/v2/manager.mjs");
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
  const modded=newRoom({name:"Mundo dos Lobos",port:secondPort,capacity:24,preset:"custom",mods:["mais-lobos"]});
  createRoom(path.join(dir,"normal.json"),normal);
  createRoom(path.join(dir,"lobos.json"),modded);
  const entries=await checkRooms(discoverRooms(dir));
  let child,logs="";
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
    assert.equal(normStatus.v2.animals.wolfHealth,500); // Verify original baseline below via reference check
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
    const ticket=async(url,code)=>fetch(url+"/api/join",{
      method:"POST",headers:{"content-type":"application/json","x-mooio-code":code},
      body:JSON.stringify({host:url+"/s/LC",captcha:true})
    });
    assert.equal((await ticket(a,modded.roomCode)).status,403);
    assert.equal((await ticket(b,normal.roomCode)).status,403);
    assert.equal((await ticket(a,normal.roomCode)).status,200);
    assert.equal((await ticket(b,modded.roomCode)).status,200);
    const status=command(["status","--rooms",dir]);
    assert.equal(status.exit,0,status.output);
    assert.match(status.output,/ONLINE normal/);
    assert.match(status.output,/ONLINE lobos/);
    assert.match(status.output,/0\/15 jogadores/);
    assert.match(status.output,/0\/24 jogadores/);
    assert.doesNotMatch(status.output,new RegExp(normal.roomCode));
  }finally{
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
