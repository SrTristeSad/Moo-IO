-- Request a genuine single-use guest join ticket from the reconstructed original
-- Node.js API. No alternative transport and no changes to the Node server.
-- Moo IO permits trusted LAN sessions guarded by a room invite code.
-- The inherited boolean CAPTCHA is ONLY a local test stub; do not expose to internet.
local Join={}
local TLS=require("src.net.tls_bridge")
-- Moo IO modification: hosts may be reached from other machines on LAN.
local function validHost(host)
  return type(host)=="string" and host:match("^[%w%.%-]+$")~=nil
end
local function getError(response)
  if type(response)~="string" then return "resposta ausente" end
  return response:match('"error"%s*:%s*"([^"]+)"')
    or response:match('"type"%s*:%s*"([^"]+)"')
    or "resposta recusada"
end
local function encodeId(did)
  if type(did)=="string" and #did>=16 and #did<=64
    and did:match("^[0-9a-f]+$") then
    return ',"did":"'..did..'"'
  end
  return ""
end
function Join.guest(options)
  assert(type(options)=="table","join options required")
  local host=options.host or "127.0.0.1"
  local port=options.port or 8080
  local server=options.server or "LC"
  if not validHost(host) then return nil,"host invalido" end
  if type(port)~="number" or port<1 or port>65535 or port%1~=0 then
    return nil,"porta invalida"
  end
  if type(server)~="string" or not server:match("^[A-Za-z0-9]+$") then
    return nil,"servidor invalido"
  end
  local roomCode=options.inviteCode
  if type(roomCode)~="string" or not roomCode:match("^[%w%-]+$")
    or #roomCode<8 or #roomCode>64 then
    return nil,"codigo de convite invalido"
  end
  local http=options.http or require("socket.http")
  local ltn12=options.ltn12 or require("ltn12")
  local secure=options.secure==true
  local secureOptions
  if secure then
    local why
    secureOptions,why=TLS.options(host,port,options)
    if not secureOptions then return nil,why end
  elseif TLS.validDomain(host) then
    return nil,"Endereco publico exige HTTPS/WSS"
  end
  local hostUrl=(secure and "https://" or "http://")..host..
    (secure and "" or ":"..port).."/s/"..server
  -- The original local API deliberately uses a boolean stand-in for CAPTCHA.
  -- Do not send this to an internet-facing server.
  local auth=""
  if options.authToken~=nil then
    if type(options.authToken)~="string" or
      #options.authToken<12 or #options.authToken>4096 or
      not options.authToken:match("^[%w%._%-]+$") then
      return nil,"token de autenticacao invalido"
    end
    auth=',"auth":"'..options.authToken..'"'
  end
  -- Guest uses the local CAPTCHA stand-in. Authenticated join passes
  -- the same server-issued JWT to Node and does not pretend to be a guest.
  local body='{"host":"'..hostUrl..'","captcha":true'
    ..auth..encodeId(options.did)..'}'
  local chunks={}
  local oldTimeout=http.TIMEOUT
  http.TIMEOUT=4
  local ok,result,status=pcall(http.request,{
    url="http://"..host..":"..port.."/api/join",
    method="POST",
    headers={
      ["Content-Type"]="application/json",
      ["Content-Length"]=tostring(#body),
      ["Connection"]="close",
      ["X-MooIO-Code"]=roomCode
    },
    source=ltn12.source.string(body),
    sink=ltn12.sink.table(chunks),
    create=secureOptions and secureOptions.create or nil
  })
  http.TIMEOUT=oldTimeout
  if not ok then return nil,"API join falhou: "..tostring(result) end
  if not result then return nil,"API join indisponivel: "..tostring(status) end
  local response=table.concat(chunks)
  local code=tonumber(status)
  if code~=200 then
    return nil,"API /api/join HTTP "..tostring(status)..": "..getError(response)
  end
  if #response>8192 then return nil,"resposta do ticket muito grande" end
  local ticket=response:match('"ticket"%s*:%s*"([0-9a-f]+)"')
  local did=response:match('"did"%s*:%s*"([0-9a-f]+)"')
  if not ticket or #ticket~=36 or not did or #did<16 or #did>64 then
    return nil,"/api/join nao retornou um ticket e device ID validos"
  end
  return {ticket=ticket,did=did,host=hostUrl}
end
return Join
