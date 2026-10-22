// SPDX-License-Identifier: AGPL-3.0-only
import test from "node:test";
import assert from "node:assert/strict";
import {privateNetworkKind,allowedRoomInterface,parseIPv4} from "../server/src/mooio/network.js";
test("accepts LAN and common VPN overlay IPv4",()=>{
  for(const ip of ["192.168.1.9","10.20.30.40","172.25.3.4","100.64.1.2","100.127.2.3","25.22.33.44","26.10.1.2"]) {
    assert.ok(privateNetworkKind(ip),ip);
    assert.equal(allowedRoomInterface(ip,"vpn"),true);
  }
});
test("rejects public, reserved and ambiguous IPv4 addresses",()=>{
  for(const ip of ["8.8.8.8","1.1.1.1","104.20.10.1","100.128.1.1","100.100.100.100","0.0.0.0","169.254.1.1","224.0.0.1","999.4.4.4","192.168.01.1","foo.example.com"]) {
    assert.equal(privateNetworkKind(ip),null,ip);
  }
});
test("LAN mode does not bind Tailscale and VPN mode rejects loopback",()=>{
  assert.equal(allowedRoomInterface("192.168.1.9","lan"),true);
  assert.equal(allowedRoomInterface("100.90.1.5","lan"),false);
  assert.equal(allowedRoomInterface("100.90.1.5","vpn"),true);
  assert.equal(allowedRoomInterface("127.0.0.1","vpn"),false);
  assert.deepEqual(parseIPv4("10.22.0.1"),[10,22,0,1]);
});
