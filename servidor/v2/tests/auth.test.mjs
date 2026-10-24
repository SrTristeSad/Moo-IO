// SPDX-License-Identifier: AGPL-3.0-only
import test from "node:test";
import assert from "node:assert/strict";
import os from "node:os";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { AccountStore } from "../../../windows/server/src/api/store.js";
import { LocalCredentials } from "../../../windows/server/src/api/credentials.js";
import { createRoom, newRoom, roomDataPath } from "../core/config.mjs";

const root=fileURLToPath(new URL("../../../",import.meta.url));
const provisioning=path.join(root,"servidor/v2/accounts.mjs");
const temp=()=>fs.mkdtempSync(path.join(os.tmpdir(),"mooio-v2-credentials-"));
test("V2: senha scrypt persistida sem texto puro, rejeita senha incorreta e tokens antigos",async()=>{
  const base=temp();
  try{
    const legacy=new AccountStore(base);
    const original=legacy.accountForEmail("user@example.org");
    const legacyToken=legacy.issueToken(original);
    await new Promise(r=>setTimeout(r,340));
    const secure=new AccountStore(base,{passwordMode:true});
    assert.equal(secure.verifyToken(legacyToken),null);
    await assert.rejects(()=>secure.setLocalPassword("user@example.org","short"),/12-128/);
    assert.equal(secure.localAccountForEmail("absent@example.org"),null);
    await secure.setLocalPassword("user@example.org","strong-correct-password-321");
    const valid=await secure.verifyLocalPassword("user@example.org","strong-correct-password-321");
    assert.equal(valid.id,original.id);
    assert.equal(await secure.verifyLocalPassword("user@example.org","bad"),null);
    assert.equal(await secure.verifyLocalPassword("unknown@example.org","strong-correct-password-321"),null);
    const token=secure.issueToken(valid);
    assert.equal(secure.verifyToken(token).id,valid.id);
    const bytes=fs.readFileSync(path.join(base,"v2-credentials.json"),"utf8");
    assert.doesNotMatch(bytes,/strong-correct-password-321/);
    assert.match(bytes,/"algo": "scrypt-v1"/);
    if(process.platform!=="win32")assert.equal(fs.statSync(path.join(base,"v2-credentials.json")).mode&0o777,0o600);
    const newProcess=new AccountStore(base,{passwordMode:true});
    assert.equal((await newProcess.verifyLocalPassword("user@example.org","strong-correct-password-321")).id,valid.id);
  }finally{fs.rmSync(base,{recursive:true,force:true});}
});
test("V2: credenciais corrompidas impedem iniciar; nao substitui autenticação antiga",async()=>{
  const base=temp();
  try{
    const regular=new AccountStore(base);
    const legacy=regular.accountForEmail("another@example.org");
    assert.equal(regular.verifyToken(regular.issueToken(legacy)).id,legacy.id);
    await new Promise(resolve=>setTimeout(resolve,350)); // complete AccountStore debounced write before removing directory
    fs.writeFileSync(path.join(base,"v2-credentials.json"),"{invalid", {mode:0o600});
    assert.throws(()=>new AccountStore(base,{passwordMode:true}));
    assert.ok(new AccountStore(base)); // local LAN does not depend on V2 credential store
  }finally{fs.rmSync(base,{recursive:true,force:true});}
});
test("V2: CLI recebe senha no stdin, nao a imprime e cria conta na sala correta",()=>{
  const base=temp(),file=path.join(base,"rooms","principal.json");
  try{
    createRoom(file,newRoom({name:"Privada",port:18444}));
    const password="super-secret-password-7878";
    const result=spawnSync(process.execPath,[provisioning,"set-password","--file",file,"--email","alice@example.org"],{
      cwd:root,input:password+"\n",encoding:"utf8",timeout:25000
    });
    assert.equal(result.status,0,result.stderr);
    assert.match(result.stdout,/alice@example.org/);
    assert.doesNotMatch(result.stdout+result.stderr,new RegExp(password));
    const store=new AccountStore(roomDataPath(file),{passwordMode:true});
    assert.equal(store.localAccountForEmail("alice@example.org")?.email,"alice@example.org");
    const auth=fs.readFileSync(path.join(roomDataPath(file),"v2-credentials.json"),"utf8");
    assert.doesNotMatch(auth,new RegExp(password));
  }finally{fs.rmSync(base,{recursive:true,force:true});}
});
