-- SPDX-License-Identifier: AGPL-3.0-only
-- Hidden Windows Node host, driven from the native LÖVE client.
local SecureRandom=require("src.net.secure_random")
local Network=require("src.net.mooio_network")
local Paths=require("src.net.mooio_paths")
local Host={}
Host.__index=Host
local ffiOK,ffi=pcall(require,"ffi")
local win=(ffiOK and ffi.os=="Windows")
local kernel
if win then
  ffi.cdef[[
  typedef void *HANDLE;
  typedef unsigned long DWORD;
  typedef int BOOL;
  typedef unsigned short WORD;
  typedef struct {
    DWORD cb;
    char* lpReserved;
    char* lpDesktop;
    char* lpTitle;
    DWORD dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars;
    DWORD dwFillAttribute, dwFlags;
    WORD wShowWindow, cbReserved2;
    unsigned char* lpReserved2;
    HANDLE hStdInput, hStdOutput, hStdError;
  } STARTUPINFOA;
  typedef struct {
    HANDLE hProcess, hThread;
    DWORD dwProcessId, dwThreadId;
  } PROCESS_INFORMATION;
  BOOL CreateProcessA(const char*,char*,void*,void*,BOOL,DWORD,void*,const char*,STARTUPINFOA*,PROCESS_INFORMATION*);
  BOOL SetEnvironmentVariableA(const char*,const char*);
  DWORD GetEnvironmentVariableA(const char*,char*,DWORD);
  BOOL CloseHandle(HANDLE);
  BOOL TerminateProcess(HANDLE,unsigned int);
  DWORD GetLastError(void);
  DWORD WaitForSingleObject(HANDLE,DWORD);
  ]]
  kernel=ffi.load("kernel32")
end
local function hex(data)
  return (data:gsub(".",function(ch) return string.format("%02x",ch:byte()) end))
end
local function getenv(key)
  local buf=ffi.new("char[4096]")
  local n=kernel.GetEnvironmentVariableA(key,buf,4096)
  return n>0 and n<4096 and ffi.string(buf,n) or nil
end
local function setenv(key,value)
  kernel.SetEnvironmentVariableA(key,value)
end
local function localAddress()
  local ok,socket=pcall(require,"socket")
  if not ok then return nil end
  local udp=socket.udp()
  if not udp then return nil end
  udp:settimeout(0)
  udp:setpeername("192.0.2.1",9) -- route lookup only; no packet is sent
  local ip=udp:getsockname()
  udp:close()
  if type(ip)=="string" and ip~="0.0.0.0" and ip~="127.0.0.1" then return ip end
  local hostname=socket.dns.gethostname()
  local resolved=hostname and socket.dns.toip(hostname)
  if resolved and resolved~="127.0.0.1" then return resolved end
  return nil
end
local function ping(port)
  local ok,http=pcall(require,"socket.http")
  if not ok then return false end
  local old=http.TIMEOUT
  http.TIMEOUT=0.35
  local good,body,code=pcall(http.request,"http://127.0.0.1:"..(port+1).."/status")
  http.TIMEOUT=old
  return good and tonumber(code)==200 and type(body)=="string"
    and body:find('"project"%s*:%s*"Moo%-IO"')~=nil
end
function Host.new()
  return setmetatable({
    state="idle",code="",address="",port=8080,hostIP="",mode="lan",
    elapsed=0,check=0,process=nil,error=nil,progress="",lastLog="",root=nil
  },Host)
end
function Host:start(mode,requestedIP,requestedBots)
  if self.state=="starting" or self.state=="ready" then return false,"Sala ja iniciada" end
  if not win then return false,"Hospedagem automatica disponivel inicialmente no Windows." end
  if ping(self.port) then return false,"Ja existe uma sala Moo IO nesta porta." end
  local root,reason=Paths.find(love.filesystem)
  if not root then return false,reason end
  local script=Paths.script(root)
  self.root=root
  mode=mode=="vpn" and "vpn" or "lan"
  local ip=mode=="vpn" and requestedIP or localAddress()
  if not Network.accept(ip,mode) then
    return false,mode=="vpn"
      and "Informe o IPv4 valido exibido pelo aplicativo VPN (nao IP publico)."
      or "Endereco LAN invalido. Verifique o Wi-Fi ou cabo."
  end
  self.hostIP=ip;self.mode=mode
  self.code=hex(SecureRandom.bytes(8))
  self.address=ip..":"..self.port
  self.elapsed=0;self.check=0;self.error=nil
  self.progress="Preparando sala..."
  self.lastLog=""
  requestedBots=tonumber(requestedBots) or 0
  if requestedBots<0 or requestedBots>8 or requestedBots%1~=0 then
    return false,"Quantidade de bots invalida (0 a 8)."
  end
  local keys={"MOO_IO_ROOM_CODE","MOO_IO_GUI_HOST","MOO_IO_BIND_IP","MOO_IO_NETWORK_MODE","MOO_IO_BOT_COUNT"}
  local originals={}
  for _,key in ipairs(keys) do originals[key]=getenv(key) end
  setenv(keys[1],self.code)
  setenv(keys[2],"1")
  setenv(keys[3],ip)
  setenv(keys[4],mode)
  setenv(keys[5],tostring(requestedBots))
  local command='powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'..script..'"'
  local cmd=ffi.new("char[?]",#command+1,command)
  local startup=ffi.new("STARTUPINFOA[1]")
  startup[0].cb=ffi.sizeof("STARTUPINFOA")
  startup[0].dwFlags=1 -- STARTF_USESHOWWINDOW
  startup[0].wShowWindow=0 -- SW_HIDE
  local info=ffi.new("PROCESS_INFORMATION[1]")
  local launched=kernel.CreateProcessA(nil,cmd,nil,nil,0,0x08000000,nil,root,startup,info)
  local lastError=launched==0 and tonumber(kernel.GetLastError()) or 0
  for _,key in ipairs(keys) do setenv(key,originals[key]) end
  if launched==0 then return false,"Nao foi possivel iniciar o Node (Windows "..lastError..")" end
  kernel.CloseHandle(info[0].hThread)
  self.process=info[0].hProcess
  self.state="starting"
  return true
end
function Host:update(dt)
  if self.state~="starting" then return end
  self.elapsed=self.elapsed+dt
  self.check=self.check+dt
  if self.check>=0.6 then
    self.check=0
    if ping(self.port) then self.state="ready";self.progress="Sala pronta.";return end
    local path=Paths.log(self.root or "")
    local log=io.open(path,"rb")
    if log then
      local len=log:seek("end") or 0
      log:seek("set",math.max(0,len-1800))
      local content=log:read("*a") or ""
      log:close()
      content=content:gsub("\r",""):gsub("\27%[[%d;]*m","")
      local lines={}
      for line in content:gmatch("[^\n]+") do
        if #line>110 then line=line:sub(1,107).."..." end
        lines[#lines+1]=line
      end
      local selected={}
      for i=math.max(1,#lines-4),#lines do selected[#selected+1]=lines[i] end
      self.lastLog=table.concat(selected,"\n")
      if content:find("MOOIO_PHASE_STARTING",1,true) then
        self.progress="Iniciando servidor Node.js..."
      end
      local reason=content:match("MOOIO_PHASE_ERROR%s+([^\n]+)")
      if reason then
        reason=reason:gsub("%z",""):gsub("%s+$","")
        self.progress=reason~="" and reason
          or "Falha ao iniciar o servidor local. Verifique o log."
      end
    end
    if self.process and kernel.WaitForSingleObject(self.process,0)==0 then
      self.state="failed"
      self.error=self.progress.. " (server/data/mooio-host.log)"
      kernel.CloseHandle(self.process)
      self.process=nil
      return
    end
  end
  if self.elapsed>90 then
    self.state="failed"
    self.error="Servidor nao iniciou. Confira server/data/mooio-host.log"
    if self.process then kernel.TerminateProcess(self.process,1);kernel.CloseHandle(self.process);self.process=nil end
  end
end
function Host:stop()
  local wasReady=self.state=="ready"
  if wasReady then
    local ok,http=pcall(require,"socket.http")
    local okLTN,ltn12=pcall(require,"ltn12")
    if ok and okLTN then
      local old=http.TIMEOUT
      http.TIMEOUT=1
      pcall(http.request,{
        url="http://127.0.0.1:"..(self.port+1).."/shutdown",
        method="POST",
        headers={["X-MooIO-Code"]=self.code,["Content-Length"]="0"},
        source=ltn12.source.empty(),sink=ltn12.sink.null()
      })
      http.TIMEOUT=old
    end
  end
  if self.process then
    -- A graceful /shutdown request can fail (adapter/firewall/closed
    -- control port). Never report "room closed" while keeping the
    -- child Node server running in the background.
    if not wasReady or kernel.WaitForSingleObject(self.process,1500)~=0 then
      kernel.TerminateProcess(self.process,1)
      kernel.WaitForSingleObject(self.process,500)
    end
    kernel.CloseHandle(self.process)
    self.process=nil
  end
  self.state="idle";self.code="";self.address="";self.hostIP=""
end
return Host
