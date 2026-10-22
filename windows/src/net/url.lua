-- URL construction for a local server under the user's control.
-- This module does not open sockets or bypass any server-side checks.
local M={}
local function enc(s)
  return tostring(s):gsub("([^%w%-_%.~])",function(c) return string.format("%%%02X",string.byte(c)) end)
end
function M.build(host,port,server,params)
  assert(type(host)=="string" and host:match("^[%w%.%-]+$"),"invalid host")
  assert(type(port)=="number" and port>=1 and port<=65535 and port%1==0,"invalid port")
  assert(type(server)=="string" and server:match("^[%w%-]+$"),"invalid server")
  local keys={}
  for k,v in pairs(params or {}) do
    if v~=nil then keys[#keys+1]=k end
  end
  table.sort(keys)
  local q={}
  for _,k in ipairs(keys) do
    q[#q+1]=enc(k).."="..enc(params[k])
  end
  return "ws://"..host..":"..port.."/s/"..server..(#q>0 and "?"..table.concat(q,"&") or "")
end
return M
