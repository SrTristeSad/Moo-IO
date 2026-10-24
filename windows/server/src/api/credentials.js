// SPDX-License-Identifier: AGPL-3.0-only
// V2-only credentials; password hashes stay outside public account metadata.
import fs from "node:fs";
import path from "node:path";
import { scrypt as scryptCb, randomBytes, timingSafeEqual } from "node:crypto";
import { promisify } from "node:util";
const scrypt=promisify(scryptCb);
const OPT={N:32768,r:8,p:1,maxmem:64*1024*1024};
export function normalizeEmail(value){
  if(typeof value!=="string")return null;
  const key=value.trim().toLowerCase();
  return key.length<=120&&/^[^\s@:/\\]{1,64}@[^\s@:/\\]{1,64}\.[a-zA-Z]{2,24}$/.test(key)?key:null;
}
export class LocalCredentials{
  constructor(dataDir){
    fs.mkdirSync(dataDir,{recursive:true,mode:0o700});
    this.file=path.join(dataDir,"v2-credentials.json");
    this.users=Object.create(null);
    if(fs.existsSync(this.file)){
      const st=fs.lstatSync(this.file);
      if(!st.isFile()||st.isSymbolicLink()||st.size>1048576)throw Error("Arquivo de credenciais V2 invalido.");
      const input=JSON.parse(fs.readFileSync(this.file,"utf8"));
      if(input?.schemaVersion!==1||!input.users||typeof input.users!=="object"||Array.isArray(input.users))
        throw Error("Formato de credenciais V2 invalido.");
      for(const [email,record] of Object.entries(input.users)){
        if(normalizeEmail(email)!==email||record?.algo!=="scrypt-v1"||
          !/^[a-f0-9]{64}$/.test(record.salt)||!/^[a-f0-9]{128}$/.test(record.hash))
          throw Error("Credencial corrompida; servidor nao iniciara.");
        this.users[email]=record;
      }
    }
  }
  async set(email,password){
    const key=normalizeEmail(email);
    if(!key||typeof password!=="string"||password.length<12||password.length>128||
       Buffer.byteLength(password,"utf8")>512||/[\x00-\x1f\x7f]/.test(password))
      throw Error("Informe email valido e senha de 12-128 caracteres sem quebras de linha.");
    const salt=randomBytes(32),hash=await scrypt(password,salt,64,OPT);
    this.users[key]={algo:"scrypt-v1",salt:salt.toString("hex"),hash:hash.toString("hex")};
    const temp=this.file+"."+process.pid+"."+randomBytes(6).toString("hex")+".tmp";
    fs.writeFileSync(temp,JSON.stringify({schemaVersion:1,users:this.users},null,2)+"\n",{flag:"wx",mode:0o600});
    try{fs.renameSync(temp,this.file);}finally{if(fs.existsSync(temp))fs.unlinkSync(temp);}
  }
  async verify(email,password){
    const key=normalizeEmail(email);
    if(!key||typeof password!=="string"||Buffer.byteLength(password,"utf8")>512)return false;
    const row=this.users[key];
    if(!row)return false;
    const hash=await scrypt(password,Buffer.from(row.salt,"hex"),64,OPT),expected=Buffer.from(row.hash,"hex");
    return hash.length===expected.length&&timingSafeEqual(hash,expected);
  }
}
