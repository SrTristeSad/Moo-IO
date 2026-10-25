// SPDX-License-Identifier: AGPL-3.0-only
// Read-only lobby for the existing V2 workers. Never expose the admin panel,
// passwords, filesystem paths, moderation data or private invitation codes.
import { discoverRooms, probeRoom } from "./supervisor.mjs";
const VALID_ID=/^[a-z](?:[a-z0-9-]{0,46}[a-z0-9])?$/;
export async function listPublicRooms(directory,{probe=probeRoom,currentId=""}={}){
  if(typeof directory!=="string"||!directory)throw Error("Diretorio V2 indisponivel");
  const entries=discoverRooms(directory);
  const states=await Promise.all(entries.map(e=>probe(e,{timeout:600})));
  const rooms=entries.map((entry,i)=>{
    const {room,id}=entry,stat=states[i];
    if(!VALID_ID.test(id))throw Error("Identificador de sala invalido");
    const row={
      id,name:room.name,preset:room.preset,port:room.port,
      online:stat.online===true,
      players:stat.online?stat.players:0,capacity:room.capacity,
      publicAccess:room.publicAccess===true
    };
    // This is opt-in: publishing an invitation allows anyone to join the room.
    if(row.publicAccess)row.inviteCode=room.roomCode;
    return row;
  });
  return {schemaVersion:1,serverType:"Moo-IO-V2",currentId,
    rooms};
}
