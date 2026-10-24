-- SPDX-License-Identifier: AGPL-3.0-only
-- Spawn the packaged Node 22 TLS relay as a hidden child ONLY when public
-- HTTPS/WSS is requested; release it on application exit. No download.
local M={}
local Random=require("src.net.secure_random")
local Paths=require("src.net.mooio_paths")
local ok,ffi=pcall(require,"ffi")
local kernel,handle,secret
if ok and ffi.os=="Windows" then
  pcall(ffi.cdef,[[
    typedef void *HANDLE;
    typedef unsigned long DWORD;
    typedef int BOOL;
    typedef unsigned short WORD;
    typedef struct {
      DWORD cb; char* lpReserved; char* lpDesktop; char* lpTitle;
      DWORD dwX,dwY,dwXSize,dwYSize,dwXCountChars,dwYCountChars;
      DWORD dwFillAttribute,dwFlags; WORD wShowWindow,cbReserved2;
      unsigned char* lpReserved2; HANDLE hStdInput,hStdOutput,hStdError;
    } STARTUPINFOA;
    typedef struct {HANDLE hProcess,hThread; DWORD dwProcessId,dwThreadId;} PROCESS_INFORMATION;
    BOOL CreateProcessA(const char*,char*,void*,void*,BOOL,DWORD,void*,const char*,STARTUPINFOA*,PROCESS_INFORMATION*);
    BOOL SetEnvironmentVariableA(const char*,const char*);
    DWORD GetEnvironmentVariableA(const char*,char*,DWORD);
    BOOL CloseHandle(HANDLE);
    BOOL TerminateProcess(HANDLE,unsigned int);
    DWORD WaitForSingleObject(HANDLE,DWORD);
    DWORD GetLastError(void);
  ]])
  kernel=ffi.load("kernel32")
end
local function hex(s)
  return (s:gsub(".",function(c)return string.format("%02x",c:byte())end))
end
local function getenv(name)
  local buf=ffi.new("char[4096]")
  local count=kernel.GetEnvironmentVariableA(name,buf,4096)
  return count>0 and count<4096 and ffi.string(buf,count) or nil
end
local function file(path)
  local f=io.open(path,"rb")
  if not f then return false end
  f:close();return true
end
function M.start()
  if secret and handle and kernel.WaitForSingleObject(handle,0)~=0 then
    return {port=8469,token=secret}
  end
  if not kernel then return nil,"TLS Windows exige executavel Windows com LuaJIT FFI" end
  local root,err=Paths.find(love and love.filesystem)
  if not root then return nil,err end
  local node=root.."/runtime/node/node.exe"
  local entry=root.."/scripts/tls-relay.mjs"
  if not file(node) or not file(entry) then
    return nil,"Distribuicao Windows incompleta: runtime Node/TLS ausente"
  end
  if root:find('["\r\n]') then return nil,"Caminho do jogo invalido" end
  secret=hex(Random.bytes(24))
  local previous=getenv("MOOIO_TLS_TOKEN")
  kernel.SetEnvironmentVariableA("MOOIO_TLS_TOKEN",secret)
  local command='"'..node..'" "'..entry..'"'
  local cmd=ffi.new("char[?]",#command+1,command)
  local startup=ffi.new("STARTUPINFOA[1]")
  startup[0].cb=ffi.sizeof("STARTUPINFOA")
  startup[0].dwFlags=1
  startup[0].wShowWindow=0
  local info=ffi.new("PROCESS_INFORMATION[1]")
  local created=kernel.CreateProcessA(nil,cmd,nil,nil,0,0x08000000,nil,root,startup,info)
  local errNumber=created==0 and tonumber(kernel.GetLastError()) or 0
  kernel.SetEnvironmentVariableA("MOOIO_TLS_TOKEN",previous)
  if created==0 then secret=nil;return nil,"Nao foi possivel iniciar TLS Windows ("..errNumber..")" end
  kernel.CloseHandle(info[0].hThread)
  handle=info[0].hProcess
  -- Node is ready asynchronously; the calling Lua socket can retry its
  -- localhost connection without weakening TLS verification.
  local socket=require("socket")
  for i=1,20 do
    if kernel.WaitForSingleObject(handle,0)==0 then
      M.stop();return nil,"Processo TLS encerrado inesperadamente"
    end
    local tcp=socket.tcp()
    tcp:settimeout(.2)
    local connected=tcp:connect("127.0.0.1",8469)
    tcp:close()
    if connected then return {port=8469,token=secret} end
    socket.sleep(.1)
  end
  M.stop()
  return nil,"Ponte TLS nao iniciou"
end
function M.stop()
  if handle then
    if kernel.WaitForSingleObject(handle,0)~=0 then
      kernel.TerminateProcess(handle,0)
      kernel.WaitForSingleObject(handle,1500)
    end
    kernel.CloseHandle(handle)
  end
  handle=nil;secret=nil
end
return M
