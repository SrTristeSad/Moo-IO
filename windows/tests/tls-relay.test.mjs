// SPDX-License-Identifier: AGPL-3.0-only
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import net from "node:net";
import tls from "node:tls";
import {spawnSync} from "node:child_process";
import {startRelay,validHostname} from "../scripts/tls-relay.mjs";

const token="ab".repeat(24);
function close(s){return new Promise(resolve=>s.close(resolve));}
function listen(s){return new Promise((resolve,reject)=>{
  s.once("error",reject);s.listen(0,"127.0.0.1",()=>{
    s.off("error",reject);resolve(s.address().port);
  });
});}
async function freePort(){
  const server=net.createServer();const port=await listen(server);
  await close(server);return port;
}
function connectToRelay(port,host,secret=token){
  return new Promise((resolve,reject)=>{
    const socket=net.connect({host:"127.0.0.1",port},()=>{
      socket.write("MOOIO-TLS1 "+secret+" "+host+" 443\n");
      resolve(socket);
    });
    socket.once("error",reject);
  });
}
async function readUntilClose(socket){
  return await new Promise((resolve,reject)=>{
    let received="";
    const timeout=setTimeout(()=>{socket.destroy();reject(Error("socket response timeout"));},5000);
    socket.on("data",part=>{received+=part.toString("latin1")});
    socket.on("error",()=>{clearTimeout(timeout);resolve(received)});
    socket.on("end",()=>{clearTimeout(timeout);resolve(received)});
    socket.on("close",()=>{clearTimeout(timeout);resolve(received)});
  });
}
test("public TLS targets require DNS, not IP literals or injection",()=>{
  for(const host of ["normal.game.example.com","auth.play.example.org"]){
    assert.equal(validHostname(host),true,host);
  }
  for(const host of ["127.0.0.1","localhost","bad..example.com","evil.com\r\nHTTP",
    "EXAMPLE.COM","-evil.example.com","example.com:8080","192.168.1.20",
    "evil.example.com.","example.com/path","a".repeat(64)+".example.com"])
    assert.equal(validHostname(host),false,host);
});
test("native Windows relay uses CA trust + matching SNI and refuses untrusted or mismatched certificates",{timeout:20000},async()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"mooio-verified-tls-"));
  let target=null,bridge=null;
  try{
    const cert=path.join(dir,"cert.pem"),key=path.join(dir,"key.pem");
    const openssl=spawnSync("openssl",["req","-x509","-nodes","-newkey","rsa:2048",
      "-keyout",key,"-out",cert,"-days","1","-subj","/CN=normal.play.example.org",
      "-addext","subjectAltName=DNS:normal.play.example.org"],
      {encoding:"utf8",timeout:9000});
    assert.equal(openssl.status,0,openssl.stderr||openssl.error?.message);
    const certificate=fs.readFileSync(cert);
    target=tls.createServer({cert:certificate,key:fs.readFileSync(key)},socket=>{
      socket.on("data",data=>{
        if(data.toString("utf8").startsWith("GET /ping HTTP/1.1"))
          socket.end("HTTP/1.1 200 OK\r\nContent-Length: 4\r\nConnection: close\r\n\r\npong");
      });
    });
    const targetPort=await listen(target);
    const relayPort=await freePort();
    const requests=[];
    let trust=false;
    bridge=await startRelay({token,port:relayPort,createTls:options=>{
      requests.push(options);
      return tls.connect({...options,host:"127.0.0.1",port:targetPort,
        ...(trust?{ca:certificate}:{})});
    }});
    const untrusted=await connectToRelay(relayPort,"normal.play.example.org");
    const noTrust=await readUntilClose(untrusted);
    assert.doesNotMatch(noTrust,/\bOK\n/);
    assert.equal(requests.at(-1).rejectUnauthorized,true);
    assert.equal(requests.at(-1).servername,"normal.play.example.org");
    trust=true;
    const mismatch=await connectToRelay(relayPort,"wrong.play.example.org");
    assert.doesNotMatch(await readUntilClose(mismatch),/\bOK\n/);
    assert.equal(requests.at(-1).servername,"wrong.play.example.org");
    const wrongKey=await connectToRelay(relayPort,"normal.play.example.org","00".repeat(24));
    assert.equal(await readUntilClose(wrongKey),"");
    const good=await connectToRelay(relayPort,"normal.play.example.org");
    const ok=await new Promise((resolve,reject)=>{
      let data="";
      good.on("data",chunk=>{
        data+=chunk.toString("latin1");
        if(data.includes("OK\n")){
          good.removeAllListeners("data");
          good.write("GET /ping HTTP/1.1\r\nHost: normal.play.example.org\r\nConnection: close\r\n\r\n");
          resolve();
        }
      });
      good.once("error",reject);
      setTimeout(()=>reject(Error("TLS bridge did not accept trusted certificate")),4000);
    });
    assert.equal(ok,undefined);
    const page=await readUntilClose(good);
    assert.match(page,/HTTP\/1\.1 200 OK/);
    assert.match(page,/pong/);
  }finally{
    if(bridge)await close(bridge);
    if(target)await close(target);
    fs.rmSync(dir,{recursive:true,force:true});
  }
});
