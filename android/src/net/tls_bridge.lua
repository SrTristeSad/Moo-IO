-- SPDX-License-Identifier: AGPL-3.0-only
-- Verified TLS tunnel for public DNS endpoints. The public server only sees
-- HTTPS/WSS (validated by Android JSSE or bundled Windows Node TLS).
-- No insecure certificate fallback. Local LAN continues using LuaSocket.
local M={}
local Port=8469
local tokenPattern="^[a-f0-9]+$"
function M.validDomain(host)
  if type(host)~="string" or host~=host:lower() or #host<4 or #host>253 or
    host:find("[^a-z0-9%.%-]") or host:find("%.%.") or
    host:sub(1,1)=="-" or host:sub(-1)=="." then return false end
  local labels={}
  for label in host:gmatch("[^.]+") do
    if #label<1 or #label>63 or label:sub(1,1)=="-" or
      label:sub(-1)=="-" then return false end
    labels[#labels+1]=label
  end
  if #labels<2 then return false end
  local top=labels[#labels]
  return #top>=2 and #top<=24 and top:match("^[a-z]+$")~=nil
end
local function bridge(options)
  if options and options.bridge then
    return options.bridge
  end
  if love and love.system and love.system.getOS and love.system.getOS()=="Android" then
    local file=io.open("/data/user/0/io.srtristesad.mooio.beta/files/mooio-tls-token.txt","rb")
    if not file then return nil,"Ponte TLS nativa ausente no APK" end
    local token=file:read("*a");file:close()
    if type(token)~="string" or #token~=48 or not token:match(tokenPattern) then
      return nil,"Credencial TLS do Android invalida"
    end
    return {port=Port,token=token}
  end
  local ok,win=pcall(require,"src.net.tls_relay_windows")
  if not ok then return nil,"Runtime TLS Windows nao incluido" end
  return win.start()
end
local function wrap(native,host,securePort,settings)
  local socketSettings={timeout=nil,connected=false}
  local obj={}
  function obj:settimeout(value,...)
    socketSettings.timeout=value
    return native:settimeout(value,...)
  end
  function obj:connect(target,port)
    if socketSettings.connected then return nil,"already connected" end
    local chosen=target or host
    if chosen~=host or port~=securePort then return nil,"Destino TLS nao autorizado" end
    native:settimeout(6)
    local ok,reason=native:connect("127.0.0.1",settings.port)
    if not ok then return nil,"Ponte TLS indisponivel: "..tostring(reason) end
    local secret=settings.token
    local preface="MOOIO-TLS1 "..secret.." "..host.." 443\n"
    local sent,why=native:send(preface)
    if not sent then return nil,"Ponte TLS recusou abertura: "..tostring(why) end
    local reply,err=native:receive("*l")
    if reply~="OK" then return nil,"TLS certificado ou dominio recusado: "..tostring(err or reply) end
    native:settimeout(socketSettings.timeout or 0)
    socketSettings.connected=true
    return 1
  end
  setmetatable(obj,{__index=function(_,key)
    local value=native[key]
    if type(value)=="function" then
      return function(_,...)return value(native,...)end
    end
    return value
  end})
  return obj
end
function M.options(host,port,overrides)
  if not M.validDomain(host) or port~=443 then
    return nil,"Endereço HTTPS público inválido: domínio DNS e porta 443 obrigatórios"
  end
  local relay,err=bridge(overrides)
  if not relay then return nil,err end
  if type(relay.token)~="string" or #relay.token~=48 or
    not relay.token:match(tokenPattern) or type(relay.port)~="number" or
    relay.port<1024 or relay.port>65535 then return nil,"Ponte TLS insegura" end
  local socket=overrides and overrides.socket or require("socket")
  local function create()
    local native,reason=socket.tcp()
    if not native then return nil,reason end
    return wrap(native,host,port,relay)
  end
  return {create=create,socket={tcp=create,select=socket.select},host=host,port=443}
end
function M.stop()
  local ok,win=pcall(require,"src.net.tls_relay_windows")
  if ok and win.stop then win.stop() end
end
return M
