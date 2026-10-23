package.path="./?.lua;./?/init.lua;"..package.path
local Host=require("src.net.mooio_host")
local address,code=nil,nil
local h=Host.new({
  readStatus=function() return address end,
  readSessionCode=function() return code end
})
assert(h.state=="idle")
local ok=h:start("lan",nil,0)
assert(ok and h.state=="starting")
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
h:stop()
assert(h.state=="idle")
local dead=Host.new({readStatus=function() return nil end,readSessionCode=function()return nil end})
assert(dead:start("lan"))
for _=1,38 do dead:update(.7) end
assert(dead.state=="failed" and type(dead.error)=="string")
print("MOO IO ANDROID HOST PASS")
