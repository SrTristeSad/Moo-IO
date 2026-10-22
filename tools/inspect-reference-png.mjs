// Metadata-only PNG auditor: checks local art without publishing images.
// CLI: node tools/inspect-reference-png.mjs [folder]. Exits nonzero on invalid
// PNG signatures/chunks/IDAT. This rejects fake .png placeholders at source.
import fs from "node:fs/promises";
import path from "node:path";
import zlib from "node:zlib";
import {fileURLToPath} from "node:url";
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"..");
const base=path.resolve(process.argv[2]||path.join(root,"assets","reference","img"));
const signature=Buffer.from("89504e470d0a1a0a","hex");
export function verifyPNG(buffer){
  if(buffer.length<45)throw Error("arquivo pequeno demais para PNG");
  if(!buffer.subarray(0,8).equals(signature))
    throw Error("assinatura PNG incorreta (arquivo nao e PNG)");
  let at=8,width=0,height=0,seenIHDR=false,seenIEND=false;
  const compressed=[];
  while(at+12<=buffer.length){
    const len=buffer.readUInt32BE(at);
    const type=buffer.toString("latin1",at+4,at+8);
    const limit=at+len+12;
    if(limit>buffer.length)throw Error("chunk "+type+" truncado");
    if(!/^[A-Za-z]{4}$/.test(type))throw Error("chunk invalido");
    const chunk=buffer.subarray(at+8,at+8+len);
    if(type==="IHDR"){
      if(seenIHDR||len!==13)throw Error("IHDR duplicado/invalido");
      width=chunk.readUInt32BE(0);height=chunk.readUInt32BE(4);
      if(!width||!height||width>32768||height>32768)
        throw Error("dimensoes invalidas");
      seenIHDR=true;
    }
    if(type==="IDAT")compressed.push(chunk);
    if(type==="IEND"){seenIEND=true;break;}
    at=limit;
  }
  if(!seenIHDR||!seenIEND||compressed.length===0)
    throw Error("faltando IHDR, IDAT ou IEND");
  try{zlib.inflateSync(Buffer.concat(compressed));}
  catch{throw Error("IDAT comprimido invalido");}
  return width+"x"+height;
}
function isWebP(data){
  return data.length>=16 &&
    data.toString("ascii",0,4)==="RIFF" &&
    data.toString("ascii",8,12)==="WEBP";
}
async function audit(){
  // .png describes a NAME, not a guarantee of the underlying codec.
  // Some archived images are VP8L WebP inside RIFF containers.
  const {default:sharp}=await import("sharp");
  let checked=0,pngs=0,webps=0,invalid=0;
  for(const category of ["animals","weapons","hats","accessories","resources","icons"]){
    let entries;
    try{entries=await fs.readdir(path.join(base,category));}
    catch(error){
      console.error("[IMG] Pasta ausente: "+category+" (NAO significa arquivos corrompidos)");
      invalid++;continue;
    }
    for(const file of entries.filter(name=>name.toLowerCase().endsWith(".png"))){
      checked++;
      const key=category+"/"+file;
      try{
        const data=await fs.readFile(path.join(base,key));
        if(isWebP(data)){
          const metadata=await sharp(data).metadata();
          if(metadata.format!=="webp" || !metadata.width || !metadata.height)
            throw Error("WebP nao decodificavel");
          console.log("[IMG] WEBP COM NOME .PNG (VALIDO): "+key+
            " -> "+metadata.width+"x"+metadata.height);
          webps++;
        }else{
          verifyPNG(data);
          pngs++;
        }
      }catch(err){
        invalid++;
        console.error("[IMG] FALHA REAL: "+key+" - "+err.message);
      }
    }
  }
  console.log("[IMG] "+checked+" arquivos: "+pngs+" PNG legitimos; "+
    webps+" WebP validos chamados .png; "+invalid+" erro(s).");
  if(invalid)process.exitCode=1;
}

if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) await audit();
