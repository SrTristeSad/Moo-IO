// SPDX-License-Identifier: AGPL-3.0-only
// V2 private moderation history. Only the game worker reads this file.
import fs from "node:fs";
import path from "node:path";
import {randomBytes} from "node:crypto";
export const DURATIONS=[5,15,60,360,1440,10080];
export class V2ModerationJournal {
  constructor(dir){
    fs.mkdirSync(dir,{recursive:true,mode:0o700});
    this.file=path.join(dir,"v2-moderation.json");
    this.data={schemaVersion:1,active:[],history:[]};
    if(fs.existsSync(this.file)){
      const s=fs.lstatSync(this.file);
      if(!s.isFile()||s.isSymbolicLink()||s.size>262144||(process.platform!=="win32"&&(s.mode&0o077)))
        throw Error("Registro privado de moderacao invalido");
      const d=JSON.parse(fs.readFileSync(this.file,"utf8"));
      if(d?.schemaVersion!==1||!Array.isArray(d.active)||!Array.isArray(d.history)||d.active.length>200||d.history.length>200)throw Error("Registro de moderacao corrompido");
      this.data=d;
    }
  }
  save(){
    const tmp=this.file+"."+randomBytes(6).toString("hex")+".tmp";
    fs.writeFileSync(tmp,JSON.stringify(this.data),{flag:"wx",mode:0o600});
    try{fs.renameSync(tmp,this.file)}finally{if(fs.existsSync(tmp))fs.unlinkSync(tmp)}
  }
  clean(){
    const now=Date.now(),before=this.data.active.length;
    this.data.active=this.data.active.filter(x=>x.until>now);
    if(before!==this.data.active.length)this.save();
  }
  history(){return this.data.history.slice(-50).reverse();}
  bans(){this.clean();return this.data.active.map(({id,name,reason,until,at})=>({id,name,reason,until,at}))}
  record(action,{name,reason="",minutes=undefined,until=undefined}){
    const event={at:new Date().toISOString(),action,name:String(name).slice(0,80),reason:String(reason).slice(0,120)};
    if(minutes!==undefined)event.minutes=minutes;
    if(until!==undefined)event.until=until;
    this.data.history.push(event);this.data.history=this.data.history.slice(-200);
    this.save();return event;
  }
  add({name,reason,minutes,kind,key}){
    this.clean();
    if(!DURATIONS.includes(minutes)||!["account","device"].includes(kind)||typeof key!=="string"||!key||this.data.active.length>=200)throw Error("Banimento invalido ou limite atingido");
    const row={id:randomBytes(12).toString("hex"),kind,key,name:String(name).slice(0,80),reason:String(reason).slice(0,120),at:new Date().toISOString(),until:Date.now()+minutes*60000};
    this.data.active.push(row);this.record("ban",{name,reason,minutes,until:row.until});return row;
  }
  remove(id){
    if(typeof id!=="string"||!/^[a-f0-9]{24}$/.test(id))throw Error("ID de banimento invalido");
    this.clean();const i=this.data.active.findIndex(x=>x.id===id);
    if(i<0)throw Error("Banimento nao encontrado");
    const [row]=this.data.active.splice(i,1);this.record("unban",{name:row.name});return row;
  }
}
