import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {newRoom,createRoom} from "../core/config.mjs";
import {listPublicRooms} from "../core/public-directory.mjs";
test("V2 IP:port directory lists room choices but never publishes private codes",async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),"mooio-directory-"));
 try{
  const privateRoom=newRoom({name:"Amigos",port:18180,preset:"traditional"});
  const publicRoom=newRoom({name:"Arena dos Lobos",port:18181,preset:"custom",
    publicAccess:true});
  createRoom(path.join(root,"amigos.json"),privateRoom);
  createRoom(path.join(root,"lobos.json"),publicRoom);
  const response=await listPublicRooms(root,{
    currentId:"amigos",
    probe:async ({id,room})=>({online:true,players:id==="amigos"?2:7,
      capacity:room.capacity})
  });
  assert.equal(response.serverType,"Moo-IO-V2");
  assert.equal(response.currentId,"amigos");
  assert.equal(response.rooms.length,2);
  const secret=response.rooms.find(x=>x.id==="amigos");
  assert.equal(secret.publicAccess,false);
  assert.equal(Object.hasOwn(secret,"inviteCode"),false);
  assert.equal(JSON.stringify(response).includes(privateRoom.roomCode),false);
  const advertised=response.rooms.find(x=>x.id==="lobos");
  assert.equal(advertised.publicAccess,true);
  assert.equal(advertised.inviteCode,publicRoom.roomCode);
  assert.equal(advertised.players,7);
  assert.equal(advertised.preset,"custom");
  assert.equal(advertised.port,18181);
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});
test("V2 directory refuses nonexistent or malformed room folder",async()=>{
 await assert.rejects(listPublicRooms("/nonexistent/mooio-v2-directory"),/Diretorio|ENOENT/);
});
