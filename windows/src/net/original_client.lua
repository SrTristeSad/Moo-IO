-- DIRECT client of the original al007ex/moomoo-clone WebSocket endpoint.
-- The reconstructed Node game logic is unchanged (a missing local config
-- file can be added by the Windows installer). No custom TCP gateway.
-- Uses the original /api/join ticket, pinned authenticated transport, and
-- original spawn messages. Browser-specific bundle seal still unsupported.
local SocketWS=require("src.net.websocket_client")
local Bootstrap=require("src.protocol.bootstrap")
local Random=require("src.net.secure_random")
local Build=require("src.protocol.original_build")
local OriginalSession=require("src.protocol.original_session")
local Join=require("src.net.original_join")
local TLS=require("src.net.tls_bridge")
local MessagePack=require("src.protocol.msgpack")
local Original={}
Original.__index=Original

local function validHost(h)
  return type(h)=="string" and h:match("^[%w%.%-]+$")~=nil
end
local function validPort(n)
  return type(n)=="number" and n>=1 and n<=65535 and n%1==0
end
local function httpPing(socketHttp,host,port,secure)
  local opts
  if secure then
    local why;opts,why=TLS.options(host,port)
    if not opts then return nil,why end
  end
  local oldTimeout=socketHttp.TIMEOUT
  socketHttp.TIMEOUT=2
  local data,code
  if opts then
    local ltn12=require("ltn12")
    local chunks={}
    local ok,result,status=pcall(socketHttp.request,{
      url="http://"..host..":443/ping",method="GET",
      create=opts.create,sink=ltn12.sink.table(chunks)
    })
    if ok and result then data=table.concat(chunks);code=status
    else data=nil;code=tostring(status or result) end
  else
    local ok,result,status=pcall(socketHttp.request,
      "http://"..host..":"..port.."/ping")
    if ok then data=result;code=status else data=nil;code=tostring(result) end
  end
  socketHttp.TIMEOUT=oldTimeout
  if tonumber(code)~=200 then return nil,"GET /ping HTTP "..tostring(code) end
  if type(data)~="string" or #data>32768 then return nil,"resposta /ping invalida" end
  local build=data:match('"build"%s*:%s*"([%w]+)"')
  if not build or #build>100 then return nil,"identificador do build ausente no /ping" end
  return build
end
function Original.new(options)
  options=options or {}
  local socketHttp=options.http or require("socket.http")
  return setmetatable({
    host=options.host or "127.0.0.1",port=options.port or 8080,
    server=options.server or "LC",inviteCode=options.inviteCode,
    name=options.name or "Jogador",
    autoSpawn=options.autoSpawn~=false,
    authToken=options.authToken,
    secure=options.secure==true,
    join=options.join or Join,
    ltn12=options.ltn12,
    did=nil,ticket=nil,spawnSent=false,sid=nil,packetCount=0,
    http=socketHttp,random=options.random or Random.bytes,
    sha1=options.sha1 or function(data) return love.data.hash("sha1",data) end,
    socketLib=options.socket,
    state="idle",status="Servidor original ainda nao conectado.",
    error=nil,build=nil,handshake=nil,session=nil,websocket=nil,events={}
  },Original)
end
function Original:connect()
  if not validHost(self.host) or not validPort(self.port) then
    self.state="failed";self.error="Endereco local invalido"
    return false,self.error
  end
  if not self.server:match("^[%w]+$") then
    self.state="failed";self.error="Servidor de jogo invalido"
    return false,self.error
  end
  self:close()
  if self.secure and (not TLS.validDomain(self.host) or self.port~=443) then
    return false,"Servidor publico exige HTTPS DNS na porta 443"
  end
  if not self.secure and TLS.validDomain(self.host) then
    return false,"Nao e permitido conectar a servidor publico sem TLS"
  end
  local build,reason=httpPing(self.http,self.host,self.port,self.secure)
  if not build then
    self.state="failed";self.error=reason
    self.status="Servidor original indisponivel: "..reason
    return false,reason
  end
  self.build=build
  -- /api/join is the exact API used by the author's local client. Its guest
  -- CAPTCHA is an explicit local stand-in (boolean), not an internet service.
  -- One fresh, single-use ticket is required for every WebSocket attempt.
  local grant,joinError=self.join.guest({
    host=self.host,port=self.port,server=self.server,did=self.did,
    inviteCode=self.inviteCode,
    authToken=self.authToken,
    secure=self.secure,
    http=self.http,ltn12=self.ltn12
  })
  if not grant then
    self.state="failed"
    self.error=joinError
    self.status="Servidor recusou ingresso guest: "..tostring(joinError)
    return false,joinError
  end
  self.ticket=grant.ticket
  self.did=grant.did
  self.spawnSent=false
  self.sid=nil
  self.packetCount=0
  local options={secureRandom=self.random,sha1=self.sha1,secure=self.secure}
  if self.secure then
    local transport,transportError=TLS.options(self.host,self.port)
    if not transport then return false,transportError end
    options.socket=transport.socket
  end
  if self.socketLib then options.socket=self.socketLib end
  local ws=SocketWS.new(options)
  -- Keep ?b= bound to /ping and supply the authentic one-use join ticket.
  -- ?u= is needed only when the optional official JS bundle exists; the
  -- Lua client does not impersonate or copy the official browser bundle.
  local path="/s/"..self.server.."?b="..build.."&token=tk:"..grant.ticket
  local ok,err=ws:connect(self.host,self.port,path)
  if not ok then
    self.state="failed";self.error=err
    self.status="Falha no WebSocket original: "..tostring(err)
    return false,err
  end
  self.websocket=ws
  self.state="connecting"
  self.error=nil
  self.status="Ticket da sala emitido; abrindo WebSocket..."
  -- Do not print URLs containing the secret single-use ticket.
  return true
end
function Original:update()
  local ws=self.websocket
  if not ws then return end
  ws:update()
  for _,evt in ipairs(ws:drain()) do
    if evt.kind=="open" then
      self.state="waiting_handshake"
      self.status="WebSocket original aberto; aguardando io-init..."
    elseif evt.kind=="binary" then
      if not self.handshake then
        local handshake,err=Bootstrap.decodeHandshake(evt.value)
        if not handshake then
          self.state="failed"
          self.error="Handshake original invalido: "..tostring(err)
          self.status=self.error
          ws:close()
        else
          self.handshake=handshake
          self.state="handshake_received"
          self.events[#self.events+1]={kind="io-init",data=handshake}
          local params,buildError=Build.load(self.build,{host=self.host,port=self.port,secure=self.secure})
          if handshake.pinned and not params then
            self.state="blocked"
            self.error=tostring(buildError)
            self.status="Build do protocolo indisponivel: "..self.error
          elseif handshake.pinned and params.buildId~=self.build then
            self.state="blocked"
            self.status="Build local diferente do servidor remoto; parametros rejeitados."
          else
            local session,sessionError=OriginalSession.new(handshake,params,
              function(data) return love.data.hash("sha256",data) end)
            if not session then
              self.state="blocked"
              self.status="Sessao original indisponivel: "..tostring(sessionError)
            else
              self.session=session
              self.state="keyed_transport"
              self.status="Handshake original aceito; aguardando Play no cliente Lua."
              if self.autoSpawn then
                local okSpawn,spawnErr=self:spawn()
                if not okSpawn then
                  self.state="failed"
                  self.error="Spawn nao enviado: "..tostring(spawnErr)
                  self.status=self.error
                end
              end
            end
          end
        end
      elseif self.session then
        local packet,err=self.session:decode(evt.value)
        if not packet then
          self.state="failed"
          self.error=tostring(err)
          self.status="Erro no pacote do servidor original: "..self.error
          ws:close()
        else
          self.packetCount=self.packetCount+1
          self.events[#self.events+1]={kind="game_packet",data=packet}
          if packet.name=="q" and self.session then
            local salt=packet.args[1]
            local probes=packet.args[2]
            -- The local original-server compatibility config sends zero
            -- browser-specific probes. Answer an EMPTY round accurately;
            -- do not pretend a Lua client passed browser integrity probes.
            if type(salt)=="number" and type(probes)=="table"
              and #probes==0 and self.session.sealMode==0 then
              local seq=self.session.sent
              local ledger=self.session.ledger
              local valid,why=self:send("T",{
                0,0,0,MessagePack.null,salt,seq,ledger
              })
              if not valid then
                self.status="Falha ao responder telemetria original: "..tostring(why)
              end
            else
              self.status="Servidor exige probes/selagem do navegador ainda nao implementados em Lua."
              self.state="blocked"
            end
          end
          if packet.name=="C" and type(packet.args[1])=="number" then
            self.sid=packet.args[1]
            self.state="spawn_confirmed"
            self.status="Spawn confirmado pelo servidor Node original! ID "..tostring(self.sid)
          elseif packet.name=="B" then
            self.status="Servidor enviou desconexao: "..tostring(packet.args[1])
          end
        end
      else
        self.events[#self.events+1]={kind="encrypted_frame",length=#evt.value}
      end
    elseif evt.kind=="close" then
      self.state="closed"
      local raw=evt.value
      local code=type(raw)=="string" and #raw>=2 and (raw:byte(1)*256+raw:byte(2)) or nil
      local descriptions={
        [4001]="ticket, banimento, limite de conexoes ou politica do servidor",
        [4002]="versao do build ou bundle nao corresponde ao servidor",
        [4003]="servidor exige conta autenticada",
        [4004]="origem WebSocket nao aceita"
      }
      local description=code and descriptions[code] or "conexao encerrada"
      self.status="Servidor original fechou WebSocket: "..(code and tostring(code) or "?").." - "..description
      self.error=self.status
    elseif evt.kind=="error" then
      self.state="failed"
      self.error=tostring(evt.value)
      self.status="Erro no WebSocket original: "..self.error
    end
  end
  if ws.state=="closed" and self.state~="closed" and self.state~="failed" then
    self.state="closed"
    self.status="Conexao original fechada antes de entrar no jogo."
  end
end
-- The reference browser connects first and sends M only after Play.
-- Existing old callers preserve autoSpawn=true by default.
function Original:spawn(profile)
  if self.spawnSent and self.state~="spawn_confirmed" then
    return false,"spawn already requested"
  end
  if not self.session or not self.websocket or self.websocket.state~="open" then
    return false,"servidor ainda nao concluiu o handshake autenticado"
  end
  profile=profile or {}
  local name=type(profile.name)=="string" and profile.name or self.name
  local skin=type(profile.skin)=="number" and math.floor(profile.skin) or 0
  skin=math.max(0,math.min(9,skin))
  local request=MessagePack.map({
    name=name:sub(1,15),
    moofoll=profile.moofoll==true,
    skin=skin,
    anon=profile.anon==true
  })
  local success,err=self:send("M",{request})
  if success then
    self.name=name
    self.spawnSent=true
    self.state="joining"
    self.status="Entrada solicitada ao Node; aguardando confirmacao C..."
  end
  return success,err
end
function Original:send(name,args)
  if not self.session or not self.websocket or self.websocket.state~="open" then
    return false,"original session not authenticated"
  end
  local frame,err=self.session:encode(name,args)
  if not frame then return false,err end
  return self.websocket:send(frame,2)
end
function Original:drain()
  local events=self.events
  self.events={}
  return events
end
function Original:close()
  if self.websocket then self.websocket:close() end
  self.websocket=nil
  self.handshake=nil
  self.session=nil
  self.spawnSent=false
  self.ticket=nil
  self.events={}
end
return Original
