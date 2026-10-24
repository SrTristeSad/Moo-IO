#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Local TCP-to-TLS transport for the distributed Windows/LÖVE client.
// Each connection is pinned to a DNS name, TLS SNI + platform CA roots.
// There is NO arbitrary public proxy, no HTTP downgrade, and no token logging.
import net from "node:net";
import tls from "node:tls";
import path from "node:path";
import {fileURLToPath} from "node:url";

const DNS=/^(?=.{4,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24}$/;
const TOKEN=/^[a-f0-9]{48}$/;
const DEFAULT_PORT=8469;
export function validHostname(value){
  return typeof value==="string"&&value===value.toLowerCase()&&DNS.test(value);
}
export async function startRelay({token=process.env.MOOIO_TLS_TOKEN,port=DEFAULT_PORT}={}){
  if(!TOKEN.test(token||"")||!Number.isInteger(port)||port<1024||port>65535)
    throw Error("Credencial ou porta TLS local invalida");
  const server=net.createServer(client=>{
    if(client.remoteAddress!=="127.0.0.1"&&client.remoteAddress!=="::ffff:127.0.0.1"){
      client.destroy();return;
    }
    client.setTimeout(7000,()=>client.destroy());
    let preface="",connected=false,remote=null;
    const cleanup=()=>{if(remote)remote.destroy();};
    client.on("close",cleanup);
    client.on("error",()=>client.destroy());
    const start=(buffer)=>{
      preface+=buffer.toString("latin1");
      if(preface.length>360){client.destroy();return;}
      const end=preface.indexOf("\n");
      if(end===-1)return;
      if(end!==preface.length-1){client.destroy();return;} // no pipelined plaintext
      const match=/^MOOIO-TLS1 ([a-f0-9]{48}) ([a-z0-9.-]+) 443\r?\n$/.exec(preface);
      if(!match||match[1]!==token||!validHostname(match[2])){
        client.destroy();return;
      }
      connected=true;client.removeListener("data",start);
      client.pause();
      remote=tls.connect({
        host:match[2],port:443,servername:match[2],
        rejectUnauthorized:true,minVersion:"TLSv1.2"
      });
      remote.setTimeout(7000,()=>remote.destroy());
      remote.once("secureConnect",()=>{
        if(!remote.authorized){client.destroy();remote.destroy();return;}
        client.setTimeout(0);remote.setTimeout(0);
        client.write("OK\n");
        client.pipe(remote);remote.pipe(client);
        client.resume();
      });
      remote.on("error",()=>client.destroy());
      remote.on("close",()=>client.destroy());
    };
    client.on("data",start);
  });
  await new Promise((resolve,reject)=>{
    server.once("error",reject);
    server.listen(port,"127.0.0.1",()=>{
      server.off("error",reject);resolve();
    });
  });
  return server;
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===path.resolve(process.argv[1])){
  startRelay().catch(()=>process.exitCode=1);
}
