#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Headless VPS controls. Does not start a public admin endpoint.
import path from "node:path";
import { RoomSupervisor, discoverRooms, checkRooms, DEFAULT_ROOMS } from "./core/supervisor.mjs";
import { scanRooms, statusText, statusKey } from "./core/monitor.mjs";

const args=process.argv.slice(2);
const cmd=args.shift()||"help";
function parseArgs(args){
  const flags={rooms:DEFAULT_ROOMS,json:false,interval:15};
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
      "status: jogadores por sala; --json: relatorio para scripts.",
      "health: sai com codigo 1 se alguma sala estiver offline.",
      "watch: mostra alteracoes de jogadores/disponibilidade.",
      "start: inicia salas isoladas e reinicia apos falhas e travamentos.",
      "Administracao local; NAO disponibilize estes comandos como API publica."
    ].join("\n"));
    return;
  }
  if(!["check","status","health","watch","start"].includes(cmd))throw Error("Comando desconhecido: "+cmd);
  if(flags.json&&!["status","health"].includes(cmd))throw Error("--json somente para status/health");
  if(flags.interval!==15&&cmd!=="watch")throw Error("--interval somente para watch");
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
    let terminating=false;
    const shutdown=()=>{
      if(terminating)return;
      terminating=true;
      void supervisor.stop().then(()=>{process.exitCode=0;}).catch(error=>{
        console.error("Erro ao parar salas: "+error.message);
        process.exitCode=1;
      });
    };
    process.once("SIGINT",shutdown);
    process.once("SIGTERM",shutdown);
    supervisor.start();
    console.log("Controlador V2 ativo; "+rooms.length+" sala(s). Use Ctrl+C para encerrar.");
  }
}
main().catch(error=>{console.error("Erro no controlador V2: "+error.message);process.exitCode=1;});
