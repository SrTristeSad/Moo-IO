import test from "node:test";
import assert from "node:assert/strict";
import sharp from "sharp";
import {verifyPNG} from "../tools/inspect-reference-png.mjs";

test("real PNG decodes; fake signature-only PNG is rejected",async()=>{
  const pixel=Buffer.from([23,45,67,190]);
  const png=await sharp(pixel,{raw:{width:1,height:1,channels:4}})
    .png().toBuffer();
  assert.equal(verifyPNG(png),"1x1");
  const fake=Buffer.alloc(33);
  Buffer.from("89504e470d0a1a0a","hex").copy(fake);
  fake.writeUInt32BE(13,8);
  fake.write("IHDR",12);
  fake.writeUInt32BE(1,16);
  fake.writeUInt32BE(1,20);
  assert.throws(()=>verifyPNG(fake));
});

test("lossless WebP mislabeled .png converts to a real pixel-identical PNG",async()=>{
  const raw=Buffer.from([255,0,80,255]);
  const webp=await sharp(raw,{raw:{width:1,height:1,channels:4}})
    .webp({lossless:true}).toBuffer();
  assert.equal(webp.subarray(0,4).toString(),"RIFF");
  assert.equal(webp.subarray(8,12).toString(),"WEBP");
  assert.throws(()=>verifyPNG(webp),/assinatura PNG/);
  const png=await sharp(webp).png().toBuffer();
  assert.equal(verifyPNG(png),"1x1");
  assert.deepEqual(await sharp(png).raw().toBuffer(),raw);
});
