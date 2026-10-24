// SPDX-License-Identifier: AGPL-3.0-only
import test from "node:test";
import assert from "node:assert/strict";
import os from "node:os";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { setup, doctor, unitContent, panelUnitContent, quoteSystemd, ROOT } from "../vps.mjs";
import { readRoom, createRoom, newRoom } from "../core/config.mjs";
const cli=fileURLToPath(new URL("../vps.mjs",import.meta.url));
const dir=()=>fs.mkdtempSync(path.join(os.tmpdir(),"mooio-v2-vps-"));
test("Setup cria sala privada e e idempotente", async()=>{
  const base=dir(),rooms=path.join(base,"rooms");
  try{
    const a=await setup({rooms,name:"Teste VPS",port:18880,skipInstall:true});
    assert.equal(a.created,true);
    const file=path.join(rooms,"principal.json"),data=readRoom(file);
    assert.equal(data.name,"Teste VPS");
    assert.equal(data.port,18880);
    assert.equal(data.host,"127.0.0.1");
    assert.equal(data.capacity,40);
    assert.deepEqual(data.mods,[]);
    const b=await setup({rooms,name:"Nao sobrescrever",port:18888,skipInstall:true});
    assert.equal(b.created,false);
    assert.deepEqual(readRoom(file),data);
    if(process.platform!=="win32")assert.equal(fs.statSync(file).mode&0o777,0o600);
    const check=await doctor({rooms});
    assert.equal(check.rooms.length,1);
    assert.deepEqual(check.warnings,[]);
    const r=spawnSync(process.execPath,[cli,"doctor","--rooms",rooms],{cwd:ROOT,encoding:"utf8"});
    assert.equal(r.status,0,r.stderr);
    assert.doesNotMatch(r.stdout,new RegExp(data.roomCode));
  }finally{fs.rmSync(base,{force:true,recursive:true});}
});
test("Setup preserva sala customizada e mods",async()=>{
  const base=dir(),rooms=path.join(base,"rooms");
  try{
    fs.mkdirSync(rooms);
    const file=path.join(rooms,"especial.json");
    const original=newRoom({name:"Especial",port:18033,preset:"custom",mods:["mais-lobos"]});
    createRoom(file,original);
    const result=await setup({rooms,skipInstall:true});
    assert.equal(result.created,false);
    assert.deepEqual(readRoom(file),original);
    assert.deepEqual(fs.readdirSync(rooms),["especial.json"]);
  }finally{fs.rmSync(base,{force:true,recursive:true});}
});
test("Setup rejeita portas invalidas, conflitos e links simbolicos",async()=>{
  const base=dir(),rooms=path.join(base,"rooms");
  try{
    await assert.rejects(()=>setup({rooms,port:80,skipInstall:true}),/Porta/);
    fs.mkdirSync(rooms);
    createRoom(path.join(rooms,"a.json"),newRoom({port:18555}));
    createRoom(path.join(rooms,"b.json"),newRoom({port:18555}));
    await assert.rejects(()=>setup({rooms,skipInstall:true}),/Porta duplicada/);
    const link=path.join(base,"link");
    try {
      fs.symlinkSync(rooms,link,"dir");
      await assert.rejects(()=>setup({rooms:link,skipInstall:true}),/symlink/);
    }catch(e){if(!["EPERM","EACCES","ENOSYS"].includes(e.code))throw e;}
  }finally{fs.rmSync(base,{force:true,recursive:true});}
});
test("Unit systemd seguro com caminhos contendo espacos",()=>{
  const unit=unitContent({root:"/opt/Moo IO",rooms:"/opt/Moo IO/rooms",node:"/usr/bin/node"});
  assert.match(unit,/ExecStart="\/usr\/bin\/node" "\/opt\/Moo IO\/servidor\/v2\/manager.mjs" start --rooms "\/opt\/Moo IO\/rooms"/);
  assert.match(unit,/ExecStartPre=.* check --rooms /);
  assert.match(unit,/NoNewPrivileges=true/);
  assert.match(unit,/UMask=0077/);
  assert.doesNotMatch(unit,/0\.0\.0\.0|:443|:80\b|sudo|curl/);
  assert.equal(quoteSystemd("/path/has $cash %var"),'"/path/has $$cash %%var"');
  assert.throws(()=>quoteSystemd("/root/file\nBad=true"),/controle/);
  assert.throws(()=>quoteSystemd("relative/file"),/absoluto/);
});

test("Painel systemd gerado separadamente, somente localhost e senha obrigatoria",()=>{
  const unit=panelUnitContent({root:"/opt/Moo IO",rooms:"/opt/Moo IO/rooms",node:"/usr/bin/node",port:8787});
  assert.match(unit,/ExecStartPre="\/usr\/bin\/node" "\/opt\/Moo IO\/servidor\/v2\/panel.mjs" check --rooms "\/opt\/Moo IO\/rooms"/);
  assert.match(unit,/ExecStart="\/usr\/bin\/node" "\/opt\/Moo IO\/servidor\/v2\/panel.mjs" serve --rooms "\/opt\/Moo IO\/rooms" --port 8787/);
  assert.match(unit,/NoNewPrivileges=true/);
  assert.match(unit,/UMask=0077/);
  assert.match(unit,/After=network.target mooio-v2.service/);
  assert.doesNotMatch(unit,/0\.0\.0\.0|reverse_proxy|sudo|curl/);
  assert.throws(()=>panelUnitContent({port:443}),/Porta/);
  const generated=spawnSync(process.execPath,[cli,"panel-unit","--rooms","/opt/Moo IO/rooms","--port","8787"],
    {cwd:ROOT,encoding:"utf8"});
  assert.equal(generated.status,0,generated.stderr);
  assert.match(generated.stdout,/panel.mjs" serve/);
  assert.doesNotMatch(generated.stdout,/senha|password.*=.*[a-f0-9]{64}/i);
});
