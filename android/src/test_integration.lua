-- Automated E2E against a REAL running original Node server.
-- Only enabled by MOOQUEST_INTEGRATION=guest|account in headless CI.
-- Never fabricates a world; waits for actual server C and D packets.
local Original=require("src.net.original_client")
local Auth=require("src.net.local_auth")
local World=require("src.game.world_state")
local Panels=require("src.game.reference_panels")
local Clans=require("src.game.account_clans")
local SecureRandom=require("src.net.secure_random")
local I={}
I.__index=I
function I.new(mode)
  if mode~="guest" and mode~="account" and mode~="store_tribe" and mode~="persistent_clan" then
    error("unknown Node integration mode")
  end
  local token=nil
  local suffix=nil
  if mode=="account" or mode=="persistent_clan" then
    local email="ci-test@localhost.invalid"
    if mode=="persistent_clan" then
      local bytes=SecureRandom.bytes(4)
      suffix=string.format("%02x%02x%02x%02x",bytes:byte(1,4))
      email="ci-ui-clan-"..suffix.."@localhost.invalid"
    end
    local challenge,err=Auth.requestCode(email)
    if not challenge then error("account /auth/code: "..tostring(err)) end
    local verified,reason=Auth.verifyCode(challenge.flow,"123456")
    if not verified then error("account /auth/verify: "..tostring(reason)) end
    token=verified.token
    print("E2E: local Node account emulator issued auth token; never logging token")
  end
  local client=Original.new({
    host="127.0.0.1",port=8080,server="LC",
    autoSpawn=false,authToken=token
  })
  local ok,err=client:connect()
  if not ok then error("Node connection: "..tostring(err)) end
  return setmetatable({
    client=client,world=World.new(),mode=mode,
    elapsed=0,spawned=false,hasC=false,hasD=false,done=false,
    panels=Panels.new(),clans=Clans.new(),suffix=suffix,stage=nil
  },I)
end
function I:stop(ok,reason)
  if self.done then return end
  self.done=true
  print((ok and "E2E PASS: " or "E2E FAIL: ")..reason)
  self.client:close()
  love.event.quit(ok and 0 or 1)
end
function I:draw()
  if self.mode=="store_tribe" then self.panels:draw(self.world) end
  if self.mode=="persistent_clan" then self.clans:draw(false) end
end
local function testStoreTribe(self)
  local panel=self.panels
  local w,h=1280,720
  if not self.stage then
    local sx,_,top=panel:buttons(w)
    panel:click(self.world,sx+10,top+10,w,h)
    local left,y=panel:position(w,h)
    local cmd=panel:click(self.world,left+350,y+124,w,h)
    if not cmd or cmd.packet~="c" or cmd.args[2]~=51 then
      return self:stop(false,"shop Equip button did not select Moo Cap")
    end
    local ok,err=self.client:send(cmd.packet,cmd.args)
    if not ok then return self:stop(false,tostring(err)) end
    self.stage="hat"
    print("E2E STORE: sent c equip Moo Cap")
  elseif self.stage=="hat" and self.world.store.hatIndex==51 then
    local _,tx,top=panel:buttons(w)
    panel:click(self.world,tx+10,top+10,w,h)
    local left,y,_,height=panel:position(w,h)
    panel:click(self.world,left+40,y+height-50,w,h)
    panel:textinput("CITest")
    local cmd=panel:click(self.world,left+300,y+height-50,w,h)
    if not cmd or cmd.packet~="L" or cmd.args[1]~="CITest" then
      return self:stop(false,"tribe Create button invalid")
    end
    local ok,err=self.client:send(cmd.packet,cmd.args)
    if not ok then return self:stop(false,tostring(err)) end
    self.stage="tribe"
    print("E2E TRIBE: sent L create CITest")
  elseif self.stage=="tribe" and self.world.tribe=="CITest" then
    -- The original Node enforces a 200ms tribe cooldown; an immediate
    -- Leave packet after Create is intentionally ignored by the server.
    if not self.joinedAt then self.joinedAt=self.elapsed;return end
    if self.elapsed-self.joinedAt<0.4 then return end
    local left,y,_,height=panel:position(w,h)
    local cmd=panel:click(self.world,left+40,y+height-50,w,h)
    if not cmd or cmd.packet~="N" then
      return self:stop(false,"tribe Leave button invalid")
    end
    local ok,err=self.client:send(cmd.packet,cmd.args)
    if not ok then return self:stop(false,tostring(err)) end
    self.stage="leave"
    print("E2E TRIBE: sent N leave")
  elseif self.stage=="leave" and self.world.tribe==nil then
    return self:stop(true,"store equipped by server, tribe created and left through Node")
  end
end
function I:update(dt)
  if self.done then return end
  self.elapsed=self.elapsed+dt
  if self.elapsed>24 then
    return self:stop(false,"timeout after 24s; state="..
      tostring(self.client.state).." status="..tostring(self.client.status))
  end
  self.client:update()
  if self.client.state=="blocked" or self.client.state=="failed"
    or self.client.state=="closed" then
    return self:stop(false,"Node client "..tostring(self.client.state)..
      ": "..tostring(self.client.error or self.client.status))
  end
  if self.client.state=="keyed_transport" and not self.spawned then
    local ok,err=self.client:spawn({name="Lua CI",skin=0})
    if not ok then return self:stop(false,"M not sent: "..tostring(err)) end
    self.spawned=true
    print("E2E: real Lua client signed and sent M packet")
  end
  for _,event in ipairs(self.client:drain()) do
    if event.kind=="game_packet" then
      local p=event.data
      self.world:apply(p.name,p.args)
      if self.mode=="store_tribe" and
        (p.name=="5" or p.name=="g" or p.name=="3" or p.name=="4") then
        print("E2E RESPONSE: "..p.name.." "..tostring(p.args[1]))
      end
      if p.name=="C" then
        self.hasC=true
        print("E2E: original server confirmed spawn C")
      elseif p.name=="D" then
        local player=self.world:localPlayer()
        if player and type(player.x)=="number" and type(player.y)=="number" then
          self.hasD=true
          print("E2E: authentic local player position D "..player.x..","..player.y)
        end
      end
    end
  end
  if self.mode=="persistent_clan" and self.hasC and self.hasD then
    return require("src.test_clan_integration")(self)
  end
  if self.mode=="store_tribe" and self.hasC and self.hasD then
    return testStoreTribe(self)
  end
  if self.hasC and self.hasD then
    return self:stop(true,"Lua "..self.mode..
      " account /api/join -> WebSocket -> io-init -> M -> C -> D")
  end
end
return I
