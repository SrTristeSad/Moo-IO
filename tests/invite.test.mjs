// SPDX-License-Identifier: AGPL-3.0-only
import test from "node:test";
import assert from "node:assert/strict";
import { equalRoomCode, publicProtocol, requireRoomInvite, validRoomCode } from "../server/src/mooio/invite.js";

test("codes are validated and compared exactly", () => {
    assert.equal(validRoomCode("hello123"),true);
    assert.equal(validRoomCode("with spaces"),false);
    assert.equal(equalRoomCode("abcdefgh","abcdefgh"),true);
    assert.equal(equalRoomCode("abcdefgh","abcdefgi"),false);
    assert.equal(equalRoomCode("abcdefgh",""),false);
});
test("public protocol omits server-only secrets", () => {
    const result = publicProtocol({buildId:"build1",salt:12,rounds:5,tapA:1,tapB:2,
       rotA:7,rotB:13,mult:17,constants:[1,2,3,4,5,6,7,8],
       sealHex:"SENSITIVE",ownerPassword:"SENSITIVE",createdAt:123});
    assert.equal("sealHex" in result,false);
    assert.equal("ownerPassword" in result,false);
    assert.deepEqual(result.constants,[1,2,3,4,5,6,7,8]);
});
test("join middleware refuses missing/incorrect code", () => {
    let status,body,next=0;
    const response={status(n){status=n;return this;},json(v){body=v;return this;}};
    requireRoomInvite("secret12",{get:()=>""},response,()=>next++);
    assert.equal(status,403);
    assert.equal(body.error,"invite_required");
    requireRoomInvite("secret12",{get:()=> "secret12"},response,()=>next++);
    assert.equal(next,1);
});
