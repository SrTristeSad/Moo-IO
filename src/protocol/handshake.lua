-- Decode already-parsed MessagePack io-init frame and validate its structure.
-- No network, key derivation or packet encryption is implemented here.
local H={}
function H.parse(frame)
  if type(frame)~="table" or frame[1]~="io-init" then
    return nil,"expected io-init"
  end
  local args=frame[2]
  if type(args)~="table" or #args~=6 then
    return nil,"invalid io-init arguments"
  end
  local unpackArgs = table.unpack or unpack
  local socketId,seed,keyHex,mode,pinned,sealMode=unpackArgs(args)
  if type(socketId)~="string" or #socketId~=16 or not socketId:match("^[0-9a-fA-F]+$") then
    return nil,"invalid socket id"
  end
  if type(seed)~="number" or seed%1~=0 or seed<0 or seed>4294967295 then
    return nil,"invalid seed"
  end
  if type(keyHex)~="string" or #keyHex~=32 or not keyHex:match("^[0-9a-fA-F]+$") then
    return nil,"invalid key"
  end
  if mode~=1 then return nil,"unsupported transport mode" end
  if pinned~=0 and pinned~=1 then return nil,"invalid pinned flag" end
  if sealMode~=0 and sealMode~=1 and sealMode~=2 then return nil,"invalid seal mode" end
  return {socketId=socketId,seed=seed,rawKeyHex=keyHex,
    mode=mode,pinned=pinned==1,sealMode=sealMode}
end
return H
