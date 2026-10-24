#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Provision password accounts through stdin; never argv or environment variables.
import { fileURLToPath } from "node:url";
import path from "node:path";
import { AccountStore } from "../../windows/server/src/api/store.js";
import { DEFAULT_ROOM, readRoom, roomDataPath } from "./core/config.mjs";
import { normalizeEmail } from "../../windows/server/src/api/credentials.js";

async function getSecret(){
  if(process.stdin.isTTY)throw Error("Forneca a senha por stdin protegido, nao por argumento.");
  const parts=[];let size=0;
  for await(const block of process.stdin){size+=block.length;if(size>2048)throw Error("Senha longa demais");parts.push(block);}
  let value=Buffer.concat(parts).toString("utf8");
  return value.endsWith("\r\n")?value.slice(0,-2):value.endsWith("\n")?value.slice(0,-1):value;
}
async function main(){
  const args=process.argv.slice(2),action=args.shift()||"help";
  if(action==="help"){
    console.log("V2: provisionar ou trocar senha de uma conta local.");
    console.log("  node servidor/v2/accounts.mjs set-password --file servidor/v2/rooms/principal.json --email usuario@example.org < senha-protegida.txt");
    console.log("Senha: 12-128 caracteres. Nao coloque senhas na linha de comando ou no repositorio.");
    return;
  }
  if(action!=="set-password")throw Error("Comando desconhecido: "+action);
  let file=DEFAULT_ROOM,email=null;
  while(args.length){
    const key=args.shift(),value=args.shift();
    if(!value||value.startsWith("--"))throw Error("Falta valor para "+key);
    if(key==="--file")file=path.resolve(value);
    else if(key==="--email")email=value;
    else throw Error("Opcao nao suportada: "+key);
  }
  if(!normalizeEmail(email))throw Error("Email invalido");
  readRoom(file);
  const password=await getSecret();
  const store=new AccountStore(roomDataPath(file),{passwordMode:true});
  await store.setLocalPassword(email,password);
  const account=store.localAccountForEmail(email);
  if(!account)throw Error("Nao foi possivel registrar a conta");
  await new Promise(r=>setTimeout(r,350));
  console.log("Senha registrada para: "+account.email+" (valor nao exibido).");
}
main().catch(e=>{console.error("Erro no cadastro V2: "+e.message);process.exitCode=1;});
