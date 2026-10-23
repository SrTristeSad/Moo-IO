-- Android: the native Node service is started ON DEMAND by the create-room button.
-- Never claim a room is ready without the live native Node control endpoint.
local Host={}
Host.__index=Host
local function getSessionCode()
  -- Stored in the app's private internal files by MooIOActivity. Not a fake room.
  local f=io.open("/data/user/0/io.srtristesad.mooio.beta/files/mooio-host/room-code.txt","rb")
  if not f then return nil end
  local code=f:read("*a");f:close()
  if code and #code>=8 and #code<=64 and code:match("^[%w%-]+$") then
    return code
  end
  return nil
end
local function getStatus()
  local ok,http=pcall(require,"socket.http")
  if not ok then return nil end
  local old=http.TIMEOUT
  http.TIMEOUT=0.4
  local call,body,status=pcall(http.request,"http://127.0.0.1:8081/status")
  http.TIMEOUT=old
  if not call or status~=200 or type(body)~="string" then return nil end
  if not body:find('"project"%s*:%s*"Moo%-IO"') then return nil end
  local host=body:match('"host"%s*:%s*"([%d%.]+)"')
  if not host then return nil end
  local count=body:match('"bots"%s*:%s*(%d+)')
  return host,count and tonumber(count) or nil
end
-- The loopback lifecycle port belongs to the Android LÖVE Activity, not Node.
-- It is only called from the explicit create/stop actions; never in the main
-- render loop. Fail closed rather than displaying a fake ready/hosting state.
local function controlServer(action,requestedBots)
  if action~="start" and action~="stop" then return false end
  local f=io.open("/data/user/0/io.srtristesad.mooio.beta/files/mooio-control-token.txt","rb")
  if not f then return false end
  local token=f:read("*a");f:close()
  if type(token)~="string" or #token~=48 or token:find("[^%x]") then
    return false
  end
  local ok,http=pcall(require,"socket.http")
  if not ok then return false end
  local previous=http.TIMEOUT
  http.TIMEOUT=.75
  local botSuffix=""
  if action=="start" then
    local count=tonumber(requestedBots) or 0
    count=math.max(0,math.min(8,math.floor(count)))
    botSuffix="/"..tostring(count)
  end
  local call,body,status=pcall(http.request,
    "http://127.0.0.1:8082/"..action.."/"..token..botSuffix)
  http.TIMEOUT=previous
  return call and status==200 and
    type(body)=="string" and
    body:find(action=="start" and "started" or "stopped",1,true)~=nil
end
function Host.new(options)
  options=options or {}
  return setmetatable({
    readStatus=options.readStatus or getStatus,
    readSessionCode=options.readSessionCode or getSessionCode,
    controlServer=options.controlServer or controlServer,state="idle",code="",address="",port=8080,
    hostIP="",mode="lan",elapsed=0,check=0,error=nil,progress="",lastLog=""},Host)
end
function Host:start(mode,requestedIP,requestedBots)
  if self.state=="starting" or self.state=="ready" then
    return false,"Sala local ja aberta."
  end
  if not self.controlServer("start",requestedBots) then
    self.state="failed"
    self.error="Nao foi possivel ligar o servidor Android. Verifique o aplicativo."
    return false,self.error
  end
  self.state="starting"
  self.botCount=math.max(0,math.min(8,math.floor(tonumber(requestedBots) or 0)))
  self.error=nil;self.elapsed=0;self.check=0
  self.progress="Ligando o servidor Node.js no celular..."
  return true
end
function Host:update(dt)
  if self.state~="starting" then return end
  self.elapsed=self.elapsed+(dt or 0)
  self.check=self.check+(dt or 0)
  if self.check<.7 then return end
  self.check=0
  local ip,actualBots=self.readStatus()
  local code=self.readSessionCode()
  if ip and code and actualBots~=nil and actualBots~=self.botCount then
    self.controlServer("stop")
    self.state="failed"
    self.error="O servidor iniciou com quantidade diferente de bots."
    return
  end
  if ip and code and actualBots~=nil then
    self.hostIP=ip
    self.code=code
    self.address=ip..":"..self.port
    self.state="ready"
    self.progress="Servidor Android pronto. Pode jogar offline."
    return
  end
  if self.elapsed>25 then
    self.controlServer("stop") -- do not leave a broken foreground service running
    self.state="failed"
    self.error="Node.js integrado nao iniciou. Veja o log MooIO-Host no Android."
  end
end
function Host:stop()
  -- Native STOP closes the Android foreground service. Its isolated Node
  -- process is killed and Android removes the notification and frees RAM.
  local wasActive=self.state=="ready" or self.state=="starting"
  if wasActive and not self.controlServer("stop") then
    self.state="failed"
    self.error="Nao foi possivel confirmar o encerramento do servidor Android."
    return false,self.error
  end
  self.state="idle";self.code="";self.address="";self.hostIP="";self.botCount=0
  self.error=nil;self.progress=""
  return true
end
return Host
