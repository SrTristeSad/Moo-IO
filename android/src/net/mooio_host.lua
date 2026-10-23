-- Android: in-process Node.js mobile server started by MooIOActivity.
-- Never claim a room is ready without the live native Node control endpoint.
local Host={}
Host.__index=Host
local function getSessionCode()
  -- Stored in the app's private internal files by MooIOActivity. Not a fake room.
  local f=io.open("/data/data/io.srtristesad.mooio/files/mooio-host/room-code.txt","rb")
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
  return host
end
function Host.new()
  return setmetatable({state="idle",code="",address="",port=8080,
    hostIP="",mode="lan",elapsed=0,check=0,error=nil,progress="",lastLog=""},Host)
end
function Host:start(mode,requestedIP,requestedBots)
  if self.state=="starting" or self.state=="ready" then
    return false,"Sala local ja aberta."
  end
  self.state="starting"
  self.error=nil;self.elapsed=0;self.check=0
  self.progress="Verificando servidor Node.js integrado ao Android..."
  return true
end
function Host:update(dt)
  if self.state~="starting" then return end
  self.elapsed=self.elapsed+(dt or 0)
  self.check=self.check+(dt or 0)
  if self.check<.7 then return end
  self.check=0
  local ip=getStatus()
  local code=getSessionCode()
  if ip and code then
    self.hostIP=ip
    self.code=code
    self.address=ip..":"..self.port
    self.state="ready"
    self.progress="Servidor Android pronto. Pode jogar offline."
    return
  end
  if self.elapsed>25 then
    self.state="failed"
    self.error="Node.js integrado nao iniciou. Veja o log MooIO-Host no Android."
  end
end
function Host:stop()
  -- Node.js is hosted inside the Android app and remains active until app exits.
  -- node::Start cannot safely be restarted in the same process.
  self.state="idle";self.code="";self.address="";self.hostIP=""
  self.error=nil;self.progress=""
end
return Host
