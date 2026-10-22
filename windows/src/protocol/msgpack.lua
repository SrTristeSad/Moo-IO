-- Independent MessagePack subset used by Moo-Quest's Lua protocol.
-- Lua 5.1/LuaJIT/5.4 compatible; no native library required.
-- Supports nil, booleans, int32, uint32, float64, UTF-8 strings, arrays, maps.
-- M.null represents nil inside arrays/maps, because Lua tables cannot hold nil.
local M = {}
M.null = setmetatable({}, {__tostring=function() return "msgpack.null" end})
local mapMarker = {}
function M.map(value)
  assert(type(value)=="table" and value~=M.null,"map table expected")
  return setmetatable(value,{__msgpackMap=mapMarker})
end
local function be(n,count)
  local out={}
  for i=count-1,0,-1 do out[#out+1]=string.char(math.floor(n/256^i)%256) end
  return table.concat(out)
end
local function encodeFloat64(value)
  local negative=value<0 or (value==0 and 1/value==-math.huge)
  local a=math.abs(value)
  local exponent,fraction
  if value~=value then
    exponent,fraction=2047,2^51
  elseif a==math.huge then
    exponent,fraction=2047,0
  elseif a==0 then
    exponent,fraction=0,0
  else
    -- Find the power of two without math.frexp (removed from recent Lua).
    local e=0
    local m=a
    if m>=1 then
      while m>=2 do m=m/2; e=e+1 end
    else
      while m<1 do m=m*2; e=e-1 end
    end
    if e>=-1022 then
      exponent=e+1023
      fraction=math.floor((m-1)*2^52+0.5)
      if fraction==2^52 then exponent=exponent+1;fraction=0 end
    else
      exponent=0
      fraction=math.floor(a/(2^-1074)+0.5)
    end
  end
  local high=(negative and 2147483648 or 0)+exponent*1048576+math.floor(fraction/4294967296)
  local low=fraction%4294967296
  return string.char(0xcb)..be(high,4)..be(low,4)
end
local function decodeFloat64(high,low)
  local negative=high>=2147483648
  local exponent=math.floor(high/1048576)%2048
  local fraction=(high%1048576)*4294967296+low
  local n
  if exponent==2047 then
    n=fraction==0 and math.huge or (0/0)
  elseif exponent==0 then
    n=fraction*2^-1074
  else
    n=(1+fraction/2^52)*2^(exponent-1023)
  end
  return negative and -n or n
end
local function isMap(v)
  if getmetatable(v) and getmetatable(v).__msgpackMap==mapMarker then return true end
  for k in pairs(v) do
    if type(k)~="number" or k<1 or k%1~=0 or k>#v then return true end
  end
  return false
end
local encode
encode=function(v,depth)
  if depth>32 then error("msgpack nesting limit") end
  if v==nil or v==M.null then return string.char(0xc0) end
  local t=type(v)
  if t=="boolean" then return string.char(v and 0xc3 or 0xc2) end
  if t=="number" then
    if v==math.floor(v) and v>=-2147483648 and v<=4294967295 then
      if v>=0 then
        if v<=127 then return string.char(v) end
        if v<=255 then return string.char(0xcc,v) end
        if v<=65535 then return string.char(0xcd)..be(v,2) end
        return string.char(0xce)..be(v,4)
      end
      if v>=-32 then return string.char(256+v) end
      if v>=-128 then return string.char(0xd0,256+v) end
      if v>=-32768 then return string.char(0xd1)..be(v+65536,2) end
      return string.char(0xd2)..be(v+4294967296,4)
    end
    return encodeFloat64(v)
  end
  if t=="string" then
    local n=#v
    if n<=31 then return string.char(0xa0+n)..v end
    if n<=255 then return string.char(0xd9,n)..v end
    if n<=65535 then return string.char(0xda)..be(n,2)..v end
    return string.char(0xdb)..be(n,4)..v
  end
  if t=="table" then
    if isMap(v) then
      local n=0
      for _ in pairs(v) do n=n+1 end
      local head
      if n<=15 then head=string.char(0x80+n)
      elseif n<=65535 then head=string.char(0xde)..be(n,2)
      else error("map too large") end
      local out={head}
      for k,x in pairs(v) do
        out[#out+1]=encode(k,depth+1)
        out[#out+1]=encode(x,depth+1)
      end
      return table.concat(out)
    end
    local n=#v
    local head
    if n<=15 then head=string.char(0x90+n)
    elseif n<=65535 then head=string.char(0xdc)..be(n,2)
    else error("array too large") end
    local out={head}
    for i=1,n do out[#out+1]=encode(v[i],depth+1) end
    return table.concat(out)
  end
  error("unsupported type "..t)
end
function M.encode(value) return encode(value,0) end
function M.decode(data)
  assert(type(data)=="string","binary string expected")
  local pos=1
  local function read(n)
    if n<0 or pos+n-1>#data then error("truncated msgpack") end
    local s=data:sub(pos,pos+n-1);pos=pos+n;return s
  end
  local function uint(n)
    local s=read(n);local value=0
    for i=1,#s do value=value*256+s:byte(i) end
    return value
  end
  local parse
  parse=function(depth)
    if depth>32 then error("msgpack nesting limit") end
    local b=uint(1)
    if b<=0x7f then return b end
    if b>=0xe0 then return b-256 end
    if b>=0xa0 and b<=0xbf then return read(b-0xa0) end
    if b>=0x90 and b<=0x9f then
      local arr={}
      for i=1,b-0x90 do arr[i]=parse(depth+1) end
      return arr
    end
    if b>=0x80 and b<=0x8f then
      local o={}
      for _=1,b-0x80 do
        local k=parse(depth+1)
        assert(k~=M.null and k~=nil,"null map key")
        o[k]=parse(depth+1)
      end
      return M.map(o)
    end
    if b==0xc0 then return M.null end
    if b==0xc2 then return false end
    if b==0xc3 then return true end
    if b==0xcc then return uint(1) end
    if b==0xcd then return uint(2) end
    if b==0xce then return uint(4) end
    if b==0xd0 then local v=uint(1);return v>=128 and v-256 or v end
    if b==0xd1 then local v=uint(2);return v>=32768 and v-65536 or v end
    if b==0xd2 then local v=uint(4);return v>=2147483648 and v-4294967296 or v end
    if b==0xd9 then return read(uint(1)) end
    if b==0xda then return read(uint(2)) end
    if b==0xdb then return read(uint(4)) end
    if b==0xdc then
      local n=uint(2);local arr={}
      for i=1,n do arr[i]=parse(depth+1) end
      return arr
    end
    if b==0xde then
      local n=uint(2);local o={}
      for _=1,n do
        local k=parse(depth+1)
        assert(k~=M.null and k~=nil,"null map key")
        o[k]=parse(depth+1)
      end
      return M.map(o)
    end
    if b==0xcb then return decodeFloat64(uint(4),uint(4)) end
    error(string.format("unsupported msgpack prefix 0x%02x",b))
  end
  local value=parse(0)
  if pos<=#data then error("trailing msgpack bytes") end
  return value
end
return M
