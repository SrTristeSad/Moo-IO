// SPDX-License-Identifier: AGPL-3.0-only
import test from "node:test";
import assert from "node:assert/strict";
import {spawn} from "node:child_process";
import {mkdtempSync,rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join,resolve} from "node:path";
import {fileURLToPath} from "node:url";

const root=resolve(fileURLToPath(new URL("..",import.meta.url)));
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function until(fn,attempts=70){
    for(let i=0;i<attempts;i++){
        try {const result=await fn(); if(result)return result;}catch{}
        await delay(120);
    }
    return null;
}
test("GUI room controller is local only and accepts only the room owner code", {timeout:25000},async()=>{
    const tmp=mkdtempSync(join(tmpdir(),"moo-io-control-"));
    const port=30000+Math.floor(Math.random()*25000);
    const child=spawn(process.execPath,["server/src/index.js"],{
        cwd:root,env:{...process.env,HOST:"127.0.0.1",PORT:String(port),MOO_IO_NETWORK_MODE:"lan",
            MOO_IO_GUI_HOST:"1",MOO_IO_ROOM_CODE:"ownercode1234",DATA_DIR:tmp,
            PROTOCOL_BUILD_FILE:join(tmp,"protocol-build.json")},
        stdio:"ignore"
    });
    const control="http://127.0.0.1:"+(port+1);
    try {
        const ready=await until(async()=>{
            const r=await fetch(control+"/status",{signal:AbortSignal.timeout(900)});
            return r.ok?await r.json():null;
        });
        assert.equal(ready?.project,"Moo-IO");
        assert.equal(ready?.host,"127.0.0.1");
        const wrong=await fetch(control+"/shutdown",{method:"POST",headers:{"x-mooio-code":"not-the-code"}});
        assert.equal(wrong.status,403);
        const status=await (await fetch("http://127.0.0.1:"+port+"/mooio/status")).json();
        assert.equal(status.project,"Moo-IO");
        const shutdown=await fetch(control+"/shutdown",{method:"POST",headers:{"x-mooio-code":"ownercode1234"}});
        assert.equal(shutdown.status,200);
        assert.ok(await until(()=>child.exitCode!==null,35),"owner control should stop Node");
    } finally {
        if(child.exitCode===null)child.kill("SIGKILL");
        rmSync(tmp,{recursive:true,force:true});
    }
});
test("public or wildcard bind address is rejected before starting the game", {timeout:12000},async()=>{
    for(const HOST of ["0.0.0.0","8.8.8.8"]){
        const tmp=mkdtempSync(join(tmpdir(),"moo-io-invalid-"));
        const child=spawn(process.execPath,["server/src/index.js"],{
            cwd:root,env:{...process.env,HOST,MOO_IO_ROOM_CODE:"valid1234",DATA_DIR:tmp},stdio:"ignore"
        });
        try{
            assert.ok(await until(()=>child.exitCode!==null,30),"must reject "+HOST);
            assert.notEqual(child.exitCode,0);
        }finally{
            if(child.exitCode===null)child.kill("SIGKILL");
            rmSync(tmp,{recursive:true,force:true});
        }
    }
});
