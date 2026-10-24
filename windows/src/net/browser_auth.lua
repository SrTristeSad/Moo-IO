-- SPDX-License-Identifier: AGPL-3.0-only
-- Browser-hosted login for PRIVATE LAN/VPN V2 rooms only.
-- No email/password in Lua. The room proxies PKCE to the HTTPS hub and
-- returns ONLY a 15-minute room JWT. Do not use plaintext public Internet.
local Json=require("src.net.json")
local Random=require("src.net.secure_random")
local Upgrade=require("src.net.upgrade")
local TLS=require("src.net.tls_bridge")
local M={}

local function privateHost(host)
  if type(host)~="string" then return false end
  local a,b,c,d=host:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  a,b,c,d=tonumber(a),tonumber(b),tonumber(c),tonumber(d)
  if not a or not b or not c or not d or
    a>255 or b>255 or c>255 or d>255 then return false end
  return a==10 or a==127 or a==25 or a==26 or (a==192 and b==168) or
    (a==172 and b>=16 and b<=31) or (a==100 and b>=64 and b<=127 and
      not (b==100 and c==100 and d==100))
end
local function send(host,port,code,route,body,options)
  options=options or {}
  local public=TLS.validDomain(host) and port==443
  if not privateHost(host) and not public then
    return nil,"Login exige IP privado ou dominio HTTPS com certificado valido."
  end
  if type(port)~="number" or port<1 or port>65535 or port%1~=0 or
    type(code)~="string" or #code<8 or #code>64 or
    not code:match("^[A-Za-z0-9%-]+$") then return nil,"Convite invalido" end
  local encoded,encodeError=Json.encode(body)
  if not encoded then return nil,encodeError end
  local http=options.http or require("socket.http")
  local ltn12=options.ltn12 or require("ltn12")
  local secureOptions=nil
  if public then
    local err
    secureOptions,err=TLS.options(host,port,options)
    if not secureOptions then return nil,err end
  end
  local chunks={}
  local previous=http.TIMEOUT
  http.TIMEOUT=1.5
  local ok,response,status=pcall(http.request,{
    url="http://"..host..":"..port.."/api/auth/v2/"..route,
    method="POST",
    headers={
      ["Content-Type"]="application/json",
      ["Content-Length"]=tostring(#encoded),
      ["X-MooIO-Code"]=code,
      ["Connection"]="close"
    },
    source=ltn12.source.string(encoded),
    sink=ltn12.sink.table(chunks),
    create=secureOptions and secureOptions.create or nil
  })
  http.TIMEOUT=previous
  if not ok or not response then return nil,"Servidor de autenticacao indisponivel" end
  local raw=table.concat(chunks)
  if #raw>8192 then return nil,"Resposta de autenticacao muito grande" end
  local data=Json.decode(raw)
  if type(data)~="table" then return nil,"Resposta de autenticacao invalida" end
  local statusCode=tonumber(status)
  if statusCode==202 and route=="token" and data.status=="pending" then
    return nil,"pending"
  end
  if statusCode~=200 then
    return nil,"Falha ao autenticar ("..tostring(statusCode or "?").."): "..
      tostring(data.type or data.error or "acesso recusado")
  end
  return data
end
local function url64(data)
  return (Upgrade.base64(data):gsub("%+","-"):gsub("/","_"):gsub("=",""))
end
function M.begin(host,port,roomCode,options)
  options=options or {}
  local random=options.random or Random.bytes
  local verifier=url64(random(48))
  local digest=options.sha256 and options.sha256(verifier) or
    love.data.hash("sha256",verifier)
  if type(digest)~="string" or #digest~=32 then
    return nil,"SHA-256 seguro indisponivel"
  end
  local challenge=url64(digest)
  local reply,err=send(host,port,roomCode,"start",{challenge=challenge},options)
  if not reply then return nil,err end
  if type(reply.id)~="string" or #reply.id~=40 or
    not reply.id:match("^[0-9a-f]+$") or
    type(reply.verificationUri)~="string" or
    not reply.verificationUri:match("^https://[%w%.%-]+/login%?id="..reply.id.."$") then
    return nil,"O servidor devolveu um endereço de login inseguro"
  end
  return {id=reply.id,verifier=verifier,verificationUri=reply.verificationUri,
    host=host,port=port,code=roomCode,options=options,elapsed=0,
    remaining=tonumber(reply.expiresIn) or 300}
end
function M.poll(state)
  if type(state)~="table" or type(state.id)~="string" then
    return nil,"Autorizacao pendente invalida"
  end
  local reply,err=send(state.host,state.port,state.code,"token",
    {id=state.id,verifier=state.verifier},state.options)
  if not reply then return nil,err end
  if reply.status~="authorized" or type(reply.token)~="string" or
    #reply.token<12 or #reply.token>4096 or
    not reply.token:match("^[%w%._%-]+$") then
    return nil,"Sessao da sala invalida"
  end
  return {token=reply.token,email=reply.email,id=reply.id}
end
return M
