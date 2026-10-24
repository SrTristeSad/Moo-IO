#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Web panel lives only on 127.0.0.1; reach remotely over an SSH tunnel.
import path from "node:path";
import { createPanel, panelCredentials, ADMIN_EMAIL } from "./core/panel.mjs";
import { DEFAULT_ROOMS } from "./core/supervisor.mjs";
import { setStaffRole } from "./core/panel-roles.mjs";

async function readPassword(){
  if(process.stdin.isTTY)throw Error("Passe a senha pelo stdin (read -rsp em terminal; nao use argumento).");
  const chunks=[];let total=0;
  for await(const part of process.stdin){
    total+=part.length;
    if(total>1024)throw Error("Senha longa demais");
    chunks.push(part);
  }
  const text=Buffer.concat(chunks).toString("utf8");
  return text.replace(/\r?\n$/,"");
}
function parse(args){
  const flags={rooms:DEFAULT_ROOMS,port:8787};
  const seen=new Set();
  while(args.length){
    const key=args.shift(),value=args.shift();
    if(!["--rooms","--port"].includes(key)||seen.has(key)||!value||value.startsWith("--"))
      throw Error("Argumento invalido: "+key);
    seen.add(key);
    if(key==="--rooms")flags.rooms=path.resolve(value);
    else {
      flags.port=Number(value);
      if(!Number.isInteger(flags.port)||flags.port<1024||flags.port>65534)
        throw Error("Porta do painel deve ser de 1024 ate 65534");
    }
  }
  return {flags,seen};
}
async function main(){
  const [action="help",...args]=process.argv.slice(2);
  if(action==="help"){
    console.log([
      "Moo-IO V2 - painel administrativo local da VPS",
      "  node servidor/v2/panel.mjs password [--rooms pasta] < senha-protegida.txt",
      "  node servidor/v2/panel.mjs serve [--rooms pasta] [--port 8787]",
      "  node servidor/v2/panel.mjs check [--rooms pasta]",
      "  node servidor/v2/panel.mjs staff EMAIL viewer|moderator|revoke [--rooms pasta] (senha via stdin para adicionar)",
      "",
      "Abra http://127.0.0.1:8787 localmente ou use tunel SSH.",
      "Nunca encaminhe o painel pelo Caddy nem publique a porta na VPS."
    ].join("\n"));
    return;
  }
  if(!["password","serve","check","staff"].includes(action))throw Error("Comando nao suportado: "+action);
  const staffEmail=action==="staff"?args.shift():null;
  const staffRole=action==="staff"?args.shift():null;
  const {flags,seen}=parse(args);
  if(action==="check"){
    if(seen.has("--port"))throw Error("--port nao e aceito por check");
    const credentials=panelCredentials(flags.rooms);
    if(!credentials.users[ADMIN_EMAIL])throw Error("Defina a senha administrativa antes de habilitar o painel");
    console.log("Senha administrativa configurada; painel pronto para iniciar em localhost.");
    return;
  }
  if(action==="staff"){
    if(seen.has("--port"))throw Error("staff aceita somente --rooms");
    const credentials=panelCredentials(flags.rooms);
    if(!credentials.users[ADMIN_EMAIL])throw Error("Crie primeiro a senha do proprietario");
    if(staffRole!=="revoke"){
      const password=await readPassword();
      await credentials.set(staffEmail,password);
    }
    setStaffRole(path.dirname(credentials.file),staffEmail,staffRole);
    console.log("Permissao de equipe atualizada; reinicie o painel para recarregar credenciais.");
    return;
  }
  if(action==="password"){
    if(seen.has("--port"))throw Error("--port nao e valido para password");
    const password=await readPassword();
    await panelCredentials(flags.rooms).set(ADMIN_EMAIL,password);
    console.log("Senha administrativa configurada. Reinicie o processo do painel se ja estiver ativo.");
  }else{
    const p=await createPanel(flags);
    console.log("Painel local V2: http://"+p.host+":"+p.port);
    console.log("Acesso remoto: ssh -L "+p.port+":127.0.0.1:"+p.port+" usuario@SEU_SERVIDOR");
    console.log("Somente localhost. Nunca adicione o painel ao Caddy.");
    const stop=()=>{
      process.off("SIGINT",stop);process.off("SIGTERM",stop);
      void p.close().catch(error=>console.error(error.message));
    };
    process.once("SIGINT",stop);
    process.once("SIGTERM",stop);
  }
}
main().catch(error=>{console.error("Erro no painel V2: "+error.message);process.exitCode=1;});
