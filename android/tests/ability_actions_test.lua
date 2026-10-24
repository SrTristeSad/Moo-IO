package.path="./?.lua;./?/init.lua;"..package.path
local Abilities=require("src.mobile.ability_actions")
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local null={}
local p={buildIndex=-1,weaponIndex=0}
local world={inventory={weapons={0,1},items={0,3}},localPlayer=function() return p end}
local packets={}
local function send(name,args)
  packets[#packets+1]={name=name,args=args}
  return true
end
local function clear() for i=#packets,1,-1 do packets[i]=nil end end
local ok,reason=Abilities.activate(world,2,0,send,null,false)
eq(ok,true);eq(#packets,1);eq(packets[1].name,"z")
eq(packets[1].args[1],1);eq(packets[1].args[2],true)
clear()
-- Eating an available apple is an actual z+F(1)+F(0) action (no K).
ok,reason=Abilities.activate(world,3,0.7,send,null,false)
eq(ok,true);eq(reason,"consume");eq(#packets,3)
eq(packets[1].name,"z");eq(packets[1].args[1],0);eq(packets[1].args[2],false)
eq(packets[2].name,"F");eq(packets[2].args[1],1);eq(packets[2].args[2],.7)
eq(packets[3].name,"F");eq(packets[3].args[1],0)
eq(packets[3].args[2],null)
clear()
-- Selecting a structure lets the server place it in the original aim direction.
ok,reason=Abilities.activate(world,4,1.1,send,null,false)
eq(ok,true);eq(reason,"build");eq(#packets,3)
eq(packets[1].name,"z");eq(packets[1].args[1],3)
eq(packets[2].name,"F");eq(packets[2].args[2],1.1)
clear()
p.buildIndex=3
ok,reason=Abilities.activate(world,4,0,send,null,false)
eq(ok,true);eq(#packets,2);eq(packets[1].name,"F")
clear()
-- Multitouch: activating an item while attacking cannot send F(0) or K.
p.buildIndex=-1
ok,reason=Abilities.activate(world,4,0,send,null,true)
eq(ok,true);eq(reason,"armed");eq(#packets,1);eq(packets[1].name,"z")
clear()
ok,reason=Abilities.activate(world,11,0,send,null,false)
eq(ok,false);eq(#packets,0)
local sendFail=function()return false,"offline" end
ok,reason=Abilities.activate(world,3,0,sendFail,null,false)
eq(ok,false);eq(reason,"offline")
print("MOO IO REAL MOBILE ABILITIES PASS")
