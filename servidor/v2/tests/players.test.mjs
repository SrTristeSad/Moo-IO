// SPDX-License-Identifier: AGPL-3.0-only
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { V2ModerationJournal } from "../../../windows/server/src/admin/v2-moderation.js";
import { ModerationStore } from "../../../windows/server/src/anticheat/index.js";
import { createPlayerAdmin } from "../../../windows/server/src/admin/v2-players.js";

const id1="1020304050607080",id2="aabbccddeeff0011",id3="ffeeddccbbaa1122";
test("player control only returns scoped safe display fields, no accounts, IP or emails",()=>{
  const game={players:[
    {id:id1,name:"Pessoa",ip:"10.1.1.1",account:{email:"private@example.com",role:"member"},connectedAt:1234,kick:()=>{}},
    {id:id2,name:"Guest",ip:"10.2.2.2",connectedAt:5678,kick:()=>{}},
    {id:id3,name:"Moderador",account:{role:"mod",email:"mod@private.example"},connectedAt:9876,kick:()=>{}}
  ]};
  const ctl=createPlayerAdmin(new Map([["LC",game]]));
  const list=ctl.execute({action:"players"});
  assert.deepEqual(list,{players:[
    {id:id1,name:"Pessoa",role:"player",connectedAt:1234},
    {id:id2,name:"Guest",role:"guest",connectedAt:5678},
    {id:id3,name:"Moderador",role:"mod",connectedAt:9876}
  ]});
  assert.doesNotMatch(JSON.stringify(list),/10\.1\.1\.1|private@example|mod@private/);
  assert.throws(()=>ctl.execute({action:"delete"}),/nao autorizado/);
});
test("kick applies to one exact session and protects moderators and admins",()=>{
  const kicked=[];
  const game={players:[
    {id:id1,account:{role:"player"},kick:reason=>kicked.push(["first",reason])},
    {id:id2,kick:reason=>kicked.push(["second",reason])},
    {id:id3,account:{role:"admin"},kick:reason=>kicked.push(["admin",reason])}
  ]};
  const ctl=createPlayerAdmin(new Map([["LC",game]]));
  assert.deepEqual(ctl.execute({action:"kick",playerId:id2}),{playerId:id2,status:"kicked"});
  assert.deepEqual(kicked,[["second","kicked"]]);
  assert.throws(()=>ctl.execute({action:"kick",playerId:id3}),/permissao de equipe/);
  assert.throws(()=>ctl.execute({action:"kick",playerId:"ABCDEF0123456789"}),/invalido/);
  assert.throws(()=>ctl.execute({action:"kick",playerId:"0000000000000000"}),/nao esta conectado/);
  assert.deepEqual(kicked,[["second","kicked"]]);
});

test("temporary bans use real moderation targets, persist, expire, can be revoked",{timeout:10000},()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"v2-moderation-"));
  try{
    const account={id:"acc-a",role:"player"};
    let disconnected=[];
    const game={players:[
      {id:id1,name:"Conta",account,kick:r=>disconnected.push(["account",r])},
      {id:id2,name:"Visita",did:"device-a",kick:r=>disconnected.push(["device",r])},
      {id:id3,name:"Equipe",account:{id:"staff",role:"mod"},kick:()=>assert.fail("staff kick")}
    ]};
    const blocks={accounts:{},devices:{}};
    const moderation={
      ban(payload){if(payload.accountId)blocks.accounts[payload.accountId]=payload.until;
        if(payload.did)blocks.devices[payload.did]=payload.until;},
      unbanAccount(id){delete blocks.accounts[id]},
      unbanIp(_,did){delete blocks.devices[did]}
    };
    const control=createPlayerAdmin(new Map([["LC",game]]),{moderation,dataDir:dir});
    assert.throws(()=>control.execute({action:"ban",playerId:id1,minutes:1,reason:"x"}),/Duracao/);
    assert.throws(()=>control.execute({action:"ban",playerId:id3,minutes:5,reason:"x"}),/Equipe/);
    const first=control.execute({action:"ban",playerId:id1,minutes:5,reason:"Teste"});
    assert.equal(first.status,"banned");
    assert.ok(blocks.accounts["acc-a"]>Date.now());
    assert.deepEqual(disconnected,[["account","banned"]]);
    assert.throws(()=>control.execute({action:"ban",playerId:id1,minutes:5,reason:"repetido"}),/ja possui/);
    const second=control.execute({action:"ban",playerId:id2,minutes:15,reason:"spam"});
    assert.equal(second.status,"banned");
    assert.ok(blocks.devices["device-a"]>Date.now());
    const bans=control.execute({action:"bans"}).bans;
    assert.equal(bans.length,2);
    assert.ok(!JSON.stringify(bans).includes("acc-a"));
    assert.ok(!JSON.stringify(bans).includes("device-a"));
    const history=control.execute({action:"history"}).history;
    assert.equal(history.length,2);
    assert.ok(history.every(x=>x.action==="ban"));
    const saved=new V2ModerationJournal(dir);
    assert.equal(saved.bans().length,2);
    const removed=control.execute({action:"unban",banId:first.id});
    assert.deepEqual(removed,{id:first.id,status:"unbanned"});
    assert.equal(blocks.accounts["acc-a"],undefined);
    assert.equal(control.execute({action:"history"}).history[0].action,"unban");
    assert.equal(new V2ModerationJournal(dir).bans().length,1);
    // Artificial expiration for deterministic test without sleeping.
    const journal=new V2ModerationJournal(dir);
    journal.data.active[0].until=Date.now()-1;journal.save();
    assert.deepEqual(journal.bans(),[]);
    assert.deepEqual(new V2ModerationJournal(dir).bans(),[]);
    assert.throws(()=>control.execute({action:"unban",banId:"000000000000000000000000"}),/nao encontrado/);
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
test("unauthenticated guests without device identity cannot be persistently banned",()=>{
  const game={players:[{id:id2,name:"Guest",kick:()=>assert.fail("should not kick")} ]};
  const moderation={ban:()=>assert.fail("should not ban")};
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"v2-guest-"));
  try{
    const ctl=createPlayerAdmin(new Map([["LC",game]]),{moderation,dataDir:dir});
    assert.throws(()=>ctl.execute({action:"ban",playerId:id2,minutes:5,reason:"x"}),/sem identificador persistente/);
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

test("authoritative ModerationStore enforces and expires timed account and device bans",()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"v2-real-ban-"));
  try{
    const moderation=new ModerationStore(dir);
    const now=Date.now();
    moderation.ban({accountId:"acct-123",name:"Jogador",until:now+60000,reason:"Teste"},{name:"panel"});
    moderation.ban({did:"device-123",name:"Visitante",until:now+60000,reason:"Teste"},{name:"panel"});
    assert.equal(moderation.isBanned("1.2.3.4","acct-123",null),true);
    assert.equal(moderation.isBanned("5.6.7.8",null,"device-123"),true);
    assert.equal(moderation.isBanned("1.2.3.4","unrelated",null),false);
    const loaded=new ModerationStore(dir);
    assert.equal(loaded.isBanned(null,"acct-123",null),true);
    loaded.unbanAccount("acct-123");
    assert.equal(loaded.isBanned(null,"acct-123",null),false);
    loaded.bans.devices["device-123"].until=Date.now()-1;
    loaded.saveBans();
    assert.equal(loaded.isBanned(null,null,"device-123"),false);
    assert.equal(new ModerationStore(dir).isBanned(null,null,"device-123"),false);
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
