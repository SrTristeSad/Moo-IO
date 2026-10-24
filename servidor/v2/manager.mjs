#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Headless VPS controls. Does not start a public admin endpoint.
import path from "node:path";
import { RoomSupervisor, discoverRooms, checkRooms, DEFAULT_ROOMS } from "./core/supervisor.mjs";
import { scanRooms, statusText, statusKey } from "./core/monitor.mjs";
import { startControlServer, requestRoomRestart, requestRoomStart, requestRoomStop, requestRoomEvents, requestRoomPlayers, requestPlayerKick } from "./core/control.mjs";

const args=process.argv.slice(2);
const cmd=args.shift()||"help";
const targetId=["restart","start-room","stop-room","events","players","kick"].includes(cmd)?args.shift():null;
const kickId=cmd==="kick"?args.shift():null;
function parseArgs(args){
  const flags={rooms:DEFAULT_ROOMS,json:false,interval:15,intervalPassed:false};
  const seen=new Set();
  while(args.length){
    const option=args.shift();
    if(!["--rooms","--json","--interval"].includes(option)||seen.has(option))
      throw Error("Opcao desconhecida ou repetida: "+option);
    seen.add(option);
    if(option==="--json"){flags.json=true;continue;}
    const value=args.shift();
    if(!value||value.startsWith("--"))throw Error("Use "+option+" com um valor");
    if(option==="--rooms")flags.rooms=path.resolve(value);
    else{
      flags.intervalPassed=true;
      flags.interval=Number(value);
      if(!Number.isInteger(flags.interval)||flags.interval<3||flags.interval>3600)
        throw Error("Intervalo do monitor: 3 a 3600 segundos");
    }
  }
  return flags;
}
async function main(){
  const flags=parseArgs(args);
  if(cmd==="help"){
    if(flags.json||flags.interval!==15||flags.rooms!==DEFAULT_ROOMS)throw Error("help nao aceita opcoes");
    console.log([
      "Moo-IO Servidor Privado V2 - administrador local de salas",
      "  node servidor/v2/manager.mjs check [--rooms pasta]",
      "  node servidor/v2/manager.mjs status [--rooms pasta] [--json]",
      "  node servidor/v2/manager.mjs health [--rooms pasta] [--json]",
      "  node servidor/v2/manager.mjs watch [--rooms pasta] [--interval 15]",
      "  node servidor/v2/manager.mjs start [--rooms pasta]",
      "  node servidor/v2/manager.mjs restart ID [--rooms pasta]",
      "  node servidor/v2/manager.mjs start-room ID [--rooms pasta]",
      "  node servidor/v2/manager.mjs stop-room ID [--rooms pasta]",
      "  node servidor/v2/manager.mjs events ID [--rooms pasta]",
      "  node servidor/v2/manager.mjs players ID [--rooms pasta]",
      "  node servidor/v2/manager.mjs kick ID PLAYER_ID [--rooms pasta]",
      "status: jogadores por sala; --json: relatorio para scripts.",
      "health: sai com codigo 1 se alguma sala estiver offline.",
      "watch: mostra alteracoes de jogadores/disponibilidade.",
      "start: inicia salas isoladas e reinicia apos falhas e travamentos.",
      "restart: valida os mods e recarrega somente a sala indicada, sem reiniciar vizinhas.",
      "start-room: inicia uma nova sala criada no disco, sem interromper as demais.",
      "stop-room: para uma sala sem auto-reinicio, sem parar as vizinhas.",
      "events: consulta eventos operacionais recentes (sem stdout e sem segredos).",
      "players: jogadores online por sessao, sem IP/email.",
      "kick: desconecta jogador especifico, protege contas de equipe.",
      "Administracao local; NAO disponibilize estes comandos como API publica."
    ].join("\n"));
    return;
  }
  if(!["check","status","health","watch","start","restart","start-room","stop-room","events","players","kick"].includes(cmd))throw Error("Comando desconhecido: "+cmd);
  if(flags.json&&!["status","health"].includes(cmd))throw Error("--json somente para status/health");
  if(flags.intervalPassed&&cmd!=="watch")throw Error("--interval somente para watch");
  if(["restart","start-room","stop-room","events","players","kick"].includes(cmd)){
    if(flags.json||flags.intervalPassed)throw Error("Comando aceita somente --rooms");
    if(!targetId)throw Error("Informe o ID da sala");
    if(args.length)throw Error("Argumentos desconhecidos");
    const actions={
      restart:requestRoomRestart,
      "start-room":requestRoomStart,
      "stop-room":requestRoomStop,
      events:requestRoomEvents,
      players:requestRoomPlayers,
      kick:requestPlayerKick
    };
    const result=await actions[cmd](flags.rooms,targetId,...(cmd==="kick"?[kickId]:[]));
    if(cmd==="events"||cmd==="players")console.log(JSON.stringify(result,null,2));
    else console.log("Sala "+result.id+": "+result.status+". Outras salas permanecem ativas.");
    return;
  }
  const rooms=await checkRooms(discoverRooms(flags.rooms));
  if(cmd==="check"){
    for(const {id,room} of rooms)console.log("OK "+id+" | "+room.name+" | "+room.host+":"+room.port+" | jogadores "+room.capacity+" | mods "+room.mods.length);
    console.log("Configuracao de "+rooms.length+" sala(s) validada. Nenhum processo iniciado.");
  }else if(cmd==="status"||cmd==="health"){
    const report=await scanRooms(rooms);
    if(flags.json)console.log(JSON.stringify(report));
    else if(cmd==="status")console.log(statusText(report));
    else{
      console.log(statusText(report));
      console.log(report.healthy?"SAUDAVEL: todas as salas online.":"FALHA: "+report.totals.offline+" sala(s) sem resposta.");
    }
    if(cmd==="health"&&!report.healthy)process.exitCode=1;
  }else if(cmd==="watch"){
    let ending=false,previous=null,wake=null;
    const stop=()=>{ending=true;wake?.();};
    process.on("SIGINT",stop);
    process.on("SIGTERM",stop);
    console.log("Monitor local V2 iniciado ("+flags.interval+"s). Ctrl+C para encerrar.");
    try{
      while(!ending){
        const report=await scanRooms(rooms);
        const key=statusKey(report);
        if(previous!==key){
          console.log("["+report.timestamp+"] "+report.totals.online+"/"+report.totals.rooms+
            " salas online; jogadores "+report.totals.players+"/"+report.totals.capacity);
          console.log(statusText(report));
          previous=key;
        }
        if(ending)break;
        await new Promise(resolve=>{
          const timer=setTimeout(resolve,flags.interval*1000);
          wake=()=>{clearTimeout(timer);resolve();};
        });
        wake=null;
      }
    }finally{
      process.removeListener("SIGINT",stop);
      process.removeListener("SIGTERM",stop);
    }
  }else{
    const supervisor=new RoomSupervisor(rooms);
    supervisor.start();
    let control;
    try{
      control=await startControlServer(flags.rooms,{onRestart:id=>supervisor.restartRoom(id),onStart:id=>supervisor.startRoom(id),
        onStop:id=>supervisor.stopRoom(id),onEvents:id=>supervisor.roomEvents(id),
        onPlayers:id=>supervisor.listPlayers(id),onKick:(id,playerId)=>supervisor.kickPlayer(id,playerId)});
    }catch(error){
      await supervisor.stop();
      throw error;
    }
    let terminating=false;
    const shutdown=()=>{
      if(terminating)return;
      terminating=true;
      void Promise.all([supervisor.stop(),control.close()]).then(()=>{process.exitCode=0;}).catch(error=>{
        console.error("Erro ao parar salas: "+error.message);
        process.exitCode=1;
      });
    };
    process.once("SIGINT",shutdown);
    process.once("SIGTERM",shutdown);
    console.log("Controlador V2 ativo; "+rooms.length+" sala(s). Controle local privado: restart ID; Ctrl+C para encerrar.");
  }
}
main().catch(error=>{console.error("Erro no controlador V2: "+error.message);process.exitCode=1;});
