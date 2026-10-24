// SPDX-License-Identifier: AGPL-3.0-only
import test from "node:test";
import assert from "node:assert/strict";
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
