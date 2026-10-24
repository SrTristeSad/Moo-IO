// SPDX-License-Identifier: AGPL-3.0-only
// V2-only player administration over Node's PARENT/CHILD IPC channel.
// Not a TCP/HTTP API. Do not include private account data or raw IPs.
const PLAYER_ID=/^[a-f0-9]{16}$/;
const REQUEST_ID=/^[a-f0-9]{16,64}$/;
const ROLES=new Set(["admin","mod","player","guest"]);

export function createPlayerAdmin(games){
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
    return {playerId,status:"kicked"};
  }
  function execute({action,playerId}){
    if(action==="players")return {players:players()};
    if(action==="kick")return kick(playerId);
    throw Error("Comando de jogador nao autorizado");
  }
  return {execute};
}

export function installPlayerAdmin(games){
  // Only active in V2 worker spawned with an IPC channel from the supervisor.
  if(typeof process.send!=="function")throw Error("Canal privado com supervisor ausente");
  const control=createPlayerAdmin(games);
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
