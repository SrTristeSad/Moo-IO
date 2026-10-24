package.path="./?.lua;./?/init.lua;"..package.path
local Host=require("src.net.mooio_host")
local address,code=nil,nil
local active=false
local starts,stops=0,0
local lastBots=-1
local function native(action,bots)
  if action=="start" then
    starts=starts+1
    lastBots=bots
    active=true
    return true
  end
  if action=="stop" then
    stops=stops+1
    active=false
    return true
  end
  error("unexpected control action")
end
local h=Host.new({
  readStatus=function() return active and address or nil, active and lastBots or nil end,
  readSessionCode=function() return active and code or nil end,
  controlServer=native
})
assert(h.state=="idle" and not active and starts==0,
  "opening the app or entering menus must never run the Node server")
local ok=h:start("lan",nil,0)
assert(ok and active and starts==1 and h.state=="starting" and lastBots==0)
for _=1,12 do h:update(.7) end
assert(h.state=="starting","must not report ready before Node controller responds")
address="192.168.1.12"
h:update(.7)
assert(h.state=="starting","must not report ready without Android room code")
code="android-room-code"
h:update(.7)
assert(h.state=="ready")
assert(h.hostIP=="192.168.1.12" and h.port==8080)
assert(h.address=="192.168.1.12:8080" and h.code=="android-room-code")
local again,reason=h:start("lan")
assert(not again and starts==1 and reason,"must never start a second Node process")
h:stop()
assert(h.state=="idle" and stops==1 and not active,
  "leaving room must actually stop native service and free resources")
h:stop()
assert(stops==1,"stopping an already-closed room must not restart service")
assert(h:start("lan",nil,5) and active and starts==2 and lastBots==5,
  
  "must be able to start a new room after the previous native service exited")
h:stop()
assert(stops==2 and not active)
local failedCalls=0
local blocked=Host.new({readStatus=function()return nil end,
  readSessionCode=function()return nil end,
  controlServer=function(action)failedCalls=failedCalls+1;return false end})
local startOk=blocked:start("lan")
assert(not startOk and blocked.state=="failed" and failedCalls==1,
  "controller failure must not claim hosting or show ongoing service")
local timeoutStop=0
local dead=Host.new({readStatus=function() return nil end,
  readSessionCode=function() return nil end,
  controlServer=function(action)
    if action=="stop" then timeoutStop=timeoutStop+1 end
    return true
  end})
assert(dead:start("lan"))
for _=1,38 do dead:update(.7) end
assert(dead.state=="failed" and type(dead.error)=="string" and timeoutStop==1,
  "startup timeout must stop the native foreground service")
dead:stop()
assert(timeoutStop==1,"no second shutdown needed after timeout")
-- Shutdown must never pretend the native Node process stopped if transport fails.
local shutdownFailure=Host.new({
  readStatus=function() return "127.0.0.1",0 end,
  readSessionCode=function() return "testcode123" end,
  controlServer=function(action) return action=="start" end
})
assert(shutdownFailure:start("lan",nil,0))
shutdownFailure:update(.8)
assert(shutdownFailure.state=="ready")
local stopped,why=shutdownFailure:stop()
assert(stopped==false and shutdownFailure.state=="failed" and why,
  "failed native shutdown must be surfaced rather than reporting RAM freed")
-- A status without the effective bot count must never confirm readiness.
local noBotStatus=Host.new({
  readStatus=function() return "127.0.0.1" end,
  readSessionCode=function() return "testcode123" end,
  controlServer=function() return true end
})
assert(noBotStatus:start("lan",nil,0))
noBotStatus:update(.8)
assert(noBotStatus.state=="starting",
  "legacy status without bot count must not confirm a room")
print("MOO IO ANDROID HOST LIFECYCLE PASS")
