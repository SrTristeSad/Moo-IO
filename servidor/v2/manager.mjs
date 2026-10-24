#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Headless VPS controls; no new HTTP API nor browser/client dependency.
import path from "node:path";
import { RoomSupervisor, discoverRooms, checkRooms, probeRoom, DEFAULT_ROOMS } from "./core/supervisor.mjs";

const args=process.argv.slice(2);
const cmd=args.shift()||"help";
async function main(){
  let dir=DEFAULT_ROOMS;
  while(args.length){
    const option=args.shift();
    if(option!=="--rooms"||!args.length)throw Error("Use --rooms diretorio");
    dir=path.resolve(args.shift());
  }
  if(cmd==="help"){
    console.log(`Moo-IO Servidor Privado V2 — controlador de salas
  node servidor/v2/manager.mjs check [--rooms pasta]
  node servidor/v2/manager.mjs status [--rooms pasta]
  node servidor/v2/manager.mjs start [--rooms pasta]

Cada arquivo <id>.json em rooms/ define uma sala; o processo da VPS
hospeda todas as salas como processos Node separados.
Configure as salas pelo cli.mjs. Nao ha painel publico de administracao.`);
    return;
  }
  if(!["check","status","start"].includes(cmd))throw Error("Comando desconhecido: "+cmd);
  const rooms=await checkRooms(discoverRooms(dir));
  if(cmd==="check"){
    for(const {id,room} of rooms)console.log("OK "+id+" | "+room.name+" | "+room.host+":"+room.port+" | jogadores "+room.capacity+" | mods "+room.mods.length);
    console.log("Configuracao de "+rooms.length+" sala(s) validada. Nenhum processo iniciado.");
  }else if(cmd==="status"){
    for(const result of await Promise.all(rooms.map(entry=>probeRoom(entry)))){
      console.log((result.online?"ONLINE ":"OFFLINE ")+result.id+" | "+result.host+":"+result.port+" | "+
        result.players+"/"+result.capacity+" jogadores | mods "+result.mods+
        (result.reason?" | "+result.reason:""));
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
