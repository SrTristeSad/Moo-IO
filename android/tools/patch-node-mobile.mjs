// SPDX-License-Identifier: AGPL-3.0-only
// Node.js Mobile v18 is built without the Unicode RegExp property-name tables.
// Express 5 -> path-to-regexp uses these classes for ROUTE PARAMETER NAMES only.
// Moo-IO routes use ASCII identifiers, so an ASCII grammar keeps semantics.
// Android packaging only: never rewrite Windows authoritative server sources.
import fs from "node:fs";

const filename=process.argv[2];
if(!filename)throw new Error("Pass the generated offline.mjs bundle");
let source=fs.readFileSync(filename,"utf8");
const fixes=[
    ["var ID_START = /^[$_\\p{ID_Start}]$/u;",
     "var ID_START = /^[$_A-Za-z]$/;"],
    ["var ID_CONTINUE = /^[$\\u200c\\u200d\\p{ID_Continue}]$/u;",
     "var ID_CONTINUE = /^[$_A-Za-z0-9]$/;"],
    ["var ID = /^[$_\\p{ID_Start}][$\\u200c\\u200d\\p{ID_Continue}]*$/u;",
     "var ID = /^[$_A-Za-z][$_A-Za-z0-9]*$/;"]
];
for(const [before,after] of fixes){
    const at=source.indexOf(before);
    if(at<0 || source.indexOf(before,at+before.length)!==-1)
        throw new Error("Missing or ambiguous Node Mobile regex: "+before);
    source=source.slice(0,at)+after+source.slice(at+before.length);
}
if(source.includes("\\p{"))
    throw new Error("Bundled server still contains unsupported Unicode RegExp classes");
fs.writeFileSync(filename,source);
console.log("MOOIO_NODE_MOBILE_COMPAT_PASS");
