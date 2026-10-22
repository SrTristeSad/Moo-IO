-- Existing reconstructed Node /api/auth/code and /api/auth/verify API.
-- IMPORTANT: the server is a LOCAL EMULATOR; it accepts ANY six digits.
-- This is NOT password authentication, email delivery or secure registration.
-- Keep it on localhost, never advertise these accounts as production security.
local Auth={}
local Json=require("src.net.json")
local function isLocal(host)
  return host=="127.0.0.1" or host=="localhost"
end
local function escapeJSON(value)
  assert(type(value)=="string","JSON string required")
  return '"'..value:gsub('[%z\1-\31\\"]',function(ch)
    if ch=='\\' then return '\\\\' end
    if ch=='"' then return '\\"' end
    return string.format('\\u%04x',ch:byte())
  end)..'"'
end
local function request(route,payload,options)
  options=options or {}
  local host,port=options.host or "127.0.0.1",options.port or 8080
  if not isLocal(host) or type(port)~="number" or port<1 or port>65535 then
    return nil,"autenticacao local disponivel apenas em localhost"
  end
  local http=options.http or require("socket.http")
  local ltn12=options.ltn12 or require("ltn12")
  local body,encodingError=Json.encode(payload)
  if not body then return nil,"JSON invalido: "..tostring(encodingError) end
  local chunks={}
  local oldTimeout=http.TIMEOUT
  http.TIMEOUT=4
  local ok,result,status=pcall(http.request,{
    url="http://"..host..":"..port.."/api/"..route,
    method="POST",
    headers={
      ["Content-Type"]="application/json",
      ["Content-Length"]=tostring(#body),
      ["Connection"]="close"
    },
    source=ltn12.source.string(body),
    sink=ltn12.sink.table(chunks)
  })
  http.TIMEOUT=oldTimeout
  if not ok then return nil,"API de conta indisponivel: "..tostring(result) end
  if not result then return nil,"API de conta nao respondeu: "..tostring(status) end
  local response=table.concat(chunks)
  -- The original permanent-clan API allows up to 80 members plus
  -- history/stats; JSON for that screen can exceed the login's 16 KiB.
  local maxResponse=route:sub(1,5)=="clan/" and 131072 or 16384
  if #response>maxResponse then return nil,"resposta de conta muito grande" end
  if tonumber(status)~=200 then
    local kind=response:match('"type"%s*:%s*"([^"]+)"')
      or response:match('"error"%s*:%s*"([^"]+)"')
    return nil,"API de conta HTTP "..tostring(status).." "..tostring(kind or "")
  end
  return response
end
function Auth.validEmail(value)
  if type(value)~="string" or #value<3 or #value>120 then return false end
  if value:find("[%c%s]") then return false end
  return value:match("^[^@]+@[^@]+%.[^@]+$")~=nil
end
function Auth.requestCode(email,options)
  if not Auth.validEmail(email) then return nil,"Informe um email valido (ate 120 caracteres)" end
  local response,err=request("auth/code",{email=email},options)
  if not response then return nil,err end
  local flow=response:match('"flow"%s*:%s*"([a-f0-9]+)"')
  if not flow or #flow~=24 then return nil,"Servidor nao retornou fluxo de conta valido" end
  return {flow=flow,email=email}
end
function Auth.verifyCode(flow,code,options)
  if type(flow)~="string" or #flow~=24 or not flow:match("^[a-f0-9]+$") then
    return nil,"Fluxo local de conta invalido"
  end
  if type(code)~="string" or not code:match("^%d%d%d%d%d%d$") then
    return nil,"O codigo precisa conter seis digitos"
  end
  local response,err=request("auth/verify",{flow=flow,code=code},options)
  if not response then return nil,err end
  local token=response:match('"token"%s*:%s*"([%w%._%-]+)"')
  local id=response:match('"id"%s*:%s*"([a-f0-9]+)"')
  if not token or #token>4096 or not id then
    return nil,"Servidor nao retornou token de conta valido"
  end
  return {token=token,id=id}
end
local function tokenValid(token)
  return type(token)=="string" and #token>=12 and #token<=4096
    and token:match("^[%w%._%-]+$")~=nil
end
local allowedClanActions={
  mine=true,create=true,request=true,answer=true,invite=true,
  decide=true,kick=true,role=true,requests=true,uninvite=true,
  leave=true,disband=true
}
local function apiJSON(route,payload,options)
  local response,err=request(route,payload,options)
  if not response then return nil,err end
  local data,jsonError=Json.decode(response)
  if not data or type(data)~="table" then
    return nil,"API retornou JSON incorreto: "..tostring(jsonError)
  end
  return data
end
function Auth.claimName(token,name,options)
  if not tokenValid(token) then return nil,"Token de conta invalido" end
  if type(name)~="string" or #name<3 or #name>15 then
    return nil,"Nome permanente deve ter 3 a 15 caracteres"
  end
  local data,err=apiJSON("name",{auth=token,name=name},options)
  if not data then return nil,err end
  if type(data.name)~="string" then return nil,"Nome nao confirmado pelo Node" end
  return data.name
end
function Auth.clanAction(token,action,body,options)
  if not tokenValid(token) then return nil,"Entre com uma conta local" end
  if type(action)~="string" or not allowedClanActions[action] then
    return nil,"Acao de cla nao permitida"
  end
  if type(body)~="table" and body~=nil then return nil,"Dados invalidos" end
  local payload={auth=token}
  for key,value in pairs(body or {}) do
    if key~="auth" and type(key)=="string" then payload[key]=value end
  end
  return apiJSON("clan/"..action,payload,options)
end
function Auth.clanMine(token,options)
  local data,err=Auth.clanAction(token,"mine",{},options)
  if not data then return nil,err end
  if data.clan~=Json.null and data.clan~=nil and
    (type(data.clan)~="table" or type(data.clan.name)~="string") then
    return nil,"Node retornou dados de cla invalidos"
  end
  return data
end
function Auth.getAccount(token,options)
  if not tokenValid(token) then
    return nil,"Token de conta invalido"
  end
  local response,err=request("account",{auth=token},options)
  if not response then return nil,err end
  local name=response:match('"name"%s*:%s*"([^"]*)"')
  return {name=name or "",raw=response}
end
return Auth
