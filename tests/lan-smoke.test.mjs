// SPDX-License-Identifier: AGPL-3.0-only
import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const root=resolve(fileURLToPath(new URL("..",import.meta.url)));
const requireServer=createRequire(resolve(root,"server/package.json"));
const WebSocket=requireServer("ws");
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));

test("LAN room: code-protected ticket, public protocol, two websocket guests", {timeout:25000},async ()=>{
    const tmp=mkdtempSync(join(tmpdir(),"moo-io-"));
    const port=20000+Math.floor(Math.random()*20000);
    const host='127.0.0.1';
    const base='http://'+host+':'+port;
    const env={...process.env,DATA_DIR:tmp,PROTOCOL_BUILD_FILE:join(tmp,"protocol-build.json"),
        PORT:String(port),HOST:host,MOO_IO_ROOM_CODE:"lanroom98765"};
    const child=spawn(process.execPath,["server/src/index.js"],{cwd:root,env,stdio:["ignore","pipe","pipe"]});
    let output="";
    child.stdout.on("data",b=>{output+=b.toString();});
    child.stderr.on("data",b=>{output+=b.toString();});
    let ready=false;
    try{
        for(let i=0;i<60;i++){
            if(child.exitCode!==null) break;
            try { const r=await fetch(base+"/mooio/status",{signal:AbortSignal.timeout(800)});
                if(r.ok && (await r.json()).project==="Moo-IO"){ready=true;break;} }catch{}
            await sleep(150);
        }
        assert.equal(ready,true,"Node server did not start: "+output.slice(-2000));
        const ping=await (await fetch(base+"/ping")).json();
        const prot=await (await fetch(base+"/mooio/protocol")).json();
        assert.equal(prot.buildId,ping.build);
        assert.equal(prot.constants.length,8);
        assert.equal(Object.hasOwn(prot,"sealHex"),false);
        const body=JSON.stringify({host:base+"/s/LC",captcha:true});
        const attempt=code=>fetch(base+"/api/join",{
            method:"POST",headers:{"content-type":"application/json",...(code?{"X-MooIO-Code":code}:{})},body
        });
        assert.equal((await attempt()).status,403,"must reject absent invite");
        assert.equal((await attempt("wrong-code")).status,403,"must reject wrong invite");
        const a=await attempt("lanroom98765"),b=await attempt("lanroom98765");
        assert.equal(a.status,200);assert.equal(b.status,200);
        const ticket1=(await a.json()).ticket,ticket2=(await b.json()).ticket;
        assert.ok(ticket1&&ticket2&&ticket1!==ticket2);
        const wsJoin=ticket=>new Promise((resolve,reject)=>{
            const socket=new WebSocket('ws://'+host+':'+port+'/s/LC?b='+ping.build+'&token=tk:'+ticket,
                {headers:{Origin:base}});
            const timeout=setTimeout(()=>{socket.terminate();reject(new Error("No handshake"));},4000);
            socket.once("message",payload=>{
                clearTimeout(timeout);
                assert.ok(payload.length>8);
                resolve(socket);
            });
            socket.once("error",err=>{clearTimeout(timeout);reject(err);});
            socket.once("unexpected-response",()=>{clearTimeout(timeout);reject(new Error("WebSocket rejected"));});
        });
        const sockets=await Promise.all([wsJoin(ticket1),wsJoin(ticket2)]);
        assert.equal(sockets.length,2);
        for(const ws of sockets) ws.close();
    } finally {
        if(child.exitCode===null) child.kill("SIGTERM");
        await sleep(300);
        rmSync(tmp,{recursive:true,force:true});
    }
});
