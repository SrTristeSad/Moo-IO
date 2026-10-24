#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Shared browser login hub for all V2 rooms on this VPS.
import path from "node:path";
import {fileURLToPath} from "node:url";
import {createIdentityService} from "./core/identity.mjs";
import {DEFAULT_ROOMS} from "./core/supervisor.mjs";

async function main(){
  const [action="help",...args]=process.argv.slice(2);
  if(action==="help"){
    console.log("Moo-IO V2 -- browser-hosted identity");
    console.log("  node servidor/v2/identity.mjs serve --origin https://auth.jogo.example.com [--rooms pasta] [--port 8788]");
    console.log("Run under HTTPS Caddy proxy; listens ONLY at 127.0.0.1. Never expose /internal.");
    return;
  }
  if(action!=="serve")throw Error("Comando invalido");
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
  if(!flags.origin)throw Error("Informe --origin https://auth.SEUDOMINIO");
  const service=await createIdentityService({
    dataDir:path.join(flags.rooms,".identity"),port:flags.port,origin:flags.origin,
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
