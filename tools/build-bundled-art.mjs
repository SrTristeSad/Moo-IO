// SPDX-License-Identifier: AGPL-3.0-only
// Run ONLY in GitHub Actions during asset publication, never on the player's PC.
// Kenney's CC0 assets are included into the git tree so users receive real PNGs.
import fs from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";
import { verifyPNG } from "./inspect-reference-png.mjs";

const manifest = JSON.parse(await fs.readFile("support/reference-image-manifest.json","utf8"));
const SHA="3694c6879e487c108f55677be7dd2ca75b07cc3b";
const BASE="https://raw.githubusercontent.com/shorepine/kenney/"+SHA+"/";
const cache=new Map(), failures=[];
const animalSource={
 "boar_1.png":"pig.png",
 "bull_1.png":"buffalo.png",
 "bull_2.png":"buffalo.png",
 "chicken_1.png":"chicken.png",
 "cow_1.png":"cow.png",
 "crab_1.png":"crocodile.png",
 "crate_1.png":"generic",
 "duck_1.png":"duck.png",
 "enemy.png":"snake.png",
 "fish_1.png":"fish",
 "pig_1.png":"pig.png",
 "sheep_1.png":"goat.png",
 "sid.png":"gorilla.png",
 "vince.png":"rhino.png",
 "wolf_1.png":"dog.png",
 "wolf_2.png":"dog.png",
 "yeti_1.png":"bear.png"
};
const animalBase="2d/Animal Pack Remastered/Round (outline)/";
const itemBase="2d/Generic Items/Colored/";
async function get(relative){
  if(cache.has(relative))return cache.get(relative);
  const url=BASE+relative.split("/").map(encodeURIComponent).join("/");
  let last;
  for(let attempt=0;attempt<3;attempt++){
    try{
      const res=await fetch(url,{signal:AbortSignal.timeout(20000)});
      if(!res.ok)throw new Error("HTTP "+res.status+" "+url);
      const bytes=Buffer.from(await res.arrayBuffer());
      // Kenney files must actually contain a valid PNG, not a renamed WEBP.
      verifyPNG(bytes);
      cache.set(relative,bytes);
      return bytes;
    }catch(e){last=e; await new Promise(ok=>setTimeout(ok,500*(attempt+1)));}
  }
  throw last;
}
function item(n){
 return itemBase+"genericItem_color_"+String(n).padStart(3,"0")+".png";
}
function locate(cat,file,index){
 if(cat==="animals"){
   const a=animalSource[file];
   if(a==="fish")return "2d/Fish Pack/fish_blue.png";
   if(a==="generic")return item(20);
   if(!a)throw Error("Unknown animal "+file);
   return animalBase+a;
 }
 if(cat==="weapons"){
   const base=file.replace(/_(?:d|e|g|r)\.png$/,".png");
   const stems=["arrow_1","axe_1","bat_1","bow_1","bullet_1","crossbow_1",
     "crossbow_2","dagger_1","grab_1","great_axe_1","great_hammer_1",
     "hammer_1","musket_1","samurai_1","shield_1","spear_1","stick_1","sword_1"];
   const stem=base.replace(".png","");
   const i=stems.indexOf(stem);
   if(i<0)throw Error("Unexpected weapon "+file);
   return item(30+i);
 }
 if(cat==="hats")return item(50+(index%52));
 if(cat==="accessories")return item(105+(index%21));
 if(cat==="resources")return item(130+(index%4));
 if(cat==="icons")return item(136+(index%2));
 throw Error("Invalid category "+cat);
}
function variant(file){
 if(file.endsWith("_g.png"))return "#ecc151";
 if(file.endsWith("_d.png"))return "#82d1ee";
 if(file.endsWith("_r.png"))return "#dc666a";
 if(file.endsWith("_e.png"))return "#58cf87";
 return null;
}
const outRoot=path.resolve("assets/custom/img");
let count=0;
for(const [cat,files] of Object.entries(manifest)){
 for(let i=0;i<files.length;i++){
   const file=files[i];
   if(!/^[a-z0-9_-]+\.png$/.test(file))throw Error("Unsafe manifest filename");
   const rel=locate(cat,file,i);
   try{
     const source=await get(rel);
     let image=sharp(source,{failOn:"error"}).resize(128,128,{
       fit:"contain",background:{r:0,g:0,b:0,alpha:0}
     });
     const tint=variant(file);
     if(tint)image=image.tint(tint);
     const png=await image.png({compressionLevel:9}).toBuffer();
     verifyPNG(png);
     const where=path.join(outRoot,cat,file);
     await fs.mkdir(path.dirname(where),{recursive:true});
     await fs.writeFile(where,png);
     count++;
   }catch(e){
     failures.push(cat+"/"+file+": "+e.message);
   }
 }
}
if(failures.length){
 console.error(failures.join("\n"));
 throw Error("Could not package "+failures.length+" sprites.");
}
const total=Object.values(manifest).reduce((n,arr)=>n+arr.length,0);
if(count!==total||count!==180)throw Error("Incomplete artwork set "+count+"/"+total);
console.log("ARTPACK READY: "+count+" genuine PNG files; CC0 Kenney source pinned "+SHA);
// Do not copy any assets from MooMoo.io/FRVR's reference art here.
// The packaged alternatives are different artwork and do not imply parity.