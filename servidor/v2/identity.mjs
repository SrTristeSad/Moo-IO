#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Shared browser login hub for all V2 rooms on this VPS.
import path from "node:path";
import fs from "node:fs";
import {fileURLToPath} from "node:url";
import {createIdentityService,publicOrigin} from "./core/identity.mjs";
import {DEFAULT_ROOMS} from "./core/supervisor.mjs";

async function main(){
  const [action="help",...args]=process.argv.slice(2);
  if(action==="help"){
    console.log("Moo-IO V2 -- browser-hosted identity");
    console.log("  node servidor/v2/identity.mjs configure --origin https://auth.jogo.example.com [--rooms pasta]");
    console.log("  node servidor/v2/identity.mjs check [--rooms pasta]");
    console.log("  node servidor/v2/identity.mjs serve [--origin https://auth.jogo.example.com] [--rooms pasta] [--port 8788]");
    console.log("Run under HTTPS Caddy proxy; listens ONLY at 127.0.0.1. Never expose /internal.");
    return;
  }
  if(!["configure","check","serve"].includes(action))throw Error("Comando invalido");
  const flags={rooms:DEFAULT_ROOMS,port:8788,origin:null};
  const seen=new Set();
  while(args.length){
    const key=args.shift(),value=args.shift();
    if(!["--rooms","--port","--origin"].includes(key)||seen.has(key)||!value||value.startsWith("--"))
      throw Error("Opcao invalida: "+key);
    seen.add(key);
    if(key==="--rooms")flags.rooms=path.resolve(value);
    if(key==="--origin")flags.origin=value;
    if(key==="--port")flags.port=Number(value);
  }
  const configDir=path.join(flags.rooms,".identity");
  const configFile=path.join(configDir,"origin.json");
  if(action==="configure"){
    if(!flags.origin||!flags.origin.startsWith("https://"))throw Error("Configuracao exige HTTPS publico");
    const origin=publicOrigin(flags.origin);
    fs.mkdirSync(configDir,{recursive:true,mode:0o700});
    const stat=fs.lstatSync(configDir);
    if(stat.isSymbolicLink()||(process.platform!=="win32"&&(stat.mode&0o077)!==0))
      throw Error("Diretorio de identidade precisa ser privado");
    const temp=configFile+"."+process.pid+".tmp";
    fs.writeFileSync(temp,JSON.stringify({schemaVersion:1,origin})+"\n",{flag:"wx",mode:0o600});
    try{fs.renameSync(temp,configFile);}finally{if(fs.existsSync(temp))fs.unlinkSync(temp);}
    console.log("Dominio da identidade configurado: "+origin);
    return;
  }
  if(!flags.origin){
    if(!fs.existsSync(configFile))throw Error("Configure a origem HTTPS com identity.mjs configure --origin ...");
    const stat=fs.lstatSync(configFile);
    if(!stat.isFile()||stat.isSymbolicLink()||stat.size>1000||
      (process.platform!=="win32"&&(stat.mode&0o077)!==0))
      throw Error("Configuracao da origem insegura");
    const saved=JSON.parse(fs.readFileSync(configFile,"utf8"));
    if(saved.schemaVersion!==1||typeof saved.origin!=="string")throw Error("Configuracao da origem invalida");
    flags.origin=saved.origin;
  }
  if(action==="check"){
    if(!flags.origin.startsWith("https://"))throw Error("Domínio HTTPS obrigatório");
    console.log("Identidade pronta para iniciar em localhost: "+publicOrigin(flags.origin));
    return;
  }
  const service=await createIdentityService({
    dataDir:configDir,port:flags.port,origin:flags.origin,
    logger:msg=>console.log("[identity] "+msg)
  });
  console.log("Moo-IO identidade em loopback 127.0.0.1:"+service.port);
  console.log("Origem HTTPS configurada: "+service.origin);
  console.log("Nao publique a porta ou /internal diretamente.");
  const stop=()=>{
    process.off("SIGINT",stop);process.off("SIGTERM",stop);
    void service.close().catch(e=>console.error(e.message));
  };
  process.once("SIGINT",stop);
  process.once("SIGTERM",stop);
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  main().catch(error=>{console.error("Erro no hub de identidade: "+error.message);process.exitCode=1;});
}
