// SPDX-License-Identifier: AGPL-3.0-only
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import net from "node:net";
import { startControlServer, requestRoomRestart, requestRoomStart, requestRoomStop, requestRoomEvents, requestRoomPlayers, requestPlayerKick, controlPaths } from "../core/control.mjs";

const makeDir=()=>fs.mkdtempSync(path.join(os.tmpdir(),"mooio-v2-control-"));
const responseFrom=(endpoint,request)=>new Promise((resolve,reject)=>{
  const socket=net.createConnection(endpoint);let output="";
  socket.setTimeout(4000,()=>{socket.destroy();reject(Error("timeout"));});
  socket.once("connect",()=>socket.write(JSON.stringify(request)+"\n"));
  socket.on("data",data=>{output+=data.toString("utf8");});
  socket.once("end",()=>{try{resolve(JSON.parse(output.trim()));}catch(e){reject(e);}});
  socket.once("error",reject);
});

test("controlador local exige autenticacao e so aceita o comando autorizado", {timeout:15000},async()=>{
  const dir=makeDir(),called=[];
  let server;
  try{
    server=await startControlServer(dir,{
      onRestart:async id=>{called.push("restart:"+id);return {id,status:"restarted"};},
      onStart:async id=>{called.push("start:"+id);return {id,status:"starting"};},
      onStop:async id=>{called.push("stop:"+id);return {id,status:"stopped"};},
      onEvents:async id=>({id,stopped:false,events:[{at:"2026-10-24T00:00:00.000Z",kind:"started"}]}),
      onPlayers:async id=>({players:[{id:"0123456789abcdef",name:"A",role:"guest"}]}),
      onKick:async (id,playerId)=>({playerId,status:"kicked"})
    });
    const paths=controlPaths(dir);
    if(process.platform!=="win32"){
      assert.equal(fs.statSync(paths.privateDir).mode&0o777,0o700);
      assert.equal(fs.statSync(paths.tokenFile).mode&0o777,0o600);
      assert.equal(fs.statSync(paths.endpoint).mode&0o777,0o600);
    }
    const unauthorized=await responseFrom(paths.endpoint,{token:"0".repeat(64),command:"restart",room:"normal"});
    assert.equal(unauthorized.ok,false);
    assert.equal(unauthorized.error,"unauthorized");
    assert.deepEqual(called,[]);
    const validToken=fs.readFileSync(paths.tokenFile,"utf8").trim();
    const injection=await responseFrom(paths.endpoint,{token:validToken,command:"restart",room:"../normal"});
    assert.equal(injection.ok,false);
    assert.equal(injection.error,"invalidCommand");
    const success=await requestRoomRestart(dir,"normal");
    assert.deepEqual(success,{id:"normal",status:"restarted"});
    assert.deepEqual(called,["restart:normal"]);
    const started=await requestRoomStart(dir,"arena");
    assert.deepEqual(started,{id:"arena",status:"starting"});
    assert.deepEqual(called,["restart:normal","start:arena"]);
    const stopped=await requestRoomStop(dir,"arena");
    assert.deepEqual(stopped,{id:"arena",status:"stopped"});
    const events=await requestRoomEvents(dir,"arena");
    assert.equal(events.events[0].kind,"started");
    assert.deepEqual(called,["restart:normal","start:arena","stop:arena"]);
    const roster=await requestRoomPlayers(dir,"normal");
    assert.equal(roster.players[0].name,"A");
    const expelled=await requestPlayerKick(dir,"normal","0123456789abcdef");
    assert.equal(expelled.status,"kicked");
    await assert.rejects(()=>requestPlayerKick(dir,"normal","../../escape"),/invalido/);
    await assert.rejects(()=>requestRoomRestart(dir,"../normal"),/ID da sala invalido/);
    await assert.rejects(()=>requestRoomStart(dir,"../arena"),/ID da sala invalido/);
    await assert.rejects(()=>requestRoomStop(dir,"../arena"),/ID da sala invalido/);
    await assert.rejects(()=>requestRoomEvents(dir,"../arena"),/ID da sala invalido/);
    const denied=await responseFrom(paths.endpoint,{token:validToken,command:"delete",room:"normal"});
    assert.equal(denied.error,"invalidCommand");
    const bad=await responseFrom(paths.endpoint,{token:"0".repeat(64),command:"stop",room:"normal"});
    assert.equal(bad.error,"unauthorized");
    await assert.rejects(()=>startControlServer(dir,{onRestart:()=>{}}),/ja usa o socket|ocupado|EADDRINUSE/);
  }finally{
    if(server)await server.close();
    fs.rmSync(dir,{force:true,recursive:true});
  }
});
test("controlador recusa symlink do token e nao sobe admin HTTP",async()=>{
  if(process.platform==="win32")return;
  const dir=makeDir();
  try{
    const paths=controlPaths(dir);
    fs.mkdirSync(paths.privateDir,{mode:0o700});
    fs.symlinkSync(path.join(dir,"secreto"),paths.tokenFile);
    await assert.rejects(()=>startControlServer(dir,{onRestart:()=>{}}),/Arquivo de controle|Token/);
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
test("controle recusado quando o supervisor nao esta ativo",async()=>{
  const dir=makeDir();
  try{await assert.rejects(()=>requestRoomRestart(dir,"normal"),/Diretorio|arquivo de autenticacao|ENOENT/);}
  finally{fs.rmSync(dir,{recursive:true,force:true});}
});
