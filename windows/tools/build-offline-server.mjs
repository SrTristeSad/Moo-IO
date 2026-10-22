// Produces a self-contained Node.js server script for the Windows source checkout.
// Build/CI downloads npm packages once; players never run npm or fetch dependencies.
import path from "node:path";
import fs from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"..");
const source=path.join(root,"server","src","index.js");
const destination=path.join(root,"server","src","offline.mjs");
await build({
  absWorkingDir:root,
  entryPoints:[source],
  outfile:destination,
  platform:"node",
  format:"esm",
  target:"node22",
  bundle:true,
  packages:"bundle",
  legalComments:"inline",
  banner:{js:"import { createRequire as __mooRequire } from 'node:module'; const require = __mooRequire(import.meta.url);"},
  logLevel:"info",
  metafile:false
});
const text=await fs.readFile(destination,"utf8");
if(text.length<100000)throw Error("Generated server bundle unexpectedly small");
console.log("MOO IO OFFLINE SERVER BUILT: "+path.relative(root,destination)+
  ", "+Buffer.byteLength(text)+" bytes, no node_modules needed at runtime");
