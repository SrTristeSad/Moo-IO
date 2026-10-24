// SPDX-License-Identifier: AGPL-3.0-only
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import net from "node:net";
import path from "node:path";
import { createPanel, panelCredentials, ADMIN_EMAIL } from "../core/panel.mjs";
import { readRoom, createRoom, newRoom } from "../core/config.mjs";
import { setStaffRole, readStaffRoles } from "../core/panel-roles.mjs";
import { probeRoom } from "../core/supervisor.mjs";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

async function port(){
  const s=net.createServer();
  await new Promise(resolve=>s.listen(0,"127.0.0.1",resolve));
  const p=s.address().port;
  await new Promise(resolve=>s.close(resolve));return p;
}
test("painel protege sessao, sala e mods",{timeout:30000},async()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"mooio-panel-"));
  const password="example-dashboard-passphrase-2026";
  let panel;
  try{
    await panelCredentials(dir).set(ADMIN_EMAIL,password);
    panel=await createPanel({rooms:dir,port:await port()});
    const base="http://127.0.0.1:"+panel.port;
    const request=(pathname,method="GET",body,cookie,csrf,origin=base)=>fetch(base+pathname,{
      method,headers:{"Origin":origin,"Content-Type":"application/json",...(cookie?{"Cookie":cookie}:{}),
        ...(csrf?{"X-CSRF-Token":csrf}:{})},body:body===undefined?undefined:JSON.stringify(body)
    });
    assert.equal((await request("/api/overview")).status,401);
    assert.equal((await request("/api/rooms/normal/players")).status,401);
    assert.equal((await request("/api/rooms/normal/kick","POST",{playerId:"0123456789abcdef"})).status,401);
    assert.equal((await request("/api/login","POST",{password},undefined,undefined,"https://external.invalid")).status,403);
    const login=await request("/api/login","POST",{password});
    assert.equal(login.status,200);
    const cookie=login.headers.get("set-cookie").split(";")[0];
    const {csrf}=await login.json();
    assert.equal((await request("/api/rooms","POST",{},cookie)).status,403);
    const info={id:"normal",name:"Normal",preset:"traditional",port:18880,capacity:25,bots:0,mods:[]};
    const create=await request("/api/rooms","POST",info,cookie,csrf);
    assert.equal(create.status,201,await create.text());
    const first=readRoom(path.join(dir,"normal.json"));
    assert.equal(first.port,18880);
    assert.equal(first.host,"127.0.0.1");
    const clash=await request("/api/rooms","POST",{...info,id:"outra"},cookie,csrf);
    assert.equal(clash.status,409);
    const update=await request("/api/rooms/normal","PUT",{preset:"custom",mods:["mais-lobos"]},cookie,csrf);
    assert.equal(update.status,200,await update.text());
    assert.deepEqual(readRoom(path.join(dir,"normal.json")).mods,["mais-lobos"]);
    assert.equal(readRoom(path.join(dir,"normal.json")).roomCode,first.roomCode);
    const overview=await request("/api/overview","GET",undefined,cookie);
    assert.equal(overview.status,200);
    const data=await overview.json();
    assert.equal(data.rooms.length,1);
    assert.equal(JSON.stringify(data).includes(first.roomCode),false);
    const badKick=await request("/api/rooms/normal/kick","POST",{playerId:"../escape"},cookie,csrf);
    assert.equal(badKick.status,400);
    const noCsrf=await request("/api/rooms/normal/kick","POST",{playerId:"0123456789abcdef"},cookie);
    assert.equal(noCsrf.status,403);
    const forged=await request("/api/rooms/normal/kick","POST",{playerId:"0123456789abcdef"},cookie,csrf,"https://evil.invalid");
    assert.equal(forged.status,403);
    const modList=await request("/api/mods","GET",undefined,cookie);
    assert.equal(modList.status,200);
    assert.ok((await modList.json()).mods.length>0);
    assert.equal((await request("/api/logout","POST",{},cookie,csrf)).status,200);
    assert.equal((await request("/api/overview","GET",undefined,cookie)).status,401);
  }finally{
    if(panel)await panel.close();
    fs.rmSync(dir,{recursive:true,force:true});
  }
});

test("Painel cria e inicia sala nova com controlador ativo sem parar primeira sala",{timeout:45000},async()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"mooio-panel-live-"));
  const root=fileURLToPath(new URL("../../../",import.meta.url));
  const initialPort=await port();
  let extraPort=await port();
  while(extraPort===initialPort)extraPort=await port();
  const room=newRoom({name:"Normal",port:initialPort,capacity:20});
  const firstFile=path.join(dir,"normal.json");
  createRoom(firstFile,room);
  let child,panel,log="";
  try{
    child=spawn(process.execPath,[path.join(root,"servidor/v2/manager.mjs"),"start","--rooms",dir],
      {cwd:root,stdio:["ignore","pipe","pipe"]});
    child.stdout.on("data",d=>log+=d.toString());
    child.stderr.on("data",d=>log+=d.toString());
    let initial=false;
    for(let i=0;i<90;i++){
      if((await probeRoom({id:"normal",file:firstFile,room},{timeout:350})).online){
        initial=true;break;
      }
      await new Promise(r=>setTimeout(r,140));
    }
    assert.equal(initial,true,"Sala inicial nao iniciou: "+log.slice(-900));
    await panelCredentials(dir).set(ADMIN_EMAIL,"panel-live-password-93841");
    panel=await createPanel({rooms:dir,port:await port()});
    const base="http://127.0.0.1:"+panel.port;
    const login=await fetch(base+"/api/login",{method:"POST",headers:{
      "Origin":base,"Content-Type":"application/json"
    },body:JSON.stringify({password:"panel-live-password-93841"})});
    assert.equal(login.status,200);
    const cookie=login.headers.get("set-cookie").split(";")[0];
    const {csrf}=await login.json();
    const created=await fetch(base+"/api/rooms",{method:"POST",headers:{
      "Origin":base,"Content-Type":"application/json","Cookie":cookie,"X-CSRF-Token":csrf
    },body:JSON.stringify({id:"arena",name:"Arena",preset:"custom",
      port:extraPort,capacity:24,bots:0,mods:["mais-lobos"]})});
    assert.equal(created.status,201,await created.text());
    // The request has already reached the private supervisor IPC channel.
    const newFile=path.join(dir,"arena.json"),config=readRoom(newFile);
    let online=false;
    for(let i=0;i<90;i++){
      if((await probeRoom({id:"arena",file:newFile,room:config},{timeout:400})).online){
        online=true;break;
      }
      await new Promise(r=>setTimeout(r,140));
    }
    assert.equal(online,true,"Painel nao iniciou nova arena: "+log.slice(-1500));
    assert.equal((await probeRoom({id:"normal",file:firstFile,room},{timeout:500})).online,true);
    const duplicate=await fetch(base+"/api/rooms/arena/start",{method:"POST",headers:{
      "Origin":base,"Content-Type":"application/json","Cookie":cookie,"X-CSRF-Token":csrf
    },body:"{}"});
    assert.notEqual(duplicate.status,200);
    const eventsUnauth=await fetch(base+"/api/rooms/arena/events");
    assert.equal(eventsUnauth.status,401);
    const activity=await fetch(base+"/api/rooms/arena/events",{
      headers:{"Cookie":cookie}
    });
    assert.equal(activity.status,200);
    const activityJson=await activity.json();
    assert.equal(activityJson?.id,"arena");
    assert.ok(activityJson.events.some(row=>row.kind==="started"));
    assert.ok(activityJson.events.length<=20);
    assert.equal(JSON.stringify(activityJson).includes(config.roomCode),false);
    const forged=await fetch(base+"/api/rooms/arena/stop",{
      method:"POST",headers:{"Origin":"https://evil.invalid","Cookie":cookie,
        "X-CSRF-Token":csrf,"Content-Type":"application/json"},body:"{}"
    });
    assert.equal(forged.status,403);
    const stopped=await fetch(base+"/api/rooms/arena/stop",{
      method:"POST",headers:{"Origin":base,"Cookie":cookie,
        "X-CSRF-Token":csrf,"Content-Type":"application/json"},body:"{}"
    });
    assert.equal(stopped.status,200);
    assert.equal((await stopped.json()).result.status,"stopped");
    await new Promise(r=>setTimeout(r,500));
    assert.equal((await probeRoom({id:"arena",file:newFile,room:config},{timeout:350})).online,false);
    assert.equal((await probeRoom({id:"normal",file:firstFile,room},{timeout:350})).online,true);
    const eventAfter=await fetch(base+"/api/rooms/arena/events",{headers:{"Cookie":cookie}});
    const history=await eventAfter.json();
    assert.ok(history.events.some(row=>row.kind==="stopped"));
    const startAgain=await fetch(base+"/api/rooms/arena/start",{
      method:"POST",headers:{"Origin":base,"Cookie":cookie,
        "X-CSRF-Token":csrf,"Content-Type":"application/json"},body:"{}"
    });
    assert.equal(startAgain.status,200,await startAgain.text());
  }finally{
    if(panel)await panel.close();
    if(child&&child.exitCode===null){
      if(process.platform==="win32")spawnSync("taskkill",["/PID",String(child.pid),"/T","/F"],{stdio:"ignore"});
      else child.kill("SIGTERM");
      await Promise.race([new Promise(resolve=>child.once("close",resolve)),
        new Promise(resolve=>setTimeout(resolve,5000))]);
      if(child.exitCode===null&&process.platform!=="win32")child.kill("SIGKILL");
    }
    fs.rmSync(dir,{recursive:true,force:true});
  }
});

test("RBAC: viewer is read-only, moderator may moderate, owner alone edits rooms",{timeout:25000},async()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"mooio-panel-roles-"));
  let panel;
  try{
    const creds=panelCredentials(dir);
    await creds.set(ADMIN_EMAIL,"owner-secret-password-2026");
    await creds.set("watcher@example.org","viewer-secret-password-2026");
    await creds.set("staff@example.org","moderator-secret-password-2026");
    const privateDir=path.join(dir,".control");
    setStaffRole(privateDir,"watcher@example.org","viewer");
    setStaffRole(privateDir,"staff@example.org","moderator");
    assert.equal(readStaffRoles(privateDir)["staff@example.org"],"moderator");
    panel=await createPanel({rooms:dir,port:await port()});
    const base="http://127.0.0.1:"+panel.port;
    const request=(url,method="GET",body,cookie,csrf)=>fetch(base+url,{
      method,headers:{"Origin":base,"Content-Type":"application/json",...(cookie?{"Cookie":cookie}:{}),
        ...(csrf?{"X-CSRF-Token":csrf}:{})},body:body===undefined?undefined:JSON.stringify(body)
    });
    const login=async(email,password)=>{
      const response=await request("/api/login","POST",{email,password});
      assert.equal(response.status,200);
      const cookie=response.headers.get("set-cookie").split(";")[0];
      const json=await response.json();
      return {cookie,csrf:json.csrf,role:json.role};
    };
    const view=await login("watcher@example.org","viewer-secret-password-2026");
    const mod=await login("staff@example.org","moderator-secret-password-2026");
    const owner=await login(ADMIN_EMAIL,"owner-secret-password-2026");
    assert.equal(view.role,"viewer");assert.equal(mod.role,"moderator");assert.equal(owner.role,"owner");
    assert.equal((await request("/api/overview","GET",undefined,view.cookie)).status,200);
    assert.equal((await request("/api/mods","GET",undefined,view.cookie)).status,403);
    assert.equal((await request("/api/rooms","POST",{},view.cookie,view.csrf)).status,403);
    assert.equal((await request("/api/rooms","POST",{},mod.cookie,mod.csrf)).status,403);
    assert.equal((await request("/api/rooms/normal/kick","POST",{playerId:"0123456789abcdef"},view.cookie,view.csrf)).status,403);
    assert.equal((await request("/api/rooms/normal/ban","POST",{playerId:"0123456789abcdef",minutes:5,reason:""},view.cookie,view.csrf)).status,403);
    assert.equal((await request("/api/rooms/normal/history","GET",undefined,view.cookie)).status,404);
    assert.equal((await request("/api/mods","GET",undefined,owner.cookie)).status,200);
    const info={id:"normal",name:"Normal",preset:"traditional",port:17880,capacity:20,bots:0,mods:[]};
    assert.equal((await request("/api/rooms","POST",info,owner.cookie,owner.csrf)).status,201);
    assert.equal((await request("/api/rooms/normal/ban","POST",{playerId:"0123456789abcdef",minutes:7,reason:""},mod.cookie,mod.csrf)).status,400);
    assert.equal((await request("/api/rooms/normal/ban","POST",{playerId:"../../invalid",minutes:5,reason:""},mod.cookie,mod.csrf)).status,400);
    assert.equal((await request("/api/rooms/normal/restart","POST",{},mod.cookie,mod.csrf)).status,403);
    // Immediate role revocation invalidates existing cookie, without restart.
    setStaffRole(privateDir,"staff@example.org","revoke");
    assert.equal((await request("/api/overview","GET",undefined,mod.cookie)).status,401);
    assert.equal((await request("/api/login","POST",{email:"staff@example.org",password:"moderator-secret-password-2026"})).status,401);
  }finally{
    if(panel)await panel.close();
    fs.rmSync(dir,{recursive:true,force:true});
  }
});
