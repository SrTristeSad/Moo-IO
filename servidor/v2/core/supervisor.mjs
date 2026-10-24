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
  constructor(entries,{
    logger=console.log,clock=()=>Date.now(),probe=probeRoom,
    watchdogIntervalMs=15000,startupGraceMs=20000,watchdogFailures=3,
    terminateProcess=terminate
  }={}){
    this.entries=entries;
    this.probe=probe;
    this.watchdogIntervalMs=watchdogIntervalMs;
    this.startupGraceMs=startupGraceMs;
    this.watchdogFailures=watchdogFailures;
    this.terminateProcess=terminateProcess;
    this.watchdogTimer=null;
    this.polling=false;
    this.logger=logger;
    this.clock=clock;
    this.states=new Map(entries.map(entry=>[entry.id,{
      entry,child:null,crashes:[],timer:null,forceTimer:null,
      misses:0,startedAt:0,restartRequested:false,disabled:false,lastExit:null,
      manualRestart:null,stopping:false,events:[]
    }]));
    this.closing=false;
    this.started=false;
  }
  // Deliberately expose only structured supervisor lifecycle events. Child
  // stdout/stderr may contain tokens and must NEVER enter the admin UI.
  recordEvent(state,kind){
    if(!["started","restarting","stopped","crashed","watchdog","disabled"].includes(kind))
      throw Error("Evento operacional invalido");
    state.events??=[];
    state.events.push({at:new Date(this.clock()).toISOString(),kind});
    if(state.events.length>40)state.events.splice(0,state.events.length-40);
  }
  roomEvents(id){
    const state=this.states.get(id);
    if(!state)throw Error("Sala nao encontrada: "+id);
    return {id,onlineProcess:!!state.child,stopped:!!state.disabled,
      events:(state.events||[]).slice(-20).map(event=>({...event}))};
  }
  async stopRoom(id){
    if(this.closing||!this.started)throw Error("Supervisor nao esta ativo");
    const state=this.states.get(id);
    if(!state)throw Error("Sala nao encontrada: "+id);
    if(state.stopping||state.manualRestart||state.restartRequested)
      throw Error("Sala ocupada com reinicio/encerramento: "+id);
    if(state.disabled&&!state.child)return {id,status:"already-stopped"};
    // Mark disabled BEFORE signals are sent, so the child's exit handler
    // cannot schedule an automatic restart.
    state.disabled=true;
    state.stopping=true;
    if(state.timer){clearTimeout(state.timer);state.timer=null;}
    if(state.forceTimer){clearTimeout(state.forceTimer);state.forceTimer=null;}
    state.misses=0;
    const child=state.child;
    try{
      if(child){
        this.terminateProcess(child);
        if(!await waitForExit(child,3200)){
          this.terminateProcess(child,true);
          if(!await waitForExit(child,1800))
            throw Error("Processo ainda nao encerrou; verifique a sala "+id);
        }
      }
      this.recordEvent(state,"stopped");
      this.logger("["+id+"] Sala parada pelo administrador (sem auto-reinicio).");
      return {id,status:"stopped"};
    }finally{state.stopping=false;}
  }
  // Start a newly created room while all existing game processes remain alive.
  // Re-read the real directory, validate ALL ports/IDs, then mutate state only
  // after its mods and network configuration have passed validation.
  async startRoom(id){
    if(this.closing||!this.started)throw Error("Supervisor nao esta ativo");
    if(!/^[a-z][a-z0-9_-]{0,47}$/.test(id))throw Error("ID da sala invalido");
    if(this.pendingStarts?.has(id))throw Error("Inicializacao ja em andamento: "+id);
    this.pendingStarts??=new Set();
    this.pendingStarts.add(id);
    try{
      const roomsDir=path.dirname(this.entries[0]?.file||DEFAULT_ROOMS);
      const found=discoverRooms(roomsDir);
      const entry=found.find(item=>item.id===id);
      if(!entry)throw Error("Sala nao encontrada no disco: "+id);
      await planRoom(entry.room);
      // Existing rooms may have unsaved changes, but listening ports are
      // always compared to the active configuration instead of stale disk.
      for(const state of this.states.values()){
        if(state.entry.id!==id&&state.entry.room.port===entry.room.port)
          throw Error("Porta em uso pela sala "+state.entry.id);
      }
      const current=this.states.get(id);
      if(current){
        if(current.child||current.manualRestart||current.timer||current.restartRequested||current.stopping)
          throw Error("Sala ja iniciada ou reiniciando: "+id);
        if(current.entry.room.host!==entry.room.host||
           current.entry.room.port!==entry.room.port||
           current.entry.room.network!==entry.room.network)
          throw Error("Host, rede ou porta mudaram; reinicie o controlador de forma planejada.");
        current.entry=entry;
        current.crashes=[];
        current.disabled=false;
        this.launch(current);
        return {id,status:"starting"};
      }
      if(this.states.size>=MAX_ROOMS)throw Error("Limite de "+MAX_ROOMS+" salas por controlador");
      const state={entry,child:null,crashes:[],timer:null,forceTimer:null,
        misses:0,startedAt:0,restartRequested:false,disabled:false,lastExit:null,
        manualRestart:null,stopping:false,events:[]};
      this.states.set(id,state);
      this.entries.push(entry);
      try{this.launch(state);}catch(error){
        this.states.delete(id);
        this.entries=this.entries.filter(item=>item.id!==id);
        throw error;
      }
      this.logger("["+id+"] Nova sala adicionada sem interromper outras salas.");
      return {id,status:"starting"};
    }finally{this.pendingStarts.delete(id);}
  }
  async restartRoom(id){
    if(this.closing||!this.started)throw Error("Supervisor nao esta ativo");
    const state=this.states.get(id);
    if(!state)throw Error("Sala nao encontrada: "+id);
    if(state.manualRestart||state.restartRequested||state.stopping)throw Error("Sala ja esta reiniciando: "+id);

    // Parse and validate the current on-disk config before touching the live
    // worker. A broken mod must leave the old match and other rooms untouched.
    const nextRoom=readRoom(state.entry.file);
    await planRoom(nextRoom);
    const current=state.entry.room;
    if(nextRoom.host!==current.host||nextRoom.port!==current.port||
       nextRoom.network!==current.network)
      throw Error("Host, porta ou rede alterados: requer reinicio planejado do controlador e revisao do gateway.");

    state.entry={...state.entry,room:nextRoom};
    state.disabled=false;
    state.crashes=[];
    if(state.timer){clearTimeout(state.timer);state.timer=null;}
    const child=state.child;
    if(!child){
      this.launch(state);
      return {id,status:"started"};
    }
    return await new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{
        if(state.manualRestart?.timer===timer){
          state.manualRestart=null;
          reject(Error("Sala nao encerrou a tempo; confira o supervisor."));
        }
      },12000);
      timer.unref?.();
      state.manualRestart={resolve,reject,timer};
      this.logger("["+id+"] Reinicio solicitado pelo administrador.");
      this.recordEvent(state,"restarting");
      try{this.terminateProcess(child);}
      catch(error){clearTimeout(timer);state.manualRestart=null;reject(error);return;}
      state.forceTimer=setTimeout(()=>{
        state.forceTimer=null;
        if(!this.closing&&state.child===child&&child.exitCode===null&&child.signalCode===null)
          this.terminateProcess(child,true);
      },5000);
      state.forceTimer.unref?.();
    });
  }
  start(){
    if(this.closing||this.started)throw Error("Supervisor nao pode iniciar duas vezes");
    this.started=true;
    for(const state of this.states.values())this.launch(state);
    // Probe independently so a game that hangs with its process still running
    // is recycled; failed rooms never stop their healthy neighbors.
    this.watchdogTimer=setInterval(()=>void this.pollHealth(),this.watchdogIntervalMs);
  }
  async pollHealth(){
    if(this.polling||this.closing)return;
    this.polling=true;
    try{
      await Promise.all([...this.states.values()].map(async state=>{
        const child=state.child;
        if(!child||state.disabled||state.restartRequested||state.manualRestart||
           this.clock()-state.startedAt<this.startupGraceMs)return;
        let result;
        try{result=await this.probe(state.entry,{timeout:1200});}
        catch(error){result={online:false,reason:error.message};}
        // Old probe results cannot affect a replacement worker.
        if(this.closing||state.child!==child||state.restartRequested)return;
        if(result.online){state.misses=0;return;}
        state.misses++;
        if(state.misses<this.watchdogFailures)return;
        state.misses=0;
        state.restartRequested=true;
        this.recordEvent(state,"watchdog");
        this.logger("["+state.entry.id+"] Watchdog: "+
          this.watchdogFailures+" verificacoes sem resposta; reiniciando apenas esta sala.");
        this.terminateProcess(child);
        // An event loop blocked in native code may ignore SIGTERM. Forcefully
        // recycle that process after a grace period without affecting neighbors.
        state.forceTimer=setTimeout(()=>{
          state.forceTimer=null;
          if(!this.closing&&state.child===child&&child.exitCode===null&&child.signalCode===null)
            this.terminateProcess(child,true);
        },5000);
        state.forceTimer.unref?.();
      }));
    }finally{this.polling=false;}
  }
  launch(state){
    if(this.closing||state.disabled)return;
    const {id,file,room}=state.entry;
    this.logger("Iniciando "+id+" ("+room.host+":"+room.port+", mods="+room.mods.length+")");
    const child=spawn(process.execPath,[cli,"start","--file",file],{
      cwd:root,stdio:["ignore","pipe","pipe"],windowsHide:true
    });
    state.child=child;
    this.recordEvent(state,"started");
    state.startedAt=this.clock();
    state.misses=0;
    state.restartRequested=false;
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
      if(state.forceTimer){clearTimeout(state.forceTimer);state.forceTimer=null;}
      state.misses=0;
      state.restartRequested=false;
      state.lastExit={code,signal,at:this.clock()};
      const manual=state.manualRestart;
      if(manual){
        state.manualRestart=null;
        clearTimeout(manual.timer);
        if(this.closing){manual.reject(Error("Supervisor sendo encerrado"));return;}
        this.logger("["+state.entry.id+"] Aplicando configuracao validada e reiniciando esta sala.");
        try{
          this.launch(state);
          manual.resolve({id:state.entry.id,status:"restarted"});
        }catch(error){manual.reject(error);}
        return;
      }
      if(this.closing||state.disabled)return;
      this.recordEvent(state,"crashed");
      const now=this.clock();
      state.crashes=state.crashes.filter(at=>now-at<CRASH_WINDOW_MS);
      state.crashes.push(now);
      if(state.crashes.length>MAX_CRASHES){
        state.disabled=true;
        this.recordEvent(state,"disabled");
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
      if(state.manualRestart){
        clearTimeout(state.manualRestart.timer);
        state.manualRestart.reject(Error("Supervisor sendo encerrado"));
        state.manualRestart=null;
      }
    }
    if(this.watchdogTimer){clearInterval(this.watchdogTimer);this.watchdogTimer=null;}
    for(const state of this.states.values()){
      if(state.timer){clearTimeout(state.timer);state.timer=null;}
      if(state.forceTimer){clearTimeout(state.forceTimer);state.forceTimer=null;}
    }
    const active=[...this.states.values()].map(s=>s.child).filter(Boolean);
    for(const child of active)this.terminateProcess(child);
    const closed=await Promise.all(active.map(child=>waitForExit(child,3500)));
    for(let i=0;i<active.length;i++)if(!closed[i])this.terminateProcess(active[i],true);
    this.logger("Supervisor finalizado; "+active.length+" sala(s) encerrada(s).");
  }
}
