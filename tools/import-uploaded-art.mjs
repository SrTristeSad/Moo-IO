// Import exactly the bytes from the user-provided moomoo-io.zip.
// The checked-in digest was computed over all 176 files in that upload.
// The pinned historical mirror is accepted ONLY when its bytes match the upload.
// This runs once on GitHub Actions, NOT on the players' machines.
import fs from "node:fs/promises";
import path from "node:path";
import {createHash} from "node:crypto";
import sharp from "sharp";
import {verifyPNG} from "./inspect-reference-png.mjs";
const srcRoot=process.argv[2];
if(!srcRoot)throw Error("Expected extracted archive client/public/img root");
const SHA256="ef360924e96082972b8dc35a8f16c39c359432baaf572ac6e5c721884fb7a062";
const OMIT=new Set([
 "animals/boar_1.png","animals/crab_1.png","animals/yeti_1.png",
 "hats/hat_59.png","hats/hat_60.png","hats/hat_61.png"
]);
const manifest=JSON.parse(await fs.readFile("support/reference-image-manifest.json","utf8"));
const keys=Object.entries(manifest).flatMap(([category,files])=>files
  .map(name=>category+"/"+name)).filter(key=>!OMIT.has(key));
keys.push("promotion/banner_4.png","favicon.png");
keys.sort();
if(keys.length!==176)throw Error("Unexpected ZIP image count "+keys.length);
const original=new Map();
const hash=createHash("sha256");
for(const key of keys){
  if(!/^(?:[a-z]+\/)?[a-z0-9_-]+\.png$/.test(key))throw Error("Unsafe path: "+key);
  const bytes=await fs.readFile(path.join(srcRoot,key));
  original.set(key,bytes);
  const name=Buffer.from(key,"utf8");
  const nameLen=Buffer.alloc(4),fileLen=Buffer.alloc(8);
  nameLen.writeUInt32BE(name.length);
  fileLen.writeBigUInt64BE(BigInt(bytes.length));
  hash.update(nameLen);hash.update(name);hash.update(fileLen);hash.update(bytes);
}
const actual=hash.digest("hex");
if(actual!==SHA256){
  throw Error("Archive differs from user supplied moomoo-io.zip; refusing replacement. "+actual);
}
const staging="assets/custom/img-incoming";
await fs.rm(staging,{recursive:true,force:true});
let converted=0;
for(const key of keys){
  const bytes=original.get(key);
  let png=bytes;
  if(bytes.subarray(0,4).toString("ascii")==="RIFF" &&
     bytes.subarray(8,12).toString("ascii")==="WEBP"){
    const src=sharp(bytes,{failOn:"error"});
    const shape=await src.metadata();
    png=await sharp(bytes).png({compressionLevel:9}).toBuffer();
    const afterShape=await sharp(png).metadata();
    if(shape.width!==afterShape.width || shape.height!==afterShape.height) {
      throw Error("Dimensions changed in "+key);
    }
    const before=await sharp(bytes).ensureAlpha().raw().toBuffer();
    const after=await sharp(png).ensureAlpha().raw().toBuffer();
    if(!before.equals(after))throw Error("Conversion changed pixels in "+key);
    converted++;
  }
  verifyPNG(png);
  const target=path.join(staging,key);
  await fs.mkdir(path.dirname(target),{recursive:true});
  await fs.writeFile(target,png);
}
if(converted!==8)throw Error("Expected 8 mislabeled WebP images, got "+converted);
await fs.rm("assets/custom/img",{recursive:true,force:true});
await fs.rename(staging,"assets/custom/img");
console.log("UPLOAD ZIP EXACT MATCH: "+actual);
console.log("READY IN GIT: 176 images, 168 source PNG, 8 pixel-identical WebP conversions");
console.log("MISSING (NOT FABRICATED): "+[...OMIT].join(", "));