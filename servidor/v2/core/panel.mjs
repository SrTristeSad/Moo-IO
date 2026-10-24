// SPDX-License-Identifier: AGPL-3.0-only
// Private browser admin dashboard. ALWAYS bind to loopback; never proxy publicly.
// Uses standard Node.js HTTP, an isolated password store and short-lived sessions.
import fs from "node:fs";
import path from "node:path";
import http from "node:http";
import { randomBytes, timingSafeEqual } from "node:crypto";
import { fileURLToPath } from "node:url";
import { LocalCredentials } from "../../../windows/server/src/api/credentials.js";
import { controlPaths, requestRoomRestart, requestRoomStart } from "./control.mjs";
import { newRoom, createRoom, readRoom, readModFile, listMods, updateRoom } from "./config.mjs";
import { discoverRooms, checkRooms, DEFAULT_ROOMS, MAX_ROOMS } from "./supervisor.mjs";
import { scanRooms } from "./monitor.mjs";
import { planRoom } from "./loader.mjs";

export const ADMIN_EMAIL="admin@panel.invalid";
const ID=/^[a-z][a-z0-9-]{0,47}$/;
const SESSION_TTL=2*60*60*1000;
const BODY_LIMIT=12*1024;
const MAX_SESSIONS=16;
const staticDir=fileURLToPath(new URL("../panel-ui/",import.meta.url));

function hex(){return randomBytes(32).toString("hex");}
function matchSecret(a,b){
  if(typeof a!=="string"||typeof b!=="string"||a.length!==b.length)return false;
  return timingSafeEqual(Buffer.from(a),Buffer.from(b));
}
function httpError(status,message){
  const error=Error(message);error.status=status;return error;
}
function privateDir(rooms){
  const {privateDir}=controlPaths(rooms);
  if(!fs.existsSync(privateDir))fs.mkdirSync(privateDir,{recursive:false,mode:0o700});
  const stat=fs.lstatSync(privateDir);
  if(!stat.isDirectory()||stat.isSymbolicLink()||
     (process.platform!=="win32"&&(stat.mode&0o077)!==0))
    throw Error("Diretorio privado do painel deve ser 0700 e nao symlink.");
  return privateDir;
}
export function panelCredentials(rooms){
  const directory=path.resolve(rooms);
  if(!fs.lstatSync(directory).isDirectory())throw Error("Pasta de salas invalida");
  return new LocalCredentials(privateDir(directory));
}
function roomInfo(entry,status){
  const {id,room}=entry;
  return {id,name:room.name,preset:room.preset,host:room.host,port:room.port,
    capacity:room.capacity,bots:room.bots,mods:[...room.mods],
    online:!!status?.online,players:status?.online?status.players:0,
    reason:status?.online?null:status?.reason||"Sala ainda nao iniciou"};
}
function checkPayload(data,fields){
  if(!data||Array.isArray(data)||typeof data!=="object")throw httpError(400,"Dados invalidos");
  for(const key of Object.keys(data))if(!fields.includes(key))throw httpError(400,"Campo nao permitido: "+key);
}
function settings(body,{requireAll=false}={}){
  const result={};
  for(const key of ["name","preset","capacity","bots","mods"]){
    if(!Object.hasOwn(body,key)){
      if(requireAll)throw httpError(400,"Informe "+key);
      continue;
    }
    const value=body[key];
    if(key==="mods"){
      if(!Array.isArray(value))throw httpError(400,"Mods precisam ser uma lista");
      result.mods=value;
    }else result[key]=value;
  }
  return result;
}
function ensureRoomId(id){
  if(!ID.test(id))throw httpError(400,"ID: letras minusculas, numeros e hifens; inicie com letra");
  return id;
}
function entriesOrEmpty(rooms){
  const entries=fs.readdirSync(rooms).filter(n=>n.endsWith(".json"));
  if(!entries.length)return [];
  return discoverRooms(rooms);
}
async function safeOverview(rooms){
  const entries=entriesOrEmpty(rooms);
  const report=entries.length?await scanRooms(entries):null;
  const byId=new Map((report?.rooms||[]).map(row=>[row.id,row]));
  return {rooms:entries.map(item=>roomInfo(item,byId.get(item.id))),
    totals:report?.totals||{rooms:0,online:0,offline:0,players:0,capacity:0},
    // Never includes roomCode, private keys or password hash.
    time:new Date().toISOString()};
}
function catalog(){
  return listMods().map(id=>{
    const mod=readModFile(id);
    return {id,name:mod.name,description:String(mod.description||"").slice(0,500)};
  });
}
function safeIdFromPathname(url){
  const match=/^\/api\/rooms\/([^/]+)(\/(?:restart|start))?$/.exec(url);
  if(!match)return null;
  return {id:ensureRoomId(match[1]),action:match[2]?.slice(1)||null};
}
function readJson(req){
  return new Promise((resolve,reject)=>{
    let size=0,pieces=[];
    req.on("data",chunk=>{
      size+=chunk.length;
      if(size>BODY_LIMIT){reject(httpError(413,"Requisicao muito grande"));req.destroy();return;}
      pieces.push(chunk);
    });
    req.once("end",()=>{
      try{resolve(JSON.parse(Buffer.concat(pieces).toString("utf8")));}
      catch{reject(httpError(400,"JSON invalido"));}
    });
    req.once("error",reject);
  });
}
function sessionFromCookie(req,sessions){
  const match=/(?:^|;\s*)mooio_admin=([a-f0-9]{64})(?:;|$)/.exec(req.headers.cookie||"");
  if(!match)return null;
  const record=sessions.get(match[1]);
  if(!record)return null;
  if(record.expires<Date.now()){sessions.delete(match[1]);return null;}
  record.expires=Date.now()+SESSION_TTL;
  return {sid:match[1],...record};
}
function headers(res){
  res.setHeader("Cache-Control","no-store");
  res.setHeader("X-Content-Type-Options","nosniff");
  res.setHeader("X-Frame-Options","DENY");
  res.setHeader("Referrer-Policy","no-referrer");
  res.setHeader("Cross-Origin-Opener-Policy","same-origin");
  res.setHeader("Content-Security-Policy","default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'");
}
function send(res,status,value){
  res.statusCode=status;
  res.setHeader("Content-Type","application/json; charset=utf-8");
  res.end(JSON.stringify(value));
}
function requireValidOrigin(req,allowed){
  const origin=req.headers.origin;
  if(!origin||!allowed.has(origin))throw httpError(403,"Origem nao autorizada");
}
function formRequest(req,allowed,session){
  requireValidOrigin(req,allowed);
  if(!session||!matchSecret(req.headers["x-csrf-token"],session.csrf))
    throw httpError(403,"Sessao ou token CSRF invalido");
}
function isLoopback(req){
  return ["127.0.0.1","::1","::ffff:127.0.0.1"].includes(req.socket.remoteAddress);
}
function filePage(res,filename,type){
  const data=fs.readFileSync(path.join(staticDir,filename));
  res.statusCode=200;
  res.setHeader("Content-Type",type);
  res.end(data);
}
async function mutateRoom(rooms,id,payload,{create=false}={}){
  ensureRoomId(id);
  const file=path.join(rooms,id+".json");
  if(create&&fs.existsSync(file))throw httpError(409,"ID de sala ja existe");
  if(!create&&!fs.existsSync(file))throw httpError(404,"Sala nao encontrada");
  const current=entriesOrEmpty(rooms);
  let room;
  if(create){
    checkPayload(payload,["id","name","preset","port","capacity","bots","mods"]);
    if(payload.id!==id||!Number.isInteger(payload.port))throw httpError(400,"ID ou porta invalido");
    if(current.length>=MAX_ROOMS)throw httpError(409,"Limite de salas atingido");
    if(current.some(entry=>entry.room.port===payload.port))throw httpError(409,"Porta ja ocupada por outra sala");
    room=newRoom({name:payload.name,preset:payload.preset,port:payload.port,
      capacity:payload.capacity,bots:payload.bots,mods:payload.mods,
      host:"127.0.0.1",network:"lan"});
  }else{
    checkPayload(payload,["name","preset","capacity","bots","mods"]);
    room={...readRoom(file),...settings(payload)};
  }
  await planRoom(room);
  // validate entire would-be world before persisting, not after mutation.
  await checkRooms(current.filter(entry=>entry.id!==id).concat([{id,file,room}]));
  if(create)createRoom(file,room);else updateRoom(file,room);
  let activation=null;
  let notice="Configuracao salva. Reinicie somente esta sala para aplicar.";
  if(create){
    try{
      activation=await requestRoomStart(rooms,id);
      notice="Sala criada e inicializacao solicitada. Outras salas continuam ativas.";
    }catch(error){
      activation={id,status:"pending"};
      // A stopped supervisor is not a reason to discard a successfully
      // validated room. The admin can click "Iniciar" when it is available.
      notice="Sala salva, mas ainda nao iniciada: "+String(error.message).slice(0,150);
    }
  }
  return {id,name:room.name,preset:room.preset,port:room.port,
    capacity:room.capacity,bots:room.bots,mods:room.mods,activation,notice};
}

export async function createPanel({rooms=DEFAULT_ROOMS,port=8787}={}){
  if(!Number.isInteger(port)||port<1024||port>65534)throw Error("Porta do painel invalida");
  const folder=path.resolve(rooms);
  const creds=panelCredentials(folder);
  if(!creds.users[ADMIN_EMAIL])throw Error("Defina a senha do painel primeiro: panel.mjs password");
  const allowed=new Set(["http://127.0.0.1:"+port,"http://localhost:"+port]);
  const hosts=new Set(["127.0.0.1:"+port,"localhost:"+port]);
  const sessions=new Map(),attempts=new Map();
  // Serialize conflicting create/edit operations to prevent duplicate port races.
  let writes=Promise.resolve();
  const queue=fn=>{
    const next=writes.then(fn);
    writes=next.catch(()=>{});
    return next;
  };
  const handler=async(req,res)=>{
    headers(res);
    try{
      if(!isLoopback(req)||!hosts.has(req.headers.host))throw httpError(403,"Acesso somente por localhost");
      const url=new URL(req.url,"http://127.0.0.1");
      if(url.search||url.hash)throw httpError(400,"Parametros nao permitidos");
      if(req.method==="GET"&&url.pathname==="/")return filePage(res,"index.html","text/html; charset=utf-8");
      if(req.method==="GET"&&url.pathname==="/panel.css")return filePage(res,"panel.css","text/css; charset=utf-8");
      if(req.method==="GET"&&url.pathname==="/panel.js")return filePage(res,"panel.js","text/javascript; charset=utf-8");
      const session=sessionFromCookie(req,sessions);
      if(req.method==="GET"&&url.pathname==="/api/session")
        return send(res,200,{authenticated:!!session,csrf:session?.csrf||null});
      if(req.method==="POST"){
        requireValidOrigin(req,allowed);
        if(!String(req.headers["content-type"]||"").toLowerCase().startsWith("application/json"))
          throw httpError(415,"Envie JSON");
      }
      if(req.method==="POST"&&url.pathname==="/api/login"){
        const address=req.socket.remoteAddress;
        const now=Date.now(),record=attempts.get(address);
        const current=record&&now-record.start<600000?record:{start:now,count:0};
        if(current.count>=10)throw httpError(429,"Limite de tentativas. Tente depois.");
        const body=await readJson(req);
        checkPayload(body,["password"]);
        if(typeof body.password!=="string"||body.password.length>128){
          current.count++;attempts.set(address,current);
          throw httpError(401,"Senha incorreta");
        }
        const good=await creds.verify(ADMIN_EMAIL,body.password);
        if(!good){
          current.count++;attempts.set(address,current);
          throw httpError(401,"Senha incorreta");
        }
        attempts.delete(address);
        if(sessions.size>=MAX_SESSIONS)sessions.delete(sessions.keys().next().value);
        const sid=hex(),csrf=hex();
        sessions.set(sid,{csrf,expires:now+SESSION_TTL});
        res.setHeader("Set-Cookie","mooio_admin="+sid+"; HttpOnly; SameSite=Strict; Path=/; Max-Age=7200");
        return send(res,200,{authenticated:true,csrf});
      }
      if(!session)throw httpError(401,"Autenticacao necessaria");
      if(req.method==="POST"&&url.pathname==="/api/logout"){
        formRequest(req,allowed,session);
        sessions.delete(session.sid);
        res.setHeader("Set-Cookie","mooio_admin=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0");
        return send(res,200,{ok:true});
      }
      if(req.method==="GET"&&url.pathname==="/api/overview")
        return send(res,200,await safeOverview(folder));
      if(req.method==="GET"&&url.pathname==="/api/mods")
        return send(res,200,{mods:catalog()});
      if(req.method==="POST"){
        formRequest(req,allowed,session);
        if(url.pathname==="/api/rooms"){
          const body=await readJson(req);
          return send(res,201,await queue(()=>mutateRoom(folder,body.id,body,{create:true})));
        }
        const match=safeIdFromPathname(url.pathname);
        if(match?.action==="start"){
          if(!fs.existsSync(path.join(folder,match.id+".json")))throw httpError(404,"Sala nao encontrada");
          return send(res,200,{result:await requestRoomStart(folder,match.id)});
        }
        if(match?.action==="restart"){
          // Fail-closed: cannot restart a room that no longer exists.
          if(!fs.existsSync(path.join(folder,match.id+".json")))throw httpError(404,"Sala nao encontrada");
          return send(res,200,{result:await requestRoomRestart(folder,match.id)});
        }
      }
      if(req.method==="PUT"){
        formRequest(req,allowed,session);
        const match=safeIdFromPathname(url.pathname);
        if(match&&!match.action){
          const body=await readJson(req);
          return send(res,200,await queue(()=>mutateRoom(folder,match.id,body)));
        }
      }
      throw httpError(404,"Rota nao encontrada");
    }catch(error){
      if(res.writableEnded||res.destroyed)return;
      const status=error.status||(/(invalido|invalid|nao confere|mods|name|capacity|bots|preset|schemaVersion|Mod|port)/i.test(error.message)?400:500);
      send(res,status,{error:status===500?"Falha na operacao. Consulte logs locais.":String(error.message).slice(0,250)});
    }
  };
  const server=http.createServer((req,res)=>{void handler(req,res);});
  server.on("upgrade",(_req,socket)=>socket.destroy());
  await new Promise((resolve,reject)=>{
    server.once("error",reject);
    server.listen(port,"127.0.0.1",()=>{server.removeListener("error",reject);resolve();});
  });
  return {port,host:"127.0.0.1",server,close:()=>new Promise(resolve=>server.close(resolve))};
}
