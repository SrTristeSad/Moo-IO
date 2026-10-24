#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// VPS preparation: never opens a public socket, edits firewall, or runs sudo.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { newRoom, createRoom } from "./core/config.mjs";
import { checkRooms, discoverRooms, DEFAULT_ROOMS } from "./core/supervisor.mjs";

export const ROOT=fileURLToPath(new URL("../../",import.meta.url));
const DEFAULT_NAME="Minha sala Moo-IO";

export function quoteSystemd(input){
  const p=String(input);
  if(!path.posix.isAbsolute(p)||/[\x00-\x1f\x7f]/.test(p))throw Error("Caminho absoluto sem caracteres de controle obrigatorio");
  return '"' + p.replace(/\\/g,"\\\\").replace(/"/g,'\\"').replace(/%/g,"%%").replace(/\$/g,()=> String.fromCharCode(36,36)) + '"';
}
export function unitContent({node=process.execPath,root=ROOT,rooms=DEFAULT_ROOMS}={}){
  const exe=quoteSystemd(node),script=quoteSystemd(path.posix.join(root,"servidor/v2/manager.mjs"));
  const work=quoteSystemd(root),config=quoteSystemd(path.posix.resolve(rooms));
  return [
    "# Gerado pela V2 Moo-IO; acesso de rede somente privado.",
    "[Unit]","Description=Moo-IO V2 private server rooms","After=network.target",
    "StartLimitIntervalSec=120","StartLimitBurst=5",
    "","[Service]","Type=simple","WorkingDirectory="+work,
    "ExecStartPre="+exe+" "+script+" check --rooms "+config,
    "ExecStart="+exe+" "+script+" start --rooms "+config,
    "Restart=on-failure","RestartSec=5","KillMode=control-group","TimeoutStopSec=15",
    "UMask=0077","NoNewPrivileges=true","Environment=NODE_ENV=production",
    "","[Install]","WantedBy=default.target",""
  ].join("\n");
}
export function panelUnitContent({node=process.execPath,root=ROOT,rooms=DEFAULT_ROOMS,port=8787}={}){
  if(!Number.isInteger(port)||port<1024||port>65534)throw Error("Porta do painel invalida");
  const exe=quoteSystemd(node),script=quoteSystemd(path.posix.join(root,"servidor/v2/panel.mjs"));
  const folder=quoteSystemd(path.posix.resolve(rooms)),work=quoteSystemd(root);
  return [
    "# Moo-IO V2: painel restrito a localhost. NUNCA adicionar ao Caddy.",
    "[Unit]","Description=Moo-IO V2 private admin panel","After=network.target mooio-v2.service",
    "StartLimitIntervalSec=120","StartLimitBurst=5",
    "","[Service]","Type=simple","WorkingDirectory="+work,
    "ExecStartPre="+exe+" "+script+" check --rooms "+folder,
    "ExecStart="+exe+" "+script+" serve --rooms "+folder+" --port "+port,
    "Restart=on-failure","RestartSec=5","KillMode=control-group","TimeoutStopSec=15",
    "UMask=0077","NoNewPrivileges=true","Environment=NODE_ENV=production",
    "","[Install]","WantedBy=default.target",""
  ].join("\n");
}
function argsParse(args){
  const flags={};
  for(let i=0;i<args.length;i++){
    const key=args[i];
    if(!["--rooms","--name","--port","--skip-install"].includes(key)||Object.hasOwn(flags,key))throw Error("Opcao invalida ou repetida: "+key);
    if(key==="--skip-install"){flags.skipInstall=true;continue;}
    const value=args[++i];
    if(!value||value.startsWith("--"))throw Error("Valor ausente para "+key);
    flags[key.slice(2)]=value;
  }
  return flags;
}
function checkNode(){
  if(Number(process.versions.node.split(".")[0])<22)throw Error("Node.js 22+ necessario. Encontrado: "+process.versions.node);
}
function dependenciesPresent(){
  return fs.existsSync(path.join(ROOT,"windows/server/node_modules/express/package.json")) &&
    fs.existsSync(path.join(ROOT,"windows/server/node_modules/ws/package.json"));
}
function installDependencies(){
  console.log("Instalando dependencias do motor windows/server...");
  const cmd=process.platform==="win32"?"npm.cmd":"npm";
  const result=spawnSync(cmd,["install","--no-audit","--no-fund","--prefix",path.join(ROOT,"windows/server")],{
    cwd:ROOT,stdio:"inherit",shell:process.platform==="win32"
  });
  if(result.error)throw Error("Falha ao iniciar npm: "+result.error.message);
  if(result.status!==0)throw Error("npm install falhou (exit "+result.status+")");
  if(!dependenciesPresent())throw Error("npm terminou sem instalar express/ws");
}
export async function setup({rooms=DEFAULT_ROOMS,name=DEFAULT_NAME,port=8080,skipInstall=false}={}){
  checkNode();
  if(!Number.isInteger(port)||port<1024||port>65534)throw Error("Porta de 1024 a 65534 obrigatoria");
  if(typeof name!=="string"||!name.trim()||name.length>60)throw Error("Nome de sala invalido");
  const directory=path.resolve(rooms);
  fs.mkdirSync(directory,{recursive:true,mode:0o700});
  const stat=fs.lstatSync(directory);
  if(!stat.isDirectory()||stat.isSymbolicLink())throw Error("Pasta de salas deve ser um diretorio real, sem symlink");
  if(!dependenciesPresent()){
    if(skipInstall)throw Error("Dependencias faltando; instale via npm install --prefix windows/server");
    installDependencies();
  }
  const existing=fs.readdirSync(directory).filter(x=>x.endsWith(".json"));
  let created=false;
  if(!existing.length){
    createRoom(path.join(directory,"principal.json"),newRoom({name,port,host:"127.0.0.1",network:"lan"}));
    created=true;
  }
  const found=await checkRooms(discoverRooms(directory));
  return {directory,created,rooms:found.map(({id,room})=>({
    id,name:room.name,host:room.host,port:room.port,capacity:room.capacity,mods:room.mods.length
  }))};
}
export async function doctor({rooms=DEFAULT_ROOMS}={}){
  checkNode();
  if(!dependenciesPresent())throw Error("Dependencias ausentes: execute node servidor/v2/vps.mjs setup");
  const found=await checkRooms(discoverRooms(path.resolve(rooms)));
  return {node:process.versions.node,rooms:found.map(({id,room})=>({
    id,host:room.host,port:room.port,mods:room.mods.length,capacity:room.capacity
  })),warnings:found.filter(({room})=>room.host!=="127.0.0.1").map(({id})=>
    "Sala "+id+" nao usa loopback; confira VPN/firewall")};
}
async function main(){
  const [command="help",...args]=process.argv.slice(2);
  if(command==="help"){
    if(args.length)throw Error("help nao recebe argumentos");
    console.log("Moo-IO V2 - preparar VPS Linux sem abrir portas publicas:");
    console.log("  node servidor/v2/vps.mjs setup [--rooms pasta] [--name nome] [--port 8080]");
    console.log("  node servidor/v2/vps.mjs doctor [--rooms pasta]");
    console.log("  node servidor/v2/vps.mjs unit [--rooms pasta]");
    console.log("  node servidor/v2/vps.mjs panel-unit [--rooms pasta] [--port 8787]");
    console.log("  bash servidor/v2/deploy/install-ubuntu.sh  # instalar servico systemd --user");
    return;
  }
  if(!["setup","doctor","unit","panel-unit"].includes(command))throw Error("Comando desconhecido: "+command);
  const opts=argsParse(args);
  if(!["setup","panel-unit"].includes(command)&&(opts.name||opts.port||opts.skipInstall))throw Error("Opcoes de setup nao aceitas em "+command);
  const rooms=opts.rooms?path.resolve(opts.rooms):DEFAULT_ROOMS;
  if(command==="setup"){
    const out=await setup({rooms,name:opts.name||DEFAULT_NAME,port:opts.port===undefined?8080:Number(opts.port),skipInstall:Boolean(opts.skipInstall)});
    console.log(out.created?"Sala tradicional inicial criada.":"Salas existentes preservadas.");
    for(const room of out.rooms)console.log("OK "+room.id+" "+room.host+":"+room.port+" ("+room.capacity+" jogadores, "+room.mods+" mods)");
    console.log("Validacao concluida: "+out.rooms.length+" sala(s).");
  }else if(command==="doctor"){
    const result=await doctor({rooms});
    console.log("Node "+result.node+"; dependencias instaladas; "+result.rooms.length+" salas validadas.");
    for(const room of result.rooms)console.log("OK "+room.id+" "+room.host+":"+room.port+" mods="+room.mods+" capacidade="+room.capacity);
    for(const warning of result.warnings)console.warn("AVISO: "+warning);
    console.log("ATENCAO: autenticacao PUBLICA e WSS ainda nao estao prontos. Nao abra portas do jogo na Internet.");
  }else if(command==="panel-unit"){
    if(opts.name||opts.skipInstall)throw Error("panel-unit aceita apenas --rooms e --port");
    process.stdout.write(panelUnitContent({rooms,port:opts.port===undefined?8787:Number(opts.port)}));
  }else{
    await checkRooms(discoverRooms(rooms));
    process.stdout.write(unitContent({rooms}));
  }
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  main().catch(error=>{console.error("Erro ao preparar VPS: "+error.message);process.exitCode=1;});
}
