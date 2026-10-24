// SPDX-License-Identifier: AGPL-3.0-only
// Local VPS monitoring only. Never publishes HTTP ports or room invite secrets.
import { probeRoom } from "./supervisor.mjs";
export function summarizeStatus(results,{time=new Date()}={}){
  if(!Array.isArray(results))throw Error("Lista de status invalida");
  const rooms=results.map(item=>({
    id:item.id,name:item.name,online:!!item.online,
    host:item.host,port:item.port,
    players:item.online ? item.players : 0,capacity:item.capacity,
    mods:item.mods,bots:item.bots,
    ...(item.online?{}:{reason:String(item.reason||"Sem resposta").slice(0,300)})
  }));
  const totals={
    rooms:rooms.length,online:rooms.filter(room=>room.online).length,
    offline:rooms.filter(room=>!room.online).length,
    players:rooms.reduce((n,room)=>n+room.players,0),
    capacity:rooms.reduce((n,room)=>n+room.capacity,0)
  };
  return {schemaVersion:1,timestamp:time.toISOString(),healthy:totals.offline===0&&totals.rooms>0,totals,rooms};
}
export async function scanRooms(entries,{probe=probeRoom,timeout=1000}={}){
  if(!Array.isArray(entries))throw Error("Salas invalidas");
  const result=await Promise.all(entries.map(async entry=>{
    try{return await probe(entry,{timeout});}
    catch(error){
      const {id,room}=entry;
      return {id,name:room.name,online:false,host:room.host,port:room.port,
        players:0,capacity:room.capacity,mods:room.mods.length,bots:room.bots,
        reason:error.message};
    }
  }));
  return summarizeStatus(result);
}
export function statusText(report){
  return report.rooms.map(row=>(
    (row.online?"ONLINE ":"OFFLINE ")+row.id+" | "+row.host+":"+row.port+
    " | "+row.players+"/"+row.capacity+" jogadores | mods "+row.mods+
    (row.reason?" | "+row.reason:"")
  )).join("\n");
}
export function statusKey(report){
  // Ignore timestamps and transient exception text.
  return JSON.stringify(report.rooms.map(({id,online,players,capacity})=>({id,online,players,capacity})));
}
