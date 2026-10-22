-- Cryptographic random bytes for the RFC6455 handshake and masking keys.
-- Never fall back to math.random for protocol secrets.
local R={}
local ok,ffi=pcall(require,"ffi")
if ok then
  ffi.cdef[[
    long BCryptGenRandom(void* hAlgorithm, unsigned char* pbBuffer,
                         unsigned long cbBuffer, unsigned long dwFlags);
  ]]
end
function R.bytes(count)
  assert(type(count)=="number" and count>=1 and count<=1024 and count%1==0)
  if ok and ffi.os=="Windows" then
    local dll=ffi.load("bcrypt")
    local buffer=ffi.new("unsigned char[?]",count)
    local status=dll.BCryptGenRandom(nil,buffer,count,2)
    if status~=0 then error("BCryptGenRandom failed: "..tonumber(status)) end
    return ffi.string(buffer,count)
  end
  local f=io.open("/dev/urandom","rb")
  if not f then error("OS secure random source unavailable") end
  local data=f:read(count)
  f:close()
  if not data or #data~=count then error("OS random source failed") end
  return data
end
return R
