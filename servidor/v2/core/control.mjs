// SPDX-License-Identifier: AGPL-3.0-only
// Private local control channel. Does NOT bind an HTTP port or expose admin
// commands to reverse proxies. Linux: 0600 Unix socket. Windows: named pipe,
// additionally authenticated with a per-installation 256-bit token.
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import net from "node:net";
import { randomBytes, createHash, timingSafeEqual } from "node:crypto";

const ID=/^[a-z][a-z0-9_-]{0,47}$/;
const MAX_REQUEST=4096;
export function controlPaths(roomsDirectory){
  const folder=path.resolve(roomsDirectory);
  const privateDir=path.join(folder,".control");
  const hash=createHash("sha256").update(folder).digest("hex").slice(0,28);
  const endpoint=process.platform==="win32"
    ? "\\\\.\\pipe\\mooio-v2-"+hash
    : path.join(privateDir,"control.sock");
  if(process.platform!=="win32"&&Buffer.byteLength(endpoint)>100)
    throw Error("Caminho do socket local muito longo; use uma pasta de salas mais curta.");
  return {privateDir,endpoint,tokenFile:path.join(privateDir,"admin.token")};
}
function ensureControlDirectory(privateDir){
  if(!fs.existsSync(privateDir))fs.mkdirSync(privateDir,{recursive:false,mode:0o700});
  const stat=fs.lstatSync(privateDir);
  if(!stat.isDirectory()||stat.isSymbolicLink())throw Error("Diretorio de controle invalido");
  if(process.platform!=="win32"&&(stat.mode&0o077)!==0)
    throw Error("Diretorio de controle precisa de permissao 0700");
}
function loadToken(tokenFile,{create=false}={}){
  if(!fs.existsSync(tokenFile)){
    if(!create)throw Error("Controlador nao inicializado: arquivo de autenticacao ausente");
    try{fs.writeFileSync(tokenFile,randomBytes(32).toString("hex")+"\n",{flag:"wx",mode:0o600});}
    catch(error){if(error.code!=="EEXIST")throw error;}
  }
  const stat=fs.lstatSync(tokenFile);
  if(!stat.isFile()||stat.isSymbolicLink()||stat.size>100||
     (process.platform!=="win32"&&(stat.mode&0o077)!==0))
    throw Error("Arquivo de controle precisa ser regular e com permissao 0600");
  const token=fs.readFileSync(tokenFile,"utf8").trim();
  if(!/^[a-f0-9]{64}$/.test(token))throw Error("Token de controle invalido");
  return token;
}
function equalToken(left,right){
  if(typeof left!=="string"||!/^[a-f0-9]{64}$/.test(left))return false;
  return timingSafeEqual(Buffer.from(left,"hex"),Buffer.from(right,"hex"));
}
async function clearStaleSocket(endpoint){
  if(process.platform==="win32"||!fs.existsSync(endpoint))return;
  const stat=fs.lstatSync(endpoint);
  if(!stat.isSocket()||stat.isSymbolicLink())
    throw Error("Caminho do socket ocupado por arquivo inesperado; nao sera substituido");
  const active=await new Promise(resolve=>{
    const check=net.createConnection(endpoint);
    let done=false;
    const finish=alive=>{if(done)return;done=true;check.destroy();resolve(alive);};
    check.setTimeout(600,()=>finish(true));
    check.once("connect",()=>finish(true));
    check.once("error",e=>finish(e.code!=="ECONNREFUSED"&&e.code!=="ENOENT"));
  });
  if(active)throw Error("Outro supervisor ja usa o socket privado.");
  fs.unlinkSync(endpoint);
}
export async function startControlServer(roomsDirectory,{onRestart,onStart}){
  if(typeof onRestart!=="function")throw Error("Callback de reinicio ausente");
  if(onStart!==undefined&&typeof onStart!=="function")throw Error("Callback de inicializacao invalido");
  const {privateDir,endpoint,tokenFile}=controlPaths(roomsDirectory);
  ensureControlDirectory(privateDir);
  const token=loadToken(tokenFile,{create:true});
  await clearStaleSocket(endpoint);
  const server=net.createServer(socket=>{
    socket.setTimeout(12000,()=>socket.destroy());
    let chunks="",finished=false;
    socket.on("data",async data=>{
      if(finished)return;
      chunks+=data.toString("utf8");
      if(Buffer.byteLength(chunks)>MAX_REQUEST){finished=true;socket.end('{"ok":false,"error":"requestTooLarge"}\n');return;}
      const pos=chunks.indexOf("\n");
      if(pos<0)return;
      finished=true;
      let request;
      try{request=JSON.parse(chunks.slice(0,pos));}catch{
        socket.end('{"ok":false,"error":"invalidJson"}\n');return;
      }
      if(!equalToken(request?.token,token)){
        socket.end('{"ok":false,"error":"unauthorized"}\n');return;
      }
      if(!["restart","start"].includes(request.command)||typeof request.room!=="string"||!ID.test(request.room)||
         (request.command==="start"&&typeof onStart!=="function")){
        socket.end('{"ok":false,"error":"invalidCommand"}\n');return;
      }
      try{
        const result=request.command==="start"?await onStart(request.room):await onRestart(request.room);
        if(!socket.destroyed)socket.end(JSON.stringify({ok:true,result})+"\n");
      }catch(error){
        if(!socket.destroyed)socket.end(JSON.stringify({ok:false,error:String(error.message).slice(0,240)})+"\n");
      }
    });
    socket.on("error",()=>{});
  });
  try{
    await new Promise((resolve,reject)=>{
      server.once("error",reject);
      server.listen(endpoint,()=>{server.removeListener("error",reject);resolve();});
    });
    if(process.platform!=="win32")fs.chmodSync(endpoint,0o600);
  }catch(error){server.close();throw error;}
  return {
    endpoint,
    async close(){
      // No new commands once the process starts shutting down.
      await new Promise(resolve=>server.close(resolve));
      if(process.platform!=="win32"){
        try{const stat=fs.lstatSync(endpoint);if(stat.isSocket())fs.unlinkSync(endpoint);}
        catch(e){if(e.code!=="ENOENT")throw e;}
      }
    }
  };
}
async function requestRoomCommand(roomsDirectory,id,command){
  if(!ID.test(id))throw Error("ID da sala invalido");
  const {privateDir,endpoint,tokenFile}=controlPaths(roomsDirectory);
  ensureControlDirectory(privateDir);
  const token=loadToken(tokenFile);
  return await new Promise((resolve,reject)=>{
    const socket=net.createConnection(endpoint);
    let result="",settled=false;
    const finish=(error,value)=>{
      if(settled)return;settled=true;socket.destroy();
      if(error)reject(error);else resolve(value);
    };
    socket.setTimeout(15000,()=>finish(Error("Supervisor nao respondeu em 15 segundos")));
    socket.once("connect",()=>socket.write(JSON.stringify({token,command,room:id})+"\n"));
    socket.on("data",data=>{
      result+=data.toString("utf8");
      if(Buffer.byteLength(result)>MAX_REQUEST)return finish(Error("Resposta muito grande"));
      const line=result.indexOf("\n");if(line<0)return;
      try{
        const payload=JSON.parse(result.slice(0,line));
        if(!payload.ok)finish(Error(String(payload.error||"Falha ao reiniciar sala")));
        else finish(null,payload.result);
      }catch(error){finish(error);}
    });
    socket.once("error",error=>finish(Error("Supervisor indisponivel: "+error.message)));
    socket.once("end",()=>finish(Error("Supervisor encerrou sem responder")));
  });
}

export function requestRoomRestart(roomsDirectory,id){return requestRoomCommand(roomsDirectory,id,"restart");}
export function requestRoomStart(roomsDirectory,id){return requestRoomCommand(roomsDirectory,id,"start");}
