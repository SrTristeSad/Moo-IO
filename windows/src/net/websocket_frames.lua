-- RFC 6455 binary framing. Pure Lua 5.1/LuaJIT, no socket dependency.
-- Client frames MUST be masked. Incoming server frames MUST NOT be masked.
local M={}
local function u16(n) return string.char(math.floor(n/256)%256,n%256) end
local function u64(n)
  assert(n>=0 and n<=9007199254740991 and n==math.floor(n),"invalid frame length")
  local hi=math.floor(n/4294967296)
  local lo=n%4294967296
  return string.char(math.floor(hi/16777216)%256,math.floor(hi/65536)%256,math.floor(hi/256)%256,hi%256,
    math.floor(lo/16777216)%256,math.floor(lo/65536)%256,math.floor(lo/256)%256,lo%256)
end
local function bxor(a,b)
  local r,p=0,1
  for _=1,8 do
    local aa=a%2;local bb=b%2
    if aa~=bb then r=r+p end
    a=math.floor(a/2);b=math.floor(b/2);p=p*2
  end
  return r
end
local function mask(payload,key)
  local out={}
  for i=1,#payload do out[i]=string.char(bxor(payload:byte(i),key:byte((i-1)%4+1))) end
  return table.concat(out)
end
function M.clientFrame(payload,opcode,key)
  assert(type(payload)=="string","payload must be a string")
  opcode=opcode or 2
  assert(opcode==2 or opcode==8 or opcode==9 or opcode==10,"unsupported opcode")
  assert(type(key)=="string" and #key==4,"four-byte random mask required")
  if opcode>=8 then assert(#payload<=125,"control frame too large") end
  local n=#payload
  local length
  if n<126 then length=string.char(128+n)
  elseif n<=65535 then length=string.char(254)..u16(n)
  else length=string.char(255)..u64(n) end
  return string.char(128+opcode)..length..key..mask(payload,key)
end
-- Incremental decoder: append network bytes, returns complete frames and remaining bytes.
-- No fragmentation, extensions or text frames: these are rejected explicitly.
function M.decodeServer(buffer,maxBytes)
  assert(type(buffer)=="string","buffer must be a string")
  maxBytes=maxBytes or 1048576
  local frames={}
  local pos=1
  while #buffer-pos+1>=2 do
    local b1,b2=buffer:byte(pos,pos+1)
    local fin=math.floor(b1/128)
    local opcode=b1%16
    local masked=math.floor(b2/128)
    local len=b2%128
    if b1%128>=16 then return nil,"reserved websocket bits set" end
    if masked~=0 then return nil,"server frames must not be masked" end
    if fin~=1 then return nil,"fragmented websocket frame not supported" end
    if opcode~=2 and opcode~=8 and opcode~=9 and opcode~=10 then return nil,"unsupported websocket opcode" end
    local header=2
    if len==126 then
      if #buffer-pos+1<4 then break end
      local a,b=buffer:byte(pos+2,pos+3);len=a*256+b;header=4
    elseif len==127 then
      if #buffer-pos+1<10 then break end
      len=0
      for i=pos+2,pos+9 do len=len*256+buffer:byte(i) end
      header=10
    end
    if len>maxBytes then return nil,"websocket frame too large" end
    if opcode>=8 and len>125 then return nil,"oversized control frame" end
    if #buffer-pos+1<header+len then break end
    frames[#frames+1]={opcode=opcode,payload=buffer:sub(pos+header,pos+header+len-1)}
    pos=pos+header+len
  end
  return frames,buffer:sub(pos)
end
return M
