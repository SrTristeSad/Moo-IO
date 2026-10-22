import fs from "node:fs/promises";
import path from "node:path";
import {verifyPNG} from "./inspect-reference-png.mjs";
const manifest=JSON.parse(await fs.readFile("support/reference-image-manifest.json","utf8"));
let count=0;
for(const [cat,files] of Object.entries(manifest)){
 for(const file of files){
   const where=path.join("assets/custom/img",cat,file);
   const bytes=await fs.readFile(where);
   verifyPNG(bytes);
   count++;
 }
}
if(count!==180)throw Error("Expected 180, found "+count);
console.log("MOO IO ASSETS VALIDATED: 180/180 real PNGs.");
