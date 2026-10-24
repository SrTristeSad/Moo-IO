// SPDX-License-Identifier: AGPL-3.0-only
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import net from "node:net";
import {spawn} from "node:child_process";
import {createHash} from "node:crypto";
import {fileURLToPath} from "node:url";
import {createIdentityService,publicOrigin} from "../core/identity.mjs";
import {newRoom,createRoom} from "../core/config.mjs";

const root=fileURLToPath(new URL("../../../",import.meta.url));
const temp=()=>fs.mkdtempSync(path.join(os.tmpdir(),"mooio-browser-auth-"));
async function port(){
  const listener=net.createServer();
  await new Promise(resolve=>listener.listen(0,"127.0.0.1",resolve));
  const result=listener.address().port;
  await new Promise(resolve=>listener.close(resolve));
  return result;
}
const verifier="a".repeat(64);
const challenge=createHash("sha256").update(verifier).digest("base64url");
async function post(url,body,extraHeaders={}){
  return fetch(url,{method:"POST",headers:{"Content-Type":"application/json","Connection":"close",...extraHeaders},
    body:JSON.stringify(body)});
}
async function authorize(base,email,password,{register=true}={}){
  const start=await post(base+"/v1/authorize/start",{challenge});
  assert.equal(start.status,200);
  const flow=await start.json();
  assert.match(flow.id,/^[a-f0-9]{40}$/);
  assert.equal(flow.verificationUri,base+"/login?id="+flow.id);
  const pending=await post(base+"/v1/authorize/token",{id:flow.id,verifier});
  assert.equal(pending.status,202);
  assert.equal((await pending.json()).status,"pending");
  const wrong=await post(base+"/v1/authorize/token",{id:flow.id,verifier:"b".repeat(64)});
  assert.equal(wrong.status,403);
  const page=await fetch(flow.verificationUri);
  assert.equal(page.status,200);
  const html=await page.text();
  assert.match(html,/Entrar e autorizar/);
  const csrf=html.match(/name="csrf" value="([a-f0-9]{48})"/)?.[1];
  assert.ok(csrf);
  const cookie=page.headers.get("set-cookie").split(";")[0];
  const form=new URLSearchParams({id:flow.id,csrf,email,password,
    action:register?"register":"login"});
  const denied=await fetch(base+"/login/submit",{method:"POST",
    headers:{"Origin":base,"Content-Type":"application/x-www-form-urlencoded"},
    body:form,redirect:"manual"});
  assert.equal(denied.status,403,"missing browser CSRF cookie must be denied");
  const result=await fetch(base+"/login/submit",{method:"POST",
    headers:{"Origin":base,"Cookie":cookie,"Content-Type":"application/x-www-form-urlencoded"},
    body:form,redirect:"manual"});
  assert.equal(result.status,200,await result.text());
  const exchange=await post(base+"/v1/authorize/token",{id:flow.id,verifier});
  assert.equal(exchange.status,200);
  const session=await exchange.json();
  assert.match(session.token,/^[a-f0-9]{64}$/);
  const replay=await post(base+"/v1/authorize/token",{id:flow.id,verifier});
  assert.equal(replay.status,410);
  return session.token;
}
test("browser login: cross-site blocked, salted password, PKCE, registration, one-time exchange, restart-safe session",{timeout:30000},async()=>{
  const dir=temp(),p=await port(),base="http://127.0.0.1:"+p,identityDir=path.join(dir,".identity");
  let hub;
  try{
    hub=await createIdentityService({dataDir:identityDir,origin:base,port:p});
    assert.throws(()=>publicOrigin("http://example.net"),/HTTPS/);
    assert.throws(()=>publicOrigin("https://evil.test/path"),/somente/);
    const token=await authorize(base,"player@example.org","correct-long-password-2026");
    const passwordFile=fs.readFileSync(path.join(identityDir,"v2-credentials.json"),"utf8");
    assert.doesNotMatch(passwordFile,/correct-long-password-2026/);
    if(process.platform!=="win32")assert.equal(fs.statSync(path.join(identityDir,"hub.secret")).mode&0o777,0o600);
    const secret=fs.readFileSync(path.join(identityDir,"hub.secret"),"utf8");
    const introspect=(secretValue,tokenValue)=>post(base+"/internal/introspect",{token:tokenValue},
      {"X-MooIO-Internal-Secret":secretValue});
    assert.equal((await introspect("0".repeat(64),token)).status,403);
    const introspection=await introspect(secret,token);
    assert.deepEqual(await introspection.json(),{active:true,email:"player@example.org"});
    await hub.close();hub=null;
    hub=await createIdentityService({dataDir:identityDir,origin:base,port:p});
    assert.equal((await introspect(secret,token).then(r=>r.json())).active,true);
    const again=await authorize(base,"player@example.org","correct-long-password-2026",{register:false});
    assert.notEqual(again,token);
    const revoked=await post(base+"/v1/session/revoke",{},
      {"Authorization":"Bearer "+token});
    assert.equal(revoked.status,200);
    assert.deepEqual(await introspect(secret,token).then(r=>r.json()),{active:false});
    assert.equal((await introspect(secret,again).then(r=>r.json())).active,true);
  }finally{if(hub)await hub.close();fs.rmSync(dir,{recursive:true,force:true});}
});
test("same browser identity exchanges into two isolated V2 rooms without the password crossing the game API",{timeout:50000},async()=>{
  const dir=temp(),authPort=await port(),ports=[];
  while(ports.length<2){const candidate=await port();if(candidate!==authPort&&!ports.includes(candidate))ports.push(candidate);}
  const base="http://127.0.0.1:"+authPort,rooms=path.join(dir,"rooms");
  fs.mkdirSync(rooms,{recursive:true});
  const configurations=ports.map((number,i)=>{
    const r=newRoom({name:"Partida "+i,port:number,capacity:10});
    createRoom(path.join(rooms,"partida"+i+".json"),r);
    return r;
  });
  let hub,manager,logs="";
  try{
    hub=await createIdentityService({dataDir:path.join(rooms,".identity"),origin:base,port:authPort});
    const browserToken=await authorize(base,"shared@example.org","long-password-2026-unique");
    manager=spawn(process.execPath,[path.join(root,"servidor/v2/manager.mjs"),"start","--rooms",rooms],{
      cwd:root,env:{...process.env,MOO_IO_V2_AUTH_PORT:String(authPort)},
      stdio:["ignore","pipe","pipe"]
    });
    manager.stdout.on("data",d=>logs+=d.toString());
    manager.stderr.on("data",d=>logs+=d.toString());
    let ready=false;
    for(let i=0;i<100;i++){
      try{
        const ok=await Promise.all(ports.map(n=>fetch("http://127.0.0.1:"+n+"/ping",
          {signal:AbortSignal.timeout(250)}).then(r=>r.ok)));
        if(ok.every(Boolean)){ready=true;break;}
      }catch{}
      await new Promise(resolve=>setTimeout(resolve,120));
    }
    assert.equal(ready,true,logs.slice(-2000));
    const ids=[];
    for(let i=0;i<2;i++){
      const port=ports[i],endpoint="http://127.0.0.1:"+port;
      const blocked=await post(endpoint+"/api/auth/browser",{token:"f".repeat(64)});
      assert.equal(blocked.status,403,await blocked.text());
      const login=await post(endpoint+"/api/auth/browser",{token:browserToken});
      assert.equal(login.status,200);
      const session=await login.json();
      assert.equal(session.email,"shared@example.org");
      assert.match(session.token,/^[\w-]+\.[\w-]+\.[\w-]+$/);
      ids.push(session.id);
      const join=await post(endpoint+"/api/join",{
        auth:session.token,host:endpoint+"/s/LC"
      },{"X-MooIO-Code":configurations[i].roomCode});
      assert.equal(join.status,200);
      assert.match((await join.json()).ticket,/^[a-f0-9]{36}$/);
    }
    assert.equal(ids.length,2);
    assert.ok(!logs.includes("long-password-2026-unique"));
  }finally{
    if(manager&&manager.exitCode===null){
      manager.kill("SIGTERM");
      await Promise.race([new Promise(r=>manager.once("close",r)),
        new Promise(r=>setTimeout(r,3000))]);
      if(manager.exitCode===null)manager.kill("SIGKILL");
    }
    if(hub)await hub.close();
    fs.rmSync(dir,{recursive:true,force:true});
  }
});
