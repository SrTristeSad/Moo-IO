#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
import { fileURLToPath } from "node:url";
import path from "node:path";
import { createRequire } from "node:module";
import { applyPlan, summary } from "./core/mods.mjs";
import { planRoom } from "./core/loader.mjs";
import { DEFAULT_ROOM, MOD_DIR, createRoom, listMods, newRoom, readModFile, readRoom, updateRoom } from "./core/config.mjs";

const root=fileURLToPath(new URL("../../",import.meta.url));
const refRequire=createRequire(path.join(root,"windows/shared/config.js"));
const arg=process.argv.slice(2);
const action=arg.shift()||"help";
function flags(args){
  const opts={_ : []};
  for(let i=0;i<args.length;i++){
    let str=args[i];
    if(!str.startsWith("--")){opts._.push(str);continue;}
    let key=str.slice(2);
    if(!["file","name","preset","host","port","network","bots","capacity"].includes(key)||Object.hasOwn(opts,key)) throw new Error("Opcao desconhecida/repetida: "+str);
    let value=args[++i];
    if(!value||value.startsWith("--")) throw new Error("Faltou valor para "+str);
    opts[key]=value;
  }
  return opts;
}
function pathname(opts){return path.resolve(opts.file||DEFAULT_ROOM);}
function onlyFile(opts){
  for(const key of Object.keys(opts)) if(key!=="file"&&key!=="_") throw new Error("--"+key+" nao e valido neste comando");
}
function usage(){
  console.log(`Servidor privado Moo-IO V2 — configuracao simples e mods JSON
  node servidor/v2/cli.mjs init [--name "Minha sala"] [--preset traditional|custom] [--host 127.0.0.1] [--port 8080] [--file caminho]
  node servidor/v2/cli.mjs mods
  node servidor/v2/cli.mjs enable ID [--file caminho]
  node servidor/v2/cli.mjs disable ID [--file caminho]
  node servidor/v2/cli.mjs preview [--file caminho]
  node servidor/v2/cli.mjs catalog
  node servidor/v2/cli.mjs start [--file caminho]
Aviso: suporte VPS publico depende de autenticacao e proxy seguros ainda nao entregues.`);
}
try{
  const opts=flags(arg), file=pathname(opts);
  if(action==="help"){usage();}
  else if(action==="init"){
    if(opts._.length)throw Error("init nao recebe argumentos sem --opcao");
    const fields={};
    for(const field of ["name","preset","host","network"])if(opts[field]!==undefined)fields[field]=opts[field];
    for(const field of ["port","bots","capacity"])if(opts[field]!==undefined)fields[field]=Number(opts[field]);
    const room=newRoom(fields);
    createRoom(file,room);
    console.log("Sala criada: "+file+"\nCodigo privado: "+room.roomCode+"\nModos: traditional ou custom. Use 'mods' e 'enable ID' para personalizar.");
  }
  else if(action==="configure"){
    if(opts._.length)throw Error("configure nao recebe argumentos sem --opcao");
    const room=readRoom(file),changes={};
    for(const field of ["name","preset","host","network"])if(opts[field]!==undefined)changes[field]=opts[field];
    for(const field of ["port","bots","capacity"])if(opts[field]!==undefined)changes[field]=Number(opts[field]);
    if(!Object.keys(changes).length)throw Error("Informe pelo menos uma opcao: --name, --preset, --host, --port, --network, --bots ou --capacity");
    Object.assign(room,changes);
    if(room.preset==="custom")await planRoom(room); // no invalid mods after editing
    updateRoom(file,room);
    console.log("Sala atualizada: "+file);
    console.log("Nome: "+room.name+" | preset: "+room.preset+" | host: "+room.host+":"+room.port+" | capacidade: "+room.capacity+" | bots: "+room.bots);
  }
  else if(action==="mods"){
    if(opts._.length)throw Error("mods nao recebe argumentos");
    console.log("Mods JSON instalados em "+MOD_DIR+":");
    for(const id of listMods()){const m=readModFile(id);console.log("- "+id+" | "+m.name+" | "+(m.description||""));}
  }
  else if(action==="enable"||action==="disable"){
    onlyFile(opts);
    if(opts._.length!==1)throw Error(action+" requer exatamente um ID de mod");
    const id=opts._[0];const room=readRoom(file);
    if(action==="enable"){
      if(room.preset!=="custom")throw Error("Troque preset para custom antes de ativar mods.");
      const manifest=readModFile(id);
      if(manifest.id!==id)throw Error("ID do manifesto nao confere");
      if(room.mods.includes(id))throw Error("Mod ja esta ativo: "+id);
      room.mods.push(id);
      await planRoom(room); // detects invalid/conflicting mods before saving
    }else {
      if(!room.mods.includes(id))throw Error("Mod nao ativo: "+id);
      room.mods=room.mods.filter(m=>m!==id);
    }
    updateRoom(file,room);
    console.log("Mod "+id+(action==="enable"?" ativado":" desativado")+" em "+file);
  }
  else if(action==="preview"){
    onlyFile(opts);if(opts._.length)throw Error("preview nao recebe argumentos");
    const room=readRoom(file),{plan}=await planRoom(room);
    console.log("Sala: "+room.name+" | preset: "+room.preset+" | "+room.host+":"+room.port+" | jogadores: "+room.capacity+" | bots: "+room.bots);
    console.log("Mods: "+(room.mods.join(", ")||"nenhum")+" | alteracoes: "+plan.length);
    for(const row of summary(plan))console.log("  "+row.mod+" / "+row.path+": "+row.from+" -> "+row.to);
    console.log("Sem mudanças no motor; preview apenas.");
  }
  else if(action==="catalog"){
    onlyFile(opts);if(opts._.length)throw Error("catalog nao recebe argumentos");
    const cfg=refRequire(path.join(root,"windows/shared/config.js"));
    const items=refRequire(path.join(root,"windows/shared/config/items.js"));
    const {AI_TYPES}=await import(new URL("../../windows/server/src/moomoo/modules/aiManager.js",import.meta.url));
    console.log("Mundo: "+JSON.stringify(Object.fromEntries(["treesPerArea","bushesPerArea","totalRocks","goldOres"].map(key=>[key,cfg[key]]))));
    for(const [category,array] of [["animals",AI_TYPES],["weapons",items.weapons],["structures",items.list]]){
      console.log("\n"+category+":");
      array.forEach((o,i)=>console.log(i+" | "+(o.name||o.src||"item "+i)+" | "+JSON.stringify(Object.fromEntries(["health","dmg","speed","killScore"].filter(k=>typeof o[k]==="number").map(k=>[k,o[k]])))));
    }
    console.log("\nspawns:");
    cfg.server.animalSpawnPlan.forEach(o=>console.log(o.index+" | desired "+o.desired));
  }
  else if(action==="start"){
    onlyFile(opts);if(opts._.length)throw Error("start nao recebe argumentos");
    const room=readRoom(file);
    const {plan}=await planRoom(room);
    console.log("Iniciando "+room.name+" | mods "+room.mods.length+" | alteracoes "+plan.length);
    applyPlan(plan);
    const {run}=await import("./core/runtime.mjs");
    await run(room,file);
  }else throw Error("Comando desconhecido: "+action);
}catch(error){console.error("Erro na V2: "+error.message);process.exitCode=1;}
