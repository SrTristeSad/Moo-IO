import fs from "node:fs/promises";
import path from "node:path";
import {verifyPNG} from "./inspect-reference-png.mjs";
const manifest=JSON.parse(await fs.readFile("support/reference-image-manifest.json","utf8"));
const missing=new Set([
 "animals/boar_1.png","animals/crab_1.png","animals/yeti_1.png",
 "hats/hat_59.png","hats/hat_60.png","hats/hat_61.png"
]);
let count=0;
const keys=[];
for(const [cat,files] of Object.entries(manifest)){
  for(const file of files){
    const key=cat+"/"+file;
    if(!missing.has(key))keys.push(key);
  }
}
keys.push("promotion/banner_4.png","favicon.png");
for(const key of keys){
  const bytes=await fs.readFile(path.join("assets/custom/img",key));
  verifyPNG(bytes);
  count++;
}
if(count!==176)throw Error("Expected 176 files, found "+count);
for(const missingKey of missing){
  try{
    await fs.stat(path.join("assets/custom/img",missingKey));
    throw Error("Unexpected fabricated placeholder: "+missingKey);
  }catch(e){if(e.code!=="ENOENT")throw e;}
}
const unexpected=[];
async function visit(dir,rel=""){
  for(const entry of await fs.readdir(dir,{withFileTypes:true})){
    const key=path.posix.join(rel,entry.name);
    if(entry.isDirectory())await visit(path.join(dir,entry.name),key);
    else if(key.endsWith(".png")&&!keys.includes(key))unexpected.push(key);
  }
}
await visit("assets/custom/img");
if(unexpected.length)throw Error("Unexpected leftover assets: "+unexpected.join(", "));
console.log("UPLOAD PACK CHECKED: 176/176 true PNGs; 6 unavailable sprites explicitly excluded.");