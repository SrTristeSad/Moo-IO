-- Nonblocking ws:// transport for a local server, using LuaSocket.
-- Dependencies injected for testability: socket library, secureRandom(n), sha1(binary).
-- This does not implement the game's authenticated packet protocol.
local Upgrade=require("src.net.upgrade")
local Frames=require("src.net.websocket_frames")
local Client={}
Client.__index=Client
local function pathOK(path)
  return type(path)=="string" and path:sub(1,1)=="/" and not path:find("[\r\n]")
end
function Client.new(options)
  assert(type(options)=="table","options required")
  assert(type(options.secureRandom)=="function","secureRandom required")
  assert(type(options.sha1)=="function","sha1 digest required")
  local socket=options.socket or require("socket")
  return setmetatable({
    socketLib=socket,random=options.secureRandom,sha1=options.sha1,
    state="idle",tcp=nil,out="",input="",events={},error=nil,
    host=nil,port=nil,path=nil,expected=nil,
    maxBuffer=options.maxBuffer or 1048576
  },Client)
end
function Client:emit(kind,value)
  self.events[#self.events+1]={kind=kind,value=value}
end
function Client:drain()
  local events=self.events
  self.events={}
  return events
end
function Client:fail(reason)
  self.error=reason
  self.state="failed"
  if self.tcp then pcall(function() self.tcp:close() end) end
  self.tcp=nil
  self:emit("error",reason)
end
function Client:connect(host,port,path)
  if self.state~="idle" and self.state~="closed" and self.state~="failed" then
    return false,"connection already active"
  end
  assert(type(host)=="string" and host:match("^[%w%.%-]+$"),"invalid host")
  assert(type(port)=="number" and port>=1 and port<=65535 and port%1==0,"invalid port")
  assert(pathOK(path),"invalid path")
  self.host,self.port,self.path=host,port,path
  self.input,self.out,self.events="","",{}
  local nonce=self.random(16)
  assert(type(nonce)=="string" and #nonce==16,"secureRandom must return 16 bytes")
  local key=Upgrade.base64(nonce)
  self.expected=Upgrade.expectedAccept(key,self.sha1)
  local tcp,err=self.socketLib.tcp()
  if not tcp then self:fail(err or "cannot create socket");return false,self.error end
  self.tcp=tcp
  tcp:settimeout(0)
  local ok,connectError=tcp:connect(host,port)
  if not ok and connectError~="timeout" and connectError~="Operation already in progress" and connectError~="already connected" then
    self:fail(connectError or "connect failed")
    return false,self.error
  end
  self.out=Upgrade.request(host,port,path,key)
  self.state=(ok or connectError=="already connected") and "upgrading" or "tcp_connecting"
  return true
end
function Client:send(payload,opcode)
  if self.state~="open" then return false,"websocket not open" end
  local key=self.random(4)
  assert(type(key)=="string" and #key==4,"secureRandom must return four bytes")
  self.out=self.out..Frames.clientFrame(payload,opcode or 2,key)
  return true
end
function Client:close()
  if self.tcp then pcall(function() self.tcp:close() end) end
  self.tcp=nil
  self.state="closed"
  self.out=""
end
function Client:update()
  if not self.tcp then return end
  -- Wait for TCP writability before sending the HTTP upgrade request.
  if self.state=="tcp_connecting" then
    if type(self.socketLib.select)~="function" then self:fail("socket.select required");return end
    local _,writable,selectError=self.socketLib.select(nil,{self.tcp},0)
    if selectError and selectError~="timeout" then self:fail(selectError);return end
    if not writable or #writable==0 then return end
    self.state="upgrading"
  end
  -- Nonblocking LuaSocket send returns (sent, err, last) with indices into supplied string.
  if #self.out>0 then
    local sent,err,last=self.tcp:send(self.out)
    local count=sent or last or 0
    if count>0 then self.out=self.out:sub(count+1) end
    if err and err~="timeout" then self:fail(err);return end
  end
  local data,err,partial=self.tcp:receive(8192)
  local chunk=data or partial or ""
  if #chunk>0 then self.input=self.input..chunk end
  if #self.input>self.maxBuffer then self:fail("incoming buffer too large");return end
  if self.state=="upgrading" then
    local at=self.input:find("\r\n\r\n",1,true)
    if at then
      local header=self.input:sub(1,at+3)
      self.input=self.input:sub(at+4)
      local valid,why=Upgrade.validateResponse(header,self.expected)
      if not valid then self:fail(why);return end
      self.state="open"
      self:emit("open")
    end
  end
  if self.state=="open" and #self.input>0 then
    local frames,remainder=Frames.decodeServer(self.input,self.maxBuffer)
    if not frames then self:fail(remainder);return end
    self.input=remainder
    for _,frame in ipairs(frames) do
      if frame.opcode==2 then self:emit("binary",frame.payload)
      elseif frame.opcode==9 then self:send(frame.payload,10)
      elseif frame.opcode==8 then self:emit("close",frame.payload);self:close();return end
    end
  end
  if err and err~="timeout" then
    if err=="closed" then self:emit("close","socket closed");self:close()
    else self:fail(err) end
  end
end
return Client
