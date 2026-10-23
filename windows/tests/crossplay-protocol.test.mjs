import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { C2S_PACKETS, S2C_PACKETS } from "../server/src/protocol/constants.js";

test("Android and Windows use exactly the same Node packet names and ordering",()=>{
  const android=fs.readFileSync("../android/src/protocol/constants.lua","utf8");
  const windows=fs.readFileSync("./src/protocol/constants.lua","utf8");
  const extract=(file,side)=>{
    const row=file.match(new RegExp("P\\."+side+"List\\s*=\\s*\\{([^}]+)\\}"));
    assert.ok(row,side+" packet table is missing");
    return [...row[1].matchAll(/"([^"]+)"/g)].map(v=>v[1]);
  };
  assert.deepEqual(extract(android,"c2s"),C2S_PACKETS);
  assert.deepEqual(extract(android,"s2c"),S2C_PACKETS);
  assert.deepEqual(extract(windows,"s2c"),S2C_PACKETS);
  assert.deepEqual(extract(windows,"c2s").concat("U"),C2S_PACKETS);
  assert.equal(C2S_PACKETS.at(-1),"U");
});
