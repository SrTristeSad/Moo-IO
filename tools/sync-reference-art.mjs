// Reference artwork importer — local machine ONLY.
// The archived client contains 174 genuine PNG and SIX lossless WEBP files
// with ".png" names. LÖVE cannot load those WEBP bytes. Transcode them to
// actual PNG while preserving original pixels; NEVER redraw/replace an image.
// If the old node-runtime/client/public/img folder is gone, download the
// pinned upstream ZIP and extract only the manifest-listed image bytes.
// Third-party art and all caches remain gitignored, never committed.
import fs from "node:fs/promises";
import path from "node:path";
import {fileURLToPath} from "node:url";
import sharp from "sharp";
import AdmZip from "adm-zip";
import {verifyPNG} from "./inspect-reference-png.mjs";

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"..");
const target=path.join(root,"assets","reference","img");
const custom=path.join(root,"assets","custom","img");
const manifest=JSON.parse(await fs.readFile(
  path.join(root,"support","reference-image-manifest.json"),"utf8"));
const baseline="06f7c1ca965a7628671676c8d9a7efd3997bb5e7";
const expectedRoot="moomoo-clone-"+baseline+"/client/public/img/";
const report=path.join(root,"ARTES-PENDENTES.txt");
const validKey=/^(animals|weapons|hats|accessories|resources|icons)\/[\w-]+\.png$/;
const allowlisted=Object.entries(manifest)
  .flatMap(([category,files])=>files.map(name=>category+"/"+name));
if(allowlisted.length!==180 || !allowlisted.every(key=>validKey.test(key)))
  throw Error("Manifesto de 180 nomes de sprites esta invalido.");

const sources=[];
const seen=new Set();
function addSource(folder){
  if(!folder)return;
  const resolved=path.resolve(folder);
  const canonical=process.platform==="win32"?resolved.toLowerCase():resolved;
  if(seen.has(canonical))return;
  seen.add(canonical);sources.push(resolved);
}
addSource(process.env.MOO_IO_ART_SOURCE_DIR);
addSource(process.env.MOOQUEST_ART_SOURCE_DIR);
addSource(path.join(root,"node-runtime","client","public","img"));
addSource(path.join(root,"..","Moo-Quest","assets","reference","img"));
addSource(path.join(root,"..","Moo-Quest","assets","custom","img"));
addSource(path.join(root,"node-runtime","dist","official","img"));
addSource(path.join(root,"client","public","img"));
addSource(path.join(root,"assets","source","img"));

const originalSignature=Buffer.from("89504e470d0a1a0a","hex");
function isWebP(data){
  return data.length>=16 &&
    data.toString("ascii",0,4)==="RIFF" &&
    data.toString("ascii",8,12)==="WEBP";
}
async function decode(data){
  if(data.subarray(0,8).equals(originalSignature)){
    // A PNG must be valid, not merely have a PNG-looking filename.
    verifyPNG(data);
    return {bytes:data,converted:false};
  }
  if(isWebP(data)){
    // The pinned archive intentionally contains lossless VP8L WebP bytes in
    // six files named .png. Decode unchanged pixels and retain transparency.
    const bytes=await sharp(data,{failOn:"error",limitInputPixels:16777216})
      .png({compressionLevel:9}).toBuffer();
    verifyPNG(bytes);
    return {bytes,converted:true};
  }
  throw Error("formato desconhecido (nao e PNG nem WebP)");
}
async function readSafe(filename){
  try{return await fs.readFile(filename)}
  catch(err){
    if(err.code==="ENOENT"||err.code==="ENOTDIR")return null;
    throw err;
  }
}
async function store(filename,buffer){
  await fs.mkdir(path.dirname(filename),{recursive:true});
  const temp=filename+".tmp-"+process.pid;
  try{
    await fs.writeFile(temp,buffer);
    await fs.rename(temp,filename);
  }catch(e){await fs.rm(temp,{force:true}).catch(()=>{});throw e}
}
function isMissing(e){return e&&["ENOENT","ENOTDIR"].includes(e.code)}
async function getArchive(){
  if(process.env.MOO_IO_ART_OFFLINE==="1"){
    throw Error("download desativado por MOO_IO_ART_OFFLINE=1");
  }
  const urls=[
    "https://github.com/al007ex/moomoo-clone/archive/"+baseline+".zip",
    "https://codeload.github.com/al007ex/moomoo-clone/zip/"+baseline
  ];
  let error;
  for(const url of urls){
    try{
      console.log("[ARTE] Pasta local incompleta. Baixando referencia congelada do GitHub para uso SOMENTE LOCAL...");
      const res=await fetch(url,{signal:AbortSignal.timeout(45000)});
      if(!res.ok)throw Error("HTTP "+res.status);
      if(Number(res.headers.get("content-length")||0)>40*1024*1024)
        throw Error("ZIP inesperadamente grande");
      const zipBytes=Buffer.from(await res.arrayBuffer());
      if(zipBytes.length>40*1024*1024)throw Error("ZIP maior que 40 MB");
      if(zipBytes.subarray(0,2).toString("ascii")!=="PK")
        throw Error("resposta nao e um ZIP");
      const zip=new AdmZip(zipBytes);
      if(!zip.getEntry(expectedRoot+"weapons/hammer_1.png"))
        throw Error("ZIP nao contem a versao fixada do pacote de artes");
      return zip;
    }catch(err){error=err}
  }
  throw Error("GitHub inacessivel: "+String(error?.message||error));
}

const metrics={existing:0,custom:0,local:0,archive:0,converted:0};
const reasons=new Map();
const pending=[];
const recovered=[];
async function tryCandidate(key,data,origin,destination){
  if(!data)return false;
  try{
    const result=await decode(data);
    if(origin!=="existing" || result.converted){
      await store(destination,result.bytes);
    }
    metrics[origin]++;
    if(result.converted){
      metrics.converted++;
      recovered.push(key+" (WebP -> PNG, mesma imagem)");
    }
    return true;
  }catch(err){
    reasons.set(key,origin+": "+err.message);
    return false;
  }
}
async function sync(){
  const missing=[];
  for(const key of allowlisted){
    const dest=path.join(target,key);
    let copied=false;
    copied=await tryCandidate(key,await readSafe(path.join(custom,key)),
      "custom",dest);
    if(!copied)
      copied=await tryCandidate(key,await readSafe(dest),"existing",dest);
    if(!copied)for(const source of sources){
      if(await tryCandidate(key,await readSafe(path.join(source,key)),
        "local",dest)){copied=true;break}
    }
    if(!copied)missing.push(key);
  }
  let archive=null,archiveError=null;
  if(missing.length){
    try{archive=await getArchive()}
    catch(err){archiveError=String(err.message||err)}
  }
  for(const key of missing){
    const dest=path.join(target,key);
    let copied=false;
    if(archive){
      const entry=archive.getEntry(expectedRoot+key);
      if(entry&&!entry.isDirectory){
        copied=await tryCandidate(key,entry.getData(),"archive",dest);
      }else{
        reasons.set(key,"ausente no ZIP de referencia fixada");
      }
    }
    if(!copied)pending.push(key);
  }
  // The pinned archive is missing exactly bow_1_d.png. This optional
  // user-provided variant must still be copied and take priority if supplied
  // later; never synthesize the diamond artwork from other pictures.
  let optionalVariants=0;
  for(const key of ["weapons/bow_1_d.png"]){
    const output=path.join(target,key);
    const personalized=await readSafe(path.join(custom,key));
    if(personalized && await tryCandidate(key,personalized,"custom",output)){
      optionalVariants++;continue;
    }
    if(await tryCandidate(key,await readSafe(output),"existing",output)){
      optionalVariants++;continue;
    }
    for(const folder of sources){
      if(await tryCandidate(key,await readSafe(path.join(folder,key)),
        "local",output)){optionalVariants++;break}
    }
  }
  const notes=[];
  notes.push("Moo-IO - Relatorio de artes locais");
  notes.push("Esta lista diferencia arquivo AUSENTE de formato de imagem invalido.");
  notes.push("Os arquivos .png da origem podem conter dados WebP. A conversao e automatica.");
  notes.push("Origem principal: "+sources.join(" | "));
  notes.push("Total esperado: "+allowlisted.length);
  notes.push("Prontos: "+(allowlisted.length-pending.length));
  notes.push("WebP convertidos para PNG: "+metrics.converted);
  notes.push("Variante de arco diamante fornecida: "+
    (optionalVariants > 0 ? "SIM" : "NAO (imagem base original usada)"));
  if(recovered.length){
    notes.push("");
    notes.push("WEBP CONVERTIDOS (nao estavam corrompidos):");
    for(const name of recovered)notes.push("- "+name);
  }
  if(pending.length){
    notes.push("");
    notes.push("ARQUIVOS REALMENTE NAO DISPONIVEIS ("+pending.length+"):");
    for(const key of pending){
      notes.push("- "+key+": "+(reasons.get(key)||"nao encontrado"));
    }
  }
  if(archiveError){
    notes.push("");
    notes.push("Falha ao tentar baixar arquivos que faltavam: "+archiveError);
    notes.push("Para usar sem internet, restaure node-runtime/client/public/img");
    notes.push("ou informe MOO_IO_ART_SOURCE_DIR com a pasta das imagens.");
  }
  notes.push("");
  notes.push("Artes de terceiros sao preparadas apenas localmente; nao publicadas no Git.");
  await fs.writeFile(report,notes.join("\n")+"\n","utf8");
  const ready=allowlisted.length-pending.length;
  console.log("[ARTE] "+ready+"/"+allowlisted.length+
    " imagens prontas; WebP convertidos="+metrics.converted+
    "; copiados de origem="+metrics.local+
    "; baixados do ZIP="+metrics.archive+
    "; artes suas="+metrics.custom+".");
  if(recovered.length){
    console.log("[ARTE] Arquivos .png que na verdade continham WebP foram convertidos sem alterar o desenho.");
  }
  if(pending.length){
    const byFolder={};
    for(const key of pending){
      const folder=key.split("/")[0];
      byFolder[folder]=(byFolder[folder]||0)+1;
    }
    const groups=Object.entries(byFolder).map(([cat,n])=>cat+"="+n).join(", ");
    console.warn("[ARTE] "+pending.length+" imagem(ns) ausente(s) apos procura/download: "+groups);
    console.warn("[ARTE] Veja ARTES-PENDENTES.txt para os motivos reais.");
    if(archiveError)console.warn("[ARTE] "+archiveError);
  }
  if(pending.includes("weapons/hammer_1.png")){
    throw Error("A imagem inicial hammer_1.png continua AUSENTE. "+
      "Nao e uma arte corrompida: verifique o download ou a pasta antiga. "+
      "Consulte ARTES-PENDENTES.txt.");
  }
  if(pending.length){
    console.warn("[ARTE] Outros sprites ainda faltam, mas a arma inicial esta pronta.");
  }
}
await sync().catch(err=>{
  console.error("[ARTE] ERRO: "+String(err.message||err));
  process.exitCode=1;
});
