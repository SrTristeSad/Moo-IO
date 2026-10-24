-- HTTP WebSocket upgrade helpers for LuaSocket-based adapters.
-- Key generation must use cryptographically secure bytes from the caller.
local M={}
local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64(data)
  local out={}
  for i=1,#data,3 do
    local a,b,c=data:byte(i,i+2)
    local n=a*65536+(b or 0)*256+(c or 0)
    local x=math.floor(n/262144)%64
    local y=math.floor(n/4096)%64
    local z=math.floor(n/64)%64
    local w=n%64
    out[#out+1]=alphabet:sub(x+1,x+1)..alphabet:sub(y+1,y+1)
      ..(b and alphabet:sub(z+1,z+1) or "=")
      ..(c and alphabet:sub(w+1,w+1) or "=")
  end
  return table.concat(out)
end
M.base64=base64
function M.request(host,port,path,key,origin,secure)
  assert(type(host)=="string" and host:match("^[%w%.%-]+$"),"invalid host")
  assert(type(port)=="number" and port%1==0 and port>=1 and port<=65535,"invalid port")
  assert(type(path)=="string" and path:sub(1,1)=="/" and not path:find("[\r\n]"),"invalid path")
  assert(type(key)=="string" and #key==24 and key:match("^[%w%+/%=]+$"),"invalid websocket key")
  if secure then assert(port==443,"WSS requires port 443") end
  local authority=secure and host or host..":"..port
  local expectedOrigin=(secure and "https://" or "http://")..authority
  origin=origin or expectedOrigin
  assert(origin==expectedOrigin,"origin must match server authority")
  return table.concat({
    "GET "..path.." HTTP/1.1",
    "Host: "..authority,
    "Upgrade: websocket",
    "Connection: Upgrade",
    "Sec-WebSocket-Key: "..key,
    "Sec-WebSocket-Version: 13",
    "Origin: "..origin,
    "",""
  },"\r\n")
end
function M.expectedAccept(key,sha1binary)
  assert(type(sha1binary)=="function","SHA-1 digest function required")
  local digest=sha1binary(key.."258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
  assert(type(digest)=="string" and #digest==20,"SHA-1 must return 20 binary bytes")
  return base64(digest)
end
function M.validateResponse(header,expected)
  if type(header)~="string" or #header>16384 then return false,"invalid response size" end
  if not header:match("^HTTP/1%.[01] 101[ \r\n]") then return false,"server did not switch protocols" end
  local fields={}
  for line in header:gmatch("\r\n([^\r\n]+)") do
    local k,v=line:match("^([^:]+):%s*(.-)%s*$")
    if k then fields[k:lower()]=v end
  end
  if not fields.upgrade or fields.upgrade:lower()~="websocket" then return false,"missing websocket upgrade" end
  if not fields.connection or not fields.connection:lower():find("upgrade",1,true) then return false,"missing connection upgrade" end
  if fields["sec-websocket-accept"]~=expected then return false,"invalid websocket accept" end
  return true
end
return M
