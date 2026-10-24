// SPDX-License-Identifier: AGPL-3.0-only
// V2-only player administration over Node's PARENT/CHILD IPC channel.
// Not a TCP/HTTP API. Do not include private account data or raw IPs.
import { V2ModerationJournal, DURATIONS } from "./v2-moderation.js";
const PLAYER_ID=/^[a-f0-9]{16}$/;
const REQUEST_ID=/^[a-f0-9]{16,64}$/;
const ROLES=new Set(["admin","mod","player","guest"]);

export function createPlayerAdmin(games,{moderation=null,dataDir=null,journal=null}={}){
  const audit=journal||(dataDir?new V2ModerationJournal(dataDir):null);
  const game=games.get("LC");
  if(!game)throw Error("Mundo LC nao encontrado");
  function safeRole(player){
    const role=player.account?.role;
    if(!role)return player.account?"player":"guest";
    return ROLES.has(role)?role:"player";
  }
  function players(){
    return game.players.filter(p=>PLAYER_ID.test(p.id)).slice(0,40).map(p=>({
      id:p.id,
      name:String(p.name||"Jogador").slice(0,80),
      role:safeRole(p),
      connectedAt:Number.isFinite(p.connectedAt)?p.connectedAt:null
    }));
  }
  function kick(playerId){
    if(typeof playerId!=="string"||!PLAYER_ID.test(playerId))
      throw Error("ID de jogador invalido");
    const player=game.players.find(p=>p.id===playerId);
    if(!player)throw Error("Jogador nao esta conectado");
    if(["admin","mod"].includes(safeRole(player)))
      throw Error("Jogador com permissao de equipe nao pode ser expulso por este painel");
    if(typeof player.kick!=="function")throw Error("Jogador nao possui conexao expulsavel");
    player.kick("kicked");
    audit?.record("kick",{name:player.name});
    return {playerId,status:"kicked"};
  }
  function ban(playerId,minutes,reason){
    if(!audit||!moderation)throw Error("Moderacao persistente indisponivel");
    if(typeof playerId!=="string"||!PLAYER_ID.test(playerId))throw Error("ID de jogador invalido");
    if(!DURATIONS.includes(minutes))throw Error("Duracao de banimento nao permitida");
    if(typeof reason!=="string"||reason.length>120||/[\x00-\x1f\x7f]/.test(reason))
      throw Error("Motivo do banimento invalido");
    const player=game.players.find(p=>p.id===playerId);
    if(!player)throw Error("Jogador nao conectado");
    if(["admin","mod"].includes(safeRole(player)))throw Error("Equipe protegida contra banimento");
    const kind=player.account?.id?"account":player.did?"device":null;
    const key=kind==="account"?String(player.account.id):kind==="device"?String(player.did):null;
    if(!kind||!key)throw Error("Jogador sem identificador persistente; use expulsar");
    audit.clean();
    if(audit.data.active.some(x=>x.kind===kind&&x.key===key))
      throw Error("Jogador ja possui banimento temporario ativo");
    const until=Date.now()+minutes*60000;
    moderation.ban({...kind==="account"?{accountId:key}:{did:key},
      name:player.name,reason,until},{name:"V2 panel"});
    const record=audit.add({name:player.name,reason,minutes,kind,key});
    player.kick("banned");
    return {id:record.id,playerId,status:"banned",until:record.until};
  }
  function unban(id){
    if(!audit||!moderation)throw Error("Moderacao persistente indisponivel");
    const row=audit.remove(id);
    if(row.kind==="account")moderation.unbanAccount(row.key);
    else moderation.unbanIp(null,row.key);
    return {id,status:"unbanned"};
  }
  function execute({action,playerId,minutes,reason,banId}){
    if(action==="players")return {players:players()};
    if(action==="kick")return kick(playerId);
    if(action==="ban")return ban(playerId,minutes,reason);
    if(action==="bans"){
      if(!audit)throw Error("Historico indisponivel");
      return {bans:audit.bans()};
    }
    if(action==="history"){
      if(!audit)throw Error("Historico indisponivel");
      return {history:audit.history()};
    }
    if(action==="unban")return unban(banId);
    throw Error("Comando de jogador nao autorizado");
  }
  return {execute};
}

export function installPlayerAdmin(games,options={}){
  // Only active in V2 worker spawned with an IPC channel from the supervisor.
  if(typeof process.send!=="function")throw Error("Canal privado com supervisor ausente");
  const control=createPlayerAdmin(games,options);
  process.on("message",message=>{
    if(message?.type!=="v2-player-admin"||!REQUEST_ID.test(message.requestId))return;
    let payload;
    try{
      payload={ok:true,result:control.execute(message)};
    }catch(error){
      payload={ok:false,error:String(error.message).slice(0,180)};
    }
    if(process.connected)process.send({type:"v2-player-admin-result",requestId:message.requestId,...payload});
  });
}
