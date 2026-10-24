// SPDX-License-Identifier: AGPL-3.0-only
// VPS room supervisor. Every room is a separate OS process, without shared mods.
// Deliberately does not offer an exposed HTTP admin endpoint.
import fs from "node:fs";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { readRoom } from "./config.mjs";
import { planRoom } from "./loader.mjs";

const root=fileURLToPath(new URL("../../../",import.meta.url));
const cli=path.join(root,"servidor/v2/cli.mjs");
const ROOM_NAME=/^[a-z][a-z0-9_-]{0,47}\.json$/;
export const DEFAULT_ROOMS=path.join(root,"servidor/v2/rooms");
export const MAX_ROOMS=32;
const MAX_CRASHES=4;
const CRASH_WINDOW_MS=60000;

export function discoverRooms(directory=DEFAULT_ROOMS){
  const folder=path.resolve(directory);
  const stat=fs.lstatSync(folder);
  if(!stat.isDirectory()||stat.isSymbolicLink())throw Error("Diretorio de salas invalido: "+folder);
  const entries=fs.readdirSync(folder).filter(name=>name.endsWith(".json")).sort();
  if(!entries.length)throw Error("Nenhuma sala encontrada em "+folder+" (use cli.mjs init --file ...)");
  if(entries.length>MAX_ROOMS)throw Error("Limite do supervisor: "+MAX_ROOMS+" salas por instancia");
  const taken=new Map(),result=[];
  for(const name of entries){
    if(!ROOM_NAME.test(name))throw Error("Nome de arquivo de sala invalido: "+name);
    const filename=path.join(folder,name);
    const fileStat=fs.lstatSync(filename);
    if(fileStat.isSymbolicLink()||!fileStat.isFile())throw Error("Arquivo de sala deve ser JSON regular, nao link simbolico: "+name);
    const room=readRoom(filename);
    const other=taken.get(room.port);
    // Prevent ambiguous bind failures and accidental collisions on the same VPS.
    if(other)throw Error("Porta duplicada "+room.port+" nas salas "+other+" e "+name);
    taken.set(room.port,name);
    result.push({id:name.slice(0,-5),file:filename,room});
  }
  return result;
}

export async function checkRooms(entries){
  for(const entry of entries){
    await planRoom(entry.room);
  }
  return entries;
}

export async function probeRoom(entry,{timeout=800}={}){
  const {room}=entry,endpoint="http://"+room.host+":"+room.port;
  try{
    const [statusResponse,pingResponse]=await Promise.all([
      fetch(endpoint+"/mooio/status",{signal:AbortSignal.timeout(timeout)}),
      fetch(endpoint+"/ping",{signal:AbortSignal.timeout(timeout)})
    ]);
    if(!statusResponse.ok||!pingResponse.ok)throw Error("HTTP "+statusResponse.status+"/"+pingResponse.status);
    const [status,ping]=await Promise.all([statusResponse.json(),pingResponse.json()]);
    // Never accept an unrelated service on an occupied port as this room.
    if(status.project!=="Moo-IO"||status.v2?.room!==room.name||
       status.v2?.capacity!==room.capacity||
       JSON.stringify(status.v2?.mods)!==JSON.stringify(room.mods))
      throw Error("A porta responde, mas nao corresponde a sala configurada");
    const game=ping.servers?.find(s=>s.key==="LC");
    if(!game||ping.servers.length!==1||game.playerCapacity!==room.capacity)
      throw Error("A sala nao tem um unico mundo correto");
    return {id:entry.id,name:room.name,online:true,host:room.host,port:room.port,
      players:game.playerCount,capacity:game.playerCapacity,mods:room.mods.length,bots:room.bots};
  }catch(error){
    return {id:entry.id,name:room.name,online:false,host:room.host,port:room.port,
      players:0,capacity:room.capacity,mods:room.mods.length,bots:room.bots,reason:error.message};
  }
}

function waitForExit(child,ms){
  return new Promise(resolve=>{
    if(child.exitCode!==null||child.signalCode!==null)return resolve(true);
    let resolved=false;
    const done=ok=>{if(resolved)return;resolved=true;clearTimeout(timer);resolve(ok);};
    const timer=setTimeout(()=>done(false),ms);
    child.once("exit",()=>done(true));
  });
}
function terminate(child,force=false){
  if(child.exitCode!==null||child.signalCode!==null)return;
  if(process.platform==="win32"){
    // Windows SIGTERM cannot reliably shut down grandchildren from Node.
    spawnSync("taskkill",["/PID",String(child.pid),"/T","/F"],{stdio:"ignore"});
  }else{
    child.kill(force?"SIGKILL":"SIGTERM");
  }
}

export class RoomSupervisor{
  constructor(entries,{logger=console.log,clock=()=>Date.now()}={}){
    this.entries=entries;
    this.logger=logger;
    this.clock=clock;
    this.states=new Map(entries.map(entry=>[entry.id,{
      entry,child:null,crashes:[],timer:null,disabled:false,lastExit:null
    }]));
    this.closing=false;
  }
  start(){
    if(this.closing)throw Error("Supervisor em encerramento");
    for(const state of this.states.values())this.launch(state);
  }
  launch(state){
    if(this.closing||state.disabled)return;
    const {id,file,room}=state.entry;
    this.logger("Iniciando "+id+" ("+room.host+":"+room.port+", mods="+room.mods.length+")");
    const child=spawn(process.execPath,[cli,"start","--file",file],{
      cwd:root,stdio:["ignore","pipe","pipe"],windowsHide:true
    });
    state.child=child;
    const report=(tag,data)=>{
      const chunks=String(data).replace(/\r/g,"").split("\n").filter(Boolean);
      for(const chunk of chunks)this.logger("["+id+" "+tag+"] "+chunk);
    };
    child.stdout?.on("data",data=>report("out",data));
    child.stderr?.on("data",data=>report("err",data));
    child.on("error",error=>report("error",error.message));
    child.once("exit",(code,signal)=>{
      if(state.child!==child)return;
      state.child=null;
      state.lastExit={code,signal,at:this.clock()};
      if(this.closing)return;
      const now=this.clock();
      state.crashes=state.crashes.filter(at=>now-at<CRASH_WINDOW_MS);
      state.crashes.push(now);
      if(state.crashes.length>MAX_CRASHES){
        state.disabled=true;
        this.logger("["+id+"] Desativada apos muitas falhas; verifique logs/portas/mods.");
        return;
      }
      const pause=Math.min(30000,1000*2**(state.crashes.length-1));
      this.logger("["+id+"] Processo terminou ("+(signal||code)+"), reiniciando em "+pause+" ms");
      state.timer=setTimeout(()=>{state.timer=null;this.launch(state)},pause);
    });
  }
  async stop(){
    if(this.closing)return;
    this.closing=true;
    for(const state of this.states.values()){
      if(state.timer){clearTimeout(state.timer);state.timer=null;}
    }
    const active=[...this.states.values()].map(s=>s.child).filter(Boolean);
    for(const child of active)terminate(child);
    const closed=await Promise.all(active.map(child=>waitForExit(child,3500)));
    for(let i=0;i<active.length;i++)if(!closed[i])terminate(active[i],true);
    this.logger("Supervisor finalizado; "+active.length+" sala(s) encerrada(s).");
  }
}
