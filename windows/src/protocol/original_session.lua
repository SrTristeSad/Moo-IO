-- Authenticated binary gameplay transport matching the RECONSTRUCTED original
-- server/src/protocol/session.js (not the temporary native TCP bridge).
-- Operates only on an actual io-init from the unchanged local server.
local Crypto=require("src.protocol.original_crypto")
local MP=require("src.protocol.msgpack")
local S={}
S.__index=S
function S.new(handshake,build,sha256)
  assert(handshake and handshake.mode==1,"handshake key mode expected")
  assert(type(sha256)=="function","SHA256 digest function required")
  if handshake.sealMode==2 then
    return nil,"original server requested browser-bound bundle seal (mode 2); native client unsupported"
  end
  local salt=handshake.pinned and build and build.salt or nil
  if handshake.pinned and (not build or not build.constants) then
    return nil,"original protocol build parameters are missing"
  end
  local rawKey=Crypto.hexToBinary(handshake.rawKeyHex)
  local key=handshake.pinned and Crypto.mixKey(rawKey,handshake.seed,build) or rawKey
  local masks=handshake.pinned and Crypto.deriveMasks(key) or nil
  return setmetatable({
    key=key,sha256=sha256,masks=masks,
    tables=Crypto.buildTables(handshake.seed,salt),
    sent=0,received=0,ledger=2166136261,
    pinned=handshake.pinned,sealMode=handshake.sealMode
  },S)
end
function S:encode(name,args)
  assert(type(name)=="string" and type(args)=="table")
  local id=self.tables.c2s.enc[name]
  if id==nil then return nil,"packet name not in original table: "..name end
  if #args>16 then return nil,"packet too long" end
  local seq=self.sent+1
  local body=MP.encode({id,args,seq})
  local tag=Crypto.hmacSha256(self.key,body,self.sha256):sub(1,6)
  if self.masks then body=Crypto.mask(body,Crypto.clientMaskSeed(self.masks.c2s,tag)) end
  self.sent=seq
  self.ledger=Crypto.fnvLedger(self.ledger,MP.encode({id,args,seq}))
  return tag..body
end
function S:decode(frame)
  if type(frame)~="string" or #frame<1 or #frame>1048576 then
    return nil,"invalid original server frame"
  end
  local count=self.received+1
  local decoded=frame
  if self.masks then decoded=Crypto.mask(frame,Crypto.serverMaskSeed(self.masks.s2c,count)) end
  local ok,message=pcall(MP.decode,decoded)
  if not ok then return nil,"invalid masked MessagePack: "..tostring(message) end
  if type(message)~="table" or #message~=2 or type(message[1])~="number"
    or type(message[2])~="table" then
    return nil,"unexpected original server packet"
  end
  local name=self.tables.s2c.dec[message[1]]
  if not name then return nil,"unknown original server packet id "..tostring(message[1]) end
  self.received=count
  return {name=name,args=message[2]}
end
return S
