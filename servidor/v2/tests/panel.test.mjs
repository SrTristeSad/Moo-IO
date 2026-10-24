// SPDX-License-Identifier: AGPL-3.0-only
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import net from "node:net";
import path from "node:path";
import { createPanel, panelCredentials, ADMIN_EMAIL } from "../core/panel.mjs";
import { readRoom } from "../core/config.mjs";

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
