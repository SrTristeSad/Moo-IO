local MessagePack=require("src.protocol.msgpack")
local Handshake=require("src.protocol.handshake")
local Bootstrap={}
function Bootstrap.decodeHandshake(binary)
  local ok,frame=pcall(MessagePack.decode,binary)
  if not ok then return nil,"invalid msgpack: "..tostring(frame) end
  return Handshake.parse(frame)
end
return Bootstrap
