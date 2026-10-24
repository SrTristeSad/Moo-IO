#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Generate Caddy TLS/WSS vhosts for loopback-bound V2 rooms; no sudo/network changes.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { DEFAULT_ROOMS } from "./core/supervisor.mjs";
import { gatewayPlan, renderCaddyfile } from "./core/gateway.mjs";

export const DEFAULT_CADDYFILE=fileURLToPath(new URL("./deploy/Caddyfile.generated",import.meta.url));
function argsParse(args){
  const out={};
  while(args.length){
    const key=args.shift();
    if(key==="--force"){
      if(out.force)throw Error("--force repetido");
      out.force=true;
      continue;
    }
    if(!["--domain","--rooms","--output"].includes(key)||Object.hasOwn(out,key))
      throw Error("Opcao invalida ou repetida: "+key);
    const value=args.shift();
    if(!value||value.startsWith("--"))throw Error("Valor ausente para "+key);
    out[key.slice(2)]=value;
  }
  return out;
}
function usage(){
  console.log("Moo-IO V2: gateway HTTPS/WSS por dominio, usando Caddy.");
  console.log("  node servidor/v2/gateway.mjs plan --domain jogo.exemplo.com [--rooms pasta]");
  console.log("  node servidor/v2/gateway.mjs generate --domain jogo.exemplo.com [--rooms pasta]");
  console.log("  node servidor/v2/gateway.mjs write --domain jogo.exemplo.com [--output caminho] [--force]");
  console.log("Exemplo: sala 'normal' vira https://normal.jogo.exemplo.com (WSS automatico).");
  console.log("Nenhum desses comandos instala Caddy, altera firewall ou publica portas.");
}
export function writeCaddyfile(filename,content,{force=false}={}){
  const absolute=path.resolve(filename);
  fs.mkdirSync(path.dirname(absolute),{recursive:true});
  if(fs.existsSync(absolute)){
    const existing=fs.lstatSync(absolute);
    if(!force)throw Error("Caddyfile ja existe: "+absolute+" (use --force para sobrescrever)");
    if(!existing.isFile()||existing.isSymbolicLink())throw Error("Caminho de destino inseguro: "+absolute);
  }
  const temporary=absolute+"."+process.pid+".tmp";
  fs.writeFileSync(temporary,content,{flag:"wx",mode:0o600});
  try{
    if(!force&&fs.existsSync(absolute))throw Error("Caddyfile ja existe: "+absolute);
    fs.renameSync(temporary,absolute);
  }finally{if(fs.existsSync(temporary))fs.unlinkSync(temporary);}
  return absolute;
}
async function main(){
  const [cmd="help",...args]=process.argv.slice(2);
  if(cmd==="help"){if(args.length)throw Error("help nao aceita opcoes");usage();return;}
  if(!["plan","generate","write"].includes(cmd))throw Error("Comando desconhecido: "+cmd);
  const opts=argsParse(args);
  if(!opts.domain)throw Error("Informe --domain seu-dominio.com");
  if(cmd!=="write"&&(opts.output||opts.force))throw Error("--output e --force apenas para write");
  const plan=await gatewayPlan({rooms:opts.rooms?path.resolve(opts.rooms):DEFAULT_ROOMS,domain:opts.domain});
  if(cmd==="plan"){
    for(const room of plan)console.log("HTTPS https://"+room.hostname+" -> "+room.upstream+" | WSS wss://"+room.hostname+"/s/LC");
    return;
  }
  const output=renderCaddyfile(plan);
  if(cmd==="generate")process.stdout.write(output);
  else console.log("Caddyfile criado: "+writeCaddyfile(opts.output||DEFAULT_CADDYFILE,output,{force:opts.force}));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  main().catch(error=>{console.error("Erro no gateway V2: "+error.message);process.exitCode=1;});
}
