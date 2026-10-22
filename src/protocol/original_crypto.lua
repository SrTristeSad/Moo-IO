-- Original protocol arithmetic and tables (no server changes).
-- Port of public al007ex/moomoo-clone@06f7c1c protocol/crypto.js and
-- protocol/build.js. Runs on LuaJIT (LÖVE) and plain Lua 5.4.
local Constants=require("src.protocol.constants")
local M={}
local MOD=4294967296
local function u32(x) return x%MOD end
local ok,bitlib=pcall(require,"bit")
if not ok then bitlib=bit32 end
local function binaryFallback(a,b,operation)
  a=u32(a);b=u32(b)
  local result,p=0,1
  for _=1,32 do
    local x,y=a%2,b%2
    if operation=="xor" and x~=y or operation=="or" and (x==1 or y==1) then
      result=result+p
    elseif operation=="and" and x==1 and y==1 then
      result=result+p
    end
    a=math.floor(a/2);b=math.floor(b/2);p=p*2
  end
  return result
end
function M.bxor(a,b)
  if bitlib then return u32(bitlib.bxor(a,b)) end
  return binaryFallback(a,b,"xor")
end
function M.bor(a,b)
  if bitlib then return u32(bitlib.bor(a,b)) end
  return binaryFallback(a,b,"or")
end
function M.band(a,b)
  if bitlib then return u32(bitlib.band(a,b)) end
  return binaryFallback(a,b,"and")
end
function M.rshift(a,b)
  if bitlib then return u32(bitlib.rshift(a,b)) end
  return math.floor(u32(a)/2^b)
end
function M.lshift(a,b)
  if bitlib then return u32(bitlib.lshift(a,b)) end
  return u32(a*2^b)
end
function M.imul(a,b)
  a=u32(a);b=u32(b)
  local a0,a1=a%65536,math.floor(a/65536)
  local b0,b1=b%65536,math.floor(b/65536)
  local low=a0*b0
  local mid=(a1*b0+a0*b1)%65536
  return u32(low+mid*65536)
end
local function add(a,b) return u32(a+b) end
local function sub(a,b) return u32(a-b) end
local function fnvStep(hash,byte)
  return M.imul(M.bxor(hash,byte),16777619)
end
local function fnvFinish(h)
  h=M.bxor(h,M.rshift(h,15))
  h=M.imul(h,739982445)
  h=M.bxor(h,M.rshift(h,12))
  return u32(h)
end
local function hashName(text,salt)
  local h=M.bxor(2166136261,salt)
  for i=1,#text do h=fnvStep(h,text:byte(i)) end
  return fnvFinish(h)
end
function M.mulberry32(seed)
  seed=u32(seed)
  return function()
    seed=add(seed,1831565813)
    local t=M.imul(M.bxor(seed,M.rshift(seed,15)),M.bor(1,seed))
    t=M.bxor(add(t,M.imul(M.bxor(t,M.rshift(t,7)),M.bor(61,t))),t)
    return M.bxor(t,M.rshift(t,14))/MOD
  end
end
local function shuffle(names,seed)
  local values={}
  for i=1,#names do values[i]=i-1 end
  local random=M.mulberry32(seed)
  for i=#names,2,-1 do
    local j=math.floor(random()*i)+1
    values[i],values[j]=values[j],values[i]
  end
  local result={enc={},dec={}}
  for i,name in ipairs(names) do
    result.enc[name]=values[i]
    result.dec[values[i]]=name
  end
  return result
end
local function extend(result,names,base,salt)
  local taken={}
  local span=128-base
  for i=base+1,#names do
    local slot=hashName(names[i],salt)%span
    while taken[slot] do slot=(slot+1)%span end
    taken[slot]=true
    result.enc[names[i]]=base+slot
    result.dec[base+slot]=names[i]
  end
  return result
end
function M.buildTables(seed,salt)
  local legacy=(salt==nil)
  local tableSeed=M.bxor(seed,M.imul(legacy and 1 or salt,2654435761))
  if legacy then
    local c2s,s2c={},{}
    for i=1,17 do c2s[i]=Constants.c2sList[i] end
    for i=1,36 do s2c[i]=Constants.s2cList[i] end
    return {c2s=shuffle(c2s,tableSeed),
      s2c=shuffle(s2c,M.bxor(tableSeed,2246822507))}
  end
  local s2cSeed=M.bxor(tableSeed,2246822507)
  local c2sBase,s2cBase={},{}
  for i=1,22 do c2sBase[i]=Constants.c2sList[i] end
  for i=1,39 do s2cBase[i]=Constants.s2cList[i] end
  return {
    c2s=extend(shuffle(c2sBase,tableSeed),Constants.c2sList,22,tableSeed),
    s2c=extend(shuffle(s2cBase,s2cSeed),Constants.s2cList,39,s2cSeed)
  }
end
local function little32(data,offset)
  local a,b,c,d=data:byte(offset+1,offset+4)
  assert(a and b and c and d,"short u32")
  return a+b*256+c*65536+d*16777216
end
M.readU32LE=little32
function M.hexToBinary(hex)
  assert(type(hex)=="string" and hex:match("^[%da-fA-F]*$") and #hex%2==0)
  return (hex:gsub("..",function(byte) return string.char(tonumber(byte,16)) end))
end
function M.mixKey(rawKey,seed,build)
  assert(#rawKey==16 and type(build)=="table" and #build.constants==8)
  local s={}
  for j=0,7 do
    s[j+1]=M.bxor(build.constants[j+1],
      M.imul(add(seed,M.imul(j+1,2654435769)),2246822519))
  end
  for i=1,#rawKey do
    local j=(i-1)%8
    local n=s[(j+1)%8+1]
    local rotated=M.bor(M.lshift(n,build.rotA),M.rshift(n,32-build.rotA))
    s[j+1]=add(M.imul(M.bxor(s[j+1],rawKey:byte(i)),16777619),rotated)
  end
  for _=1,build.rounds do
    for j=0,7 do
      local a=s[(j+build.tapA)%8+1]
      local b=s[(j+build.tapB)%8+1]
      local rotated=M.bor(M.lshift(b,build.rotB),M.rshift(b,32-build.rotB))
      local mixed=add(s[j+1],M.bxor(a,rotated))
      s[j+1]=M.imul(M.bxor(mixed,M.rshift(mixed,15)),build.mult)
    end
  end
  local out={}
  for j=1,8 do
    local n=s[j]
    for k=0,3 do out[#out+1]=string.char(math.floor(n/256^k)%256) end
  end
  return table.concat(out)
end
function M.deriveMasks(key)
  return {c2s=M.bxor(little32(key,0),3266489909),
    s2c=M.bxor(little32(key,4),668265263)}
end
function M.mask(data,seed)
  local bytes={}
  local state=u32(seed)
  if state==0 then state=1831565813 end
  for i=1,#data,4 do
    state=M.bxor(state,M.lshift(state,13))
    state=M.bxor(state,M.rshift(state,17))
    state=M.bxor(state,M.lshift(state,5))
    for k=0,math.min(3,#data-i) do
      bytes[#bytes+1]=string.char(M.bxor(data:byte(i+k),math.floor(state/256^k)%256))
    end
  end
  return table.concat(bytes)
end
function M.serverMaskSeed(base,count)
  return M.bxor(base,M.imul(count,2654435761))
end
function M.clientMaskSeed(base,tag)
  return M.bxor(base,little32(tag,0))
end
function M.hmacSha256(key,data,digest)
  assert(type(key)=="string" and type(data)=="string")
  assert(type(digest)=="function","sha256 digest required")
  if #key>64 then key=digest(key) end
  assert(#key<=64)
  key=key..string.rep("\0",64-#key)
  local inner,outer={},{}
  for i=1,64 do
    local byte=key:byte(i)
    inner[i]=string.char(M.bxor(byte,0x36))
    outer[i]=string.char(M.bxor(byte,0x5c))
  end
  local innerDigest=digest(table.concat(inner)..data)
  assert(type(innerDigest)=="string" and #innerDigest==32,"invalid SHA256")
  return digest(table.concat(outer)..innerDigest)
end
function M.fnvLedger(hash,data)
  for i=1,#data do hash=fnvStep(hash,data:byte(i)) end
  return hash
end
return M
