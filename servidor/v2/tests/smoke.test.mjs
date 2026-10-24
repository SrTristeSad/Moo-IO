import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { spawn, spawnSync } from "node:child_process";
import net from "node:net";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { newRoom, createRoom } from "../core/config.mjs";

const root=fileURLToPath(new URL("../../../",import.meta.url));
const cli=path.join(root,"servidor/v2/cli.mjs");
const requireServer=createRequire(path.join(root,"windows/server/package.json"));
const WebSocket=requireServer("ws");
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function port(){
  const server=net.createServer();
  await new Promise(r=>server.listen(0,"127.0.0.1",r));
  const p=server.address().port;
  await new Promise(r=>server.close(r));
  return p;
}
test("V2: custom real altera mundo e AI, valida convite e websocket, mantem um unico mundo", {timeout:35000}, async()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"mooio-v2-test-"));
  const file=path.join(dir,"myroom.json");
  const p=await port();
  const room=newRoom({name:"Sala Teste",preset:"custom",port:p,mods:["colheita-farta","mais-lobos"]});
  createRoom(file,room);
  const email="test@example.org",password="test-password-strong-123";
  const provision=spawnSync(process.execPath,[path.join(root,"servidor/v2/accounts.mjs"),
    "set-password","--file",file,"--email",email],{
      cwd:root,input:password+"\n",encoding:"utf8",timeout:20000
  });
  assert.equal(provision.status,0,provision.stderr);
  const second=spawnSync(process.execPath,[path.join(root,"servidor/v2/accounts.mjs"),
    "set-password","--file",file,"--email","second@example.org"],{
    cwd:root,input:password+"\n",encoding:"utf8",timeout:20000
  });
  assert.equal(second.status,0,second.stderr);
  let child,logs="";
  try{
    child=spawn(process.execPath,[cli,"start","--file",file],{cwd:root,stdio:["ignore","pipe","pipe"]});
    child.stdout.on("data",c=>logs+=c);
    child.stderr.on("data",c=>logs+=c);
    const address="http://127.0.0.1:"+p;
    let ready=false;
    for(let i=0;i<95;i++){
      if(child.exitCode!==null)break;
      try{const r=await fetch(address+"/mooio/status",{signal:AbortSignal.timeout(250)});if(r.ok){ready=true;break;}}catch{}
      await delay(150);
    }
    assert.ok(ready,"motor nao iniciou: "+logs.slice(-1900));
    const status=await (await fetch(address+"/mooio/status")).json();
    assert.equal(status.project,"Moo-IO");
    assert.equal(status.v2.room,"Sala Teste");
    assert.deepEqual(status.v2.mods,["colheita-farta","mais-lobos"]);
    assert.equal(status.v2.world.treesPerArea,15);
    assert.equal(status.v2.animals.cowHealth,650);
    assert.equal(status.v2.animals.wolfHealth,1000);
    const ping=await (await fetch(address+"/ping")).json();
    assert.equal(ping.servers.length,1,"V2 deve ter uma sala por processo");
    assert.equal(ping.servers[0].playerCapacity,40);
    assert.equal((await fetch(address+"/api/auth/code",{method:"POST",
      headers:{"content-type":"application/json"},body:JSON.stringify({email})})).status,410);
    const passwordLogin=async(pass,userEmail=email)=>fetch(address+"/api/auth/password",{
      method:"POST",headers:{"content-type":"application/json"},
      body:JSON.stringify({email:userEmail,password:pass})
    });
    assert.equal((await passwordLogin("wrong-password")).status,400);
    const good=await passwordLogin(password);
    assert.equal(good.status,200);
    const token=(await good.json()).token;
    assert.ok(token);
    for(let i=0;i<8;i++)assert.equal((await passwordLogin("wrong-password")).status,400);
    assert.equal((await passwordLogin("wrong-password")).status,429);
    assert.equal((await passwordLogin(password,"second@example.org")).status,200,
      "Uma conta bloqueada nao deve impedir outra conta no mesmo IP de fazer login");
    const join=async(code,auth=token)=>fetch(address+"/api/join",{
      method:"POST",headers:{"content-type":"application/json",...(code?{"x-mooio-code":code}:{})},
      body:JSON.stringify({host:address+"/s/LC",auth})
    });
    assert.equal((await join()).status,403);
    assert.equal((await join(room.roomCode,null)).status,403);
    const accepted=await join(room.roomCode);
    assert.equal(accepted.status,200);
    const payload=await accepted.json();
    assert.ok(payload.ticket);
    const ws=await new Promise((resolve,reject)=>{
      const socket=new WebSocket("ws://127.0.0.1:"+p+"/s/LC?b="+ping.build+"&token=tk:"+payload.ticket,{headers:{Origin:address}});
      const timer=setTimeout(()=>{socket.terminate();reject(new Error("sem handshake websocket"));},3000);
      socket.once("message",data=>{clearTimeout(timer);assert.ok(data.length>8);resolve(socket)});
      socket.once("error",error=>{clearTimeout(timer);reject(error)});
    });
    ws.terminate();
  }finally{
    if(child&&child.exitCode===null){
      if(process.platform==="win32")spawnSync("taskkill",["/PID",String(child.pid),"/T","/F"],{stdio:"ignore"});
      else child.kill("SIGTERM");
      await Promise.race([new Promise(r=>child.once("close",r)),delay(2500)]);
      if(child.exitCode===null&&process.platform!=="win32")child.kill("SIGKILL");
    }
    fs.rmSync(dir,{recursive:true,force:true});
  }
});
