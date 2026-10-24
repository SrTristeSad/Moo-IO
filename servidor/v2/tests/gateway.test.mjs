// SPDX-License-Identifier: AGPL-3.0-only
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { createRoom, newRoom } from "../core/config.mjs";
import { gatewayPlan, validateBaseDomain, buildGatewayPlan, renderCaddyfile } from "../core/gateway.mjs";
import { writeCaddyfile } from "../gateway.mjs";
const root=fileURLToPath(new URL("../../../",import.meta.url));
const script=path.join(root,"servidor/v2/gateway.mjs");
const temp=()=>fs.mkdtempSync(path.join(os.tmpdir(),"mooio-v2-gateway-"));
test("gateway preserva mods, usa dois hostnames publicos e roteia backend loopback",async()=>{
  const folder=temp();
  try{
    const normal=newRoom({name:"Normal",port:19880,capacity:40});
    const modded=newRoom({name:"Lobos",port:19881,preset:"custom",mods:["mais-lobos"]});
    createRoom(path.join(folder,"normal.json"),normal);
    createRoom(path.join(folder,"lobos.json"),modded);
    const plan=await gatewayPlan({rooms:folder,domain:"jogo.example.com"});
    assert.equal(plan.length,2);
    assert.deepEqual(plan.map(x=>x.hostname),["lobos.jogo.example.com","normal.jogo.example.com"]);
    assert.deepEqual(plan.map(x=>x.upstream),["127.0.0.1:19881","127.0.0.1:19880"]);
    const text=renderCaddyfile(plan);
    for(const item of plan){
      assert.ok(text.includes(item.hostname+" {"));
      assert.ok(text.includes("reverse_proxy "+item.upstream));
    }
    assert.match(text,/header_up X-Forwarded-For \{remote_host\}/);
    assert.match(text,/header_up -Forwarded/);
    assert.match(text,/header_up Host \{host\}/);
    assert.match(text,/@internal path \/admin\/\* \/mooio\/shutdown \/mooio\/status/);
    assert.match(text,/respond @internal 404/);
    assert.match(text,/Strict-Transport-Security/);
    assert.doesNotMatch(text,/8080\b|0\.0\.0\.0|secret|roomCode/);
    assert.doesNotMatch(text,new RegExp(normal.roomCode+"|"+modded.roomCode));
    const list=spawnSync(process.execPath,[script,"plan","--domain","jogo.example.com","--rooms",folder],{cwd:root,encoding:"utf8"});
    assert.equal(list.status,0,list.stderr);
    assert.match(list.stdout,/wss:\/\/normal\.jogo\.example\.com\/s\/LC/);
    const generate=spawnSync(process.execPath,[script,"generate","--domain","jogo.example.com","--rooms",folder],{cwd:root,encoding:"utf8"});
    assert.equal(generate.status,0,generate.stderr);
    assert.equal(generate.stdout,text);
  }finally{fs.rmSync(folder,{force:true,recursive:true});}
});
test("gateway falha fechado: DNS injection, sala com bind publico/VPN ou id com underscore",async()=>{
  const badDomains=["http://jogo.com","https://jogo.com","jogo.com:443",
    "foo/evil.com","www.EXAMPLE.com","127.0.0.1","localhost","host.local",
    "a..com","-bad.com","bad-.com","example.com\nanother.com","e".repeat(64)+".com"];
  for(const domain of badDomains)assert.throws(()=>validateBaseDomain(domain),undefined,domain);
  const base=[{id:"normal",room:newRoom({port:18000})}];
  assert.equal(buildGatewayPlan(base,{domain:"play.example.com"})[0].hostname,"normal.play.example.com");
  assert.throws(()=>buildGatewayPlan([{id:"evil_room",room:base[0].room}],{domain:"play.example.com"}),/ID de sala/);
  assert.throws(()=>buildGatewayPlan([{id:"normal",room:newRoom({host:"192.168.1.3",port:18001})}],{domain:"play.example.com"}),/127.0.0.1/);
  assert.throws(()=>buildGatewayPlan([{id:"normal",room:newRoom({host:"25.9.8.7",network:"vpn",port:18001})}],{domain:"play.example.com"}),/127.0.0.1/);
  assert.throws(()=>renderCaddyfile([{hostname:"evil.com\nreverse_proxy 1.2.3.4",upstream:"127.0.0.1:18000"}]),/invalido/);
});
test("arquivo Caddy nao sobrescreve por acidente, nao segue symlink e nao expoe convites",()=>{
  const folder=temp();
  try{
    const out=path.join(folder,"Caddyfile"),content="normal.example.com {\n reverse_proxy 127.0.0.1:18000\n}\n";
    assert.equal(writeCaddyfile(out,content),out);
    assert.equal(fs.readFileSync(out,"utf8"),content);
    assert.throws(()=>writeCaddyfile(out,"evil"),/ja existe/);
    assert.equal(fs.readFileSync(out,"utf8"),content);
    assert.equal(writeCaddyfile(out,content+"# edited\n",{force:true}),out);
    assert.ok(fs.readFileSync(out,"utf8").includes("# edited"));
    if(process.platform!=="win32"){
      assert.equal(fs.statSync(out).mode&0o777,0o600);
      const symlink=path.join(folder,"symlink");
      fs.symlinkSync(out,symlink);
      assert.throws(()=>writeCaddyfile(symlink,"bad",{force:true}),/inseguro/);
    }
  }finally{fs.rmSync(folder,{force:true,recursive:true});}
});

test("optional auth domain gateway exposes only browser login endpoints",()=>{
  const plan=buildGatewayPlan([{id:"normal",room:newRoom({port:18440})}],{domain:"play.example.com"});
  const generated=renderCaddyfile(plan,{identityHost:"auth.play.example.com",identityPort:8788});
  assert.match(generated,/auth\.play\.example\.com \{/);
  assert.match(generated,/@auth_public path \/login \/login\/submit \/v1\/authorize\/start \/v1\/authorize\/token/);
  assert.match(generated,/reverse_proxy 127\.0\.0\.1:8788/);
  assert.match(generated,/respond 404/);
  assert.doesNotMatch(generated,/@auth_public.*\/internal\/introspect/);
  assert.throws(()=>renderCaddyfile(plan,{identityHost:"normal.play.example.com"}),/duplicados/);
  assert.throws(()=>renderCaddyfile(plan,{identityHost:"auth.play.example.com",identityPort:443}),/invalidos/);
});
