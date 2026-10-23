-- Protocol-driven game state. All entities originate in packets from the Node server.
-- Packet layouts: al007ex/moomoo-clone/server/src/moomoo/server.js (pinned baseline).
local Catalog=require("src.game.catalog")
local C=require("src.game.config")
local Animation=require("src.game.reference_animation")
local CombatText=require("src.game.reference_combat_text")
local BossEffects=require("src.game.reference_boss_effects")
local Animals=require("src.game.animals")
local Store=require("src.game.store_catalog")
local JSON=require("src.net.json")
local function freeStore()
  local owned={hats={},accessories={},hatIndex=0,accessoryIndex=0}
  for _,h in ipairs(Store.hats) do
    if h.price<=0 and not h.dontSell then owned.hats[h.id]=true end
  end
  for _,a in ipairs(Store.accessories) do
    if a.price<=0 and not a.dontSell then owned.accessories[a.id]=true end
  end
  return owned
end
local World={}
World.__index=World
-- The original JS objectManager stores objects in an ARRAY and reuses
-- the first inactive slot. Lua pairs(objects) has no stable paint order,
-- so overlapping structures could unpredictably change their z-order.
local function removeObject(world,sid)
  world.objects[sid]=nil
  local slot=world.objectSlotBySid[sid]
  if slot then
    world.objectSlots[slot]=false
    world.objectSlotBySid[sid]=nil
  end
end
local function insertObject(world,sid,obj)
  local slot=world.objectSlotBySid[sid]
  if not slot then
    for i=1,world.objectSlotCount do
      if world.objectSlots[i]==false then slot=i;break end
    end
    if not slot then
      world.objectSlotCount=world.objectSlotCount+1
      slot=world.objectSlotCount
    end
    world.objectSlotBySid[sid]=slot
  end
  world.objectSlots[slot]=sid
  world.objects[sid]=obj
end
function World:orderedObjects()
  local out,seen={},{}
  for i=1,self.objectSlotCount do
    local sid=self.objectSlots[i]
    local o=sid and self.objects[sid]
    if o then
      out[#out+1]=o
      seen[sid]=true
    end
  end
  -- Menu mock objects are defined without Node H packets. Keep a stable
  -- fallback order for them too, without modifying their visuals.
  local tail={}
  for sid,o in pairs(self.objects) do
    if not seen[sid] then tail[#tail+1]={sid=sid,obj=o} end
  end
  table.sort(tail,function(a,b) return a.sid<b.sid end)
  for _,v in ipairs(tail) do out[#out+1]=v.obj end
  return out
end
-- JS player and AI entity arrays have stable iteration order between frames.
-- Keep SID order-of-first-appearance separately from current visibility:
-- hidden entities may become visible again without being appended later.
local function trackPaintOrder(world,kind,sid)
  local tracked=world.entityPaintTracked[kind]
  if not tracked[sid] then
    local order=world.entityPaintOrder[kind]
    order[#order+1]=sid
    tracked[sid]=true
  end
end
local function removePaintOrder(world,kind,sid)
  local tracked=world.entityPaintTracked[kind]
  if not tracked[sid] then return end
  tracked[sid]=nil
  local order=world.entityPaintOrder[kind]
  for i=1,#order do
    if order[i]==sid then
      table.remove(order,i)
      break
    end
  end
end
local function orderedEntities(world,kind)
  local entities=world[kind]
  local result,seen={},{}
  for _,sid in ipairs(world.entityPaintOrder[kind]) do
    local e=entities[sid]
    if e then
      result[#result+1]=e
      seen[sid]=true
    end
  end
  -- Local tests may set up simulated menu entities without packets.
  -- Show those too, in deterministic SID order; don't fabricate any entities.
  local fallback={}
  for sid,e in pairs(entities) do
    if not seen[sid] then fallback[#fallback+1]={sid=sid,entity=e} end
  end
  table.sort(fallback,function(a,b) return a.sid<b.sid end)
  for _,v in ipairs(fallback) do result[#result+1]=v.entity end
  return result
end
function World:orderedPlayers()
  return orderedEntities(self,"players")
end
function World:orderedAnimals()
  return orderedEntities(self,"animals")
end

local function number(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
local function validId(v) return number(v) and v%1==0 and v>=0 end
local function array(v) return type(v)=="table" and v or {} end
-- Snapshot smoothing follows the 170ms transition used in the JS updateGame().
local function receivePosition(entity,x,y,dir)
  entity.fromX=entity.visualX or entity.x or x
  entity.fromY=entity.visualY or entity.y or y
  entity.toX=x;entity.toY=y
  entity.visualX=entity.fromX;entity.visualY=entity.fromY
  entity.interp=0
  entity.x=x;entity.y=y
  if number(dir) then entity.dir=dir end
end

function World.new()
  return setmetatable({
    sid=nil,spawned=false,dead=false,players={},objects={},
    objectSlots={},objectSlotBySid={},objectSlotCount=0,
    animals={},projectiles={},
    entityPaintOrder={players={},animals={}},
    entityPaintTracked={players={},animals={}},
    resources={},resourceGain={},itemCounts={},inventory={weapons={},items={}},leaderboard={},
    combatText={},bossEffects={},
    updateSeconds=nil,restartSeconds=nil,pongCount=0,
    profiles={},lifeStats={},
    xp=0,maxXP=0,age=1,upgradePoints=0,upgradeAge=0,
    minimapData={},mapPings={},mapMarker=nil,lastDeath=nil,
    serverAnimals={},teams={},tribe=nil,tribeOwner=false,tribeMembers={},joinRequests={},
    store=freeStore(),
    packets=0,lastPacket=nil
  },World)
end

function World:apply(name,args)
  if type(name)~="string" then return false end
  args=array(args)
  self.packets=self.packets+1
  self.lastPacket=name
  if name=="A" then
    -- server/src/moomoo/server.js addPlayer sends server-authoritative
    -- permitted animal display metadata before any gameplay spawn.
    local handshake=args[1]
    if type(handshake)~="table" then return false end
    local kinds=handshake.animals
    if type(kinds)=="table" then
      local received={}
      for _,kind in ipairs(kinds) do
        if type(kind)=="table" and validId(kind.id) and
          type(kind.src)=="string" and
          kind.src:match("^[%w_%-]+$") and
          number(kind.scale) and kind.scale>0 then
          received[kind.id]=kind
        end
      end
      if next(received) then self.serverAnimals=received end
    end
    if type(handshake.teams)=="table" then
      self.teams={}
      for _,team in ipairs(handshake.teams) do
        if type(team)=="table" and type(team.sid)=="string" then
          self.teams[#self.teams+1]={sid=team.sid,owner=team.owner,clan=team.clan==true}
        end
      end
    end
    return true
  elseif name=="g" then
    -- Original client addAlliance({sid,owner,clan}).
    local t=args[1]
    if type(t)~="table" or type(t.sid)~="string" then return false end
    for i=#self.teams,1,-1 do
      if self.teams[i].sid==t.sid then table.remove(self.teams,i) end
    end
    self.teams[#self.teams+1]={sid=t.sid,owner=t.owner,clan=t.clan==true}
    return true
  elseif name=="1" then
    if type(args[1])~="string" then return false end
    for i=#self.teams,1,-1 do
      if self.teams[i].sid==args[1] then table.remove(self.teams,i) end
    end
    return true
  elseif name=="2" then
    if not validId(args[1]) or type(args[2])~="string" then return false end
    self.joinRequests[#self.joinRequests+1]={sid=args[1],name=args[2]}
    return true
  elseif name=="3" then
    -- Authoritative setPlayerTeam() after create/join/leave.
    self.tribe=type(args[1])=="string" and args[1] or nil
    self.tribeOwner=args[2]==true or args[2]==1
    self.tribeMembers={}
    self.joinRequests={}
    local p=self:localPlayer()
    if p then p.team=self.tribe end
    return true
  elseif name=="4" then
    local arr=array(args[1])
    self.tribeMembers={}
    for i=1,#arr-1,2 do
      if validId(arr[i]) and type(arr[i+1])=="string" then
        self.tribeMembers[#self.tribeMembers+1]={sid=arr[i],name=arr[i+1]}
      end
    end
    return true
  elseif name=="5" then
    -- Store purchase (type=0) / equip (type=1), isAccessory index.
    local action,id,accessory=args[1],args[2],args[3]
    if (action~=0 and action~=1) or not validId(id) then return false end
    if accessory~=0 and accessory~=1 and accessory~=false and accessory~=true then return false end
    local isAccessory=accessory==1 or accessory==true
    if action==0 then
      if Store.byId(id,isAccessory) then
        local owned=isAccessory and self.store.accessories or self.store.hats
        owned[id]=true
      end
    elseif isAccessory then
      self.store.accessoryIndex=id
    else
      self.store.hatIndex=id
    end
    return true
  elseif name=="C" then
    if not validId(args[1]) then return false end
    self.sid=args[1];self.spawned=true;self.dead=false
    -- The Node sends a fresh D after every C. Do not render the previous
    -- life's position while waiting for its new authoritative D snapshot.
    self.players[self.sid]=nil
    -- server/src/moomoo/modules/player.js::spawn initializes this in Node;
    -- the JavaScript client's Player.spawn() mirrors it locally.
    -- The server does not send V on each new spawn, only when inventory changes.
    self.inventory={weapons={0},items={0,3,6,10}}
    self.xp=0;self.maxXP=300;self.age=1
    self.upgradePoints=0;self.upgradeAge=2
    self.resources={kills=0}
    self.resourceGain={}
    self.itemCounts={}
    self.combatText={}
    self.bossEffects={}
    -- Stats/profiles belong to server SIDs from this session, never a
    -- local estimate inferred from kills, damage text, or resource totals.
    self.profiles={};self.lifeStats={}
    return true
  elseif name=="D" then
    -- [id,sid,name,x,y,dir,health,maxHealth,scale,skinColor,...]
    local d=array(args[1])
    local id=d[2]
    if not validId(id) or not number(d[4]) or not number(d[5]) then return false end
    local p=self.players[id] or {sid=id}
    p.id=d[1];p.name=type(d[3])=="string" and d[3] or "unknown"
    receivePosition(p,d[4],d[5],number(d[6]) and d[6] or 0)
    p.health=number(d[7]) and d[7] or 100
    p.maxHealth=number(d[8]) and d[8] or 100
    p.scale=number(d[9]) and d[9] or 35
    p.skinColor=d[10] or 0;p.clan=type(d[13])=="string" and d[13] or nil
    p.morph=d[14]
    -- Player dive state is sent both on initial D and on later m events.
    p.dive=(validId(d[15]) and d[15]<=3) and d[15] or 0
    p.invisible=d[16];p.disguised=d[17]
    self.players[id]=p
    trackPaintOrder(self,"players",id)
    return true
  elseif name=="a" then
    local positions,attrs,hidden=array(args[1]),array(args[2]),array(args[3])
    -- Positions are flattened groups of FOUR. There is no interpolation/fake prediction.
    for i=1,#positions-3,4 do
      local sid,x,y,dir=positions[i],positions[i+1],positions[i+2],positions[i+3]
      if validId(sid) and number(x) and number(y) and number(dir) then
        local p=self.players[sid] or {sid=sid,scale=35,health=100,maxHealth=100}
        receivePosition(p,x,y,dir/100)
        self.players[sid]=p
        trackPaintOrder(self,"players",sid)
      end
    end
    -- Attributes are flattened groups of TEN.
    for i=1,#attrs-9,10 do
      local sid=attrs[i]
      if validId(sid) then
        local p=self.players[sid] or {sid=sid}
        p.buildIndex=attrs[i+1];p.weaponIndex=attrs[i+2];p.variant=attrs[i+3]
        p.team=type(attrs[i+4])=="string" and attrs[i+4] or nil
        p.isLeader=attrs[i+5]
        p.skin=type(attrs[i+6])=="number" and attrs[i+6] or 0
        p.tail=type(attrs[i+7])=="number" and attrs[i+7] or 0
        p.icon=attrs[i+8]
        p.zIndex=type(attrs[i+9])=="number" and attrs[i+9] or 0
        self.players[sid]=p
        trackPaintOrder(self,"players",sid)
      end
    end
    -- The JavaScript source marks hidden players as invisible in their
    -- existing array slot; don't recycle their paint-order position.
    for _,sid in ipairs(hidden) do self.players[sid]=nil end
    return true
  elseif name=="H" then
    -- Objects: [sid,x,y,dir,scale,type,id,ownerSid] * N.
    local data=array(args[1])
    for i=1,#data-7,8 do
      local sid,x,y=data[i],data[i+1],data[i+2]
      if validId(sid) and number(x) and number(y) then
        insertObject(self,sid,{sid=sid,x=x,y=y,dir=data[i+3],scale=data[i+4],
          type=data[i+5],
          id=type(data[i+6])=="number" and data[i+6] or nil,
          owner=data[i+7]})
      end
    end
    return true
  elseif name=="I" then
    -- Animals: [sid,index,x,y,dir*100,health,nameIndex,state] * N; hidden IDs.
    local data,hidden=array(args[1]),array(args[2])
    for i=1,#data-7,8 do
      local sid,x,y=data[i],data[i+2],data[i+3]
      if validId(sid) and number(x) and number(y) then
        local ai=self.animals[sid] or {sid=sid}
        ai.index=data[i+1]
        receivePosition(ai,x,y,number(data[i+4]) and data[i+4]/100 or 0)
        ai.health=data[i+5];ai.nameIndex=data[i+6];ai.state=data[i+7]
        self.animals[sid]=ai
        trackPaintOrder(self,"animals",sid)
      end
    end
    -- Hidden animals keep their original JS-array slot for later return.
    for _,sid in ipairs(hidden) do self.animals[sid]=nil end
    return true
  elseif name=="7" then
    -- Reference updateMinimap() receives [x1,y1,x2,y2,...] for teammates.
    self.minimapData=array(args[1])
    return true
  elseif name=="8" then
    -- Reference showText(x,y,value,type). The fourth arg is unused by
    -- the original client. Do not infer damage from O/I health snapshots.
    return CombatText.spawn(self.combatText,args[1],args[2],args[3])
  elseif name=="9" then
    -- Reference pingMap(x,y), shrinking alpha with scale from 0 to 40.
    if number(args[1]) and number(args[2]) then
      self.mapPings[#self.mapPings+1]={x=args[1],y=args[2],scale=0}
    end
    return true
  elseif name=="6" then
    -- client/src/index.js receiveChat(sid,message): 3000ms speech bubble.
    local p=self.players[args[1]]
    if p and type(args[2])=="string" then
      p.chatMessage=args[2]
      p.chatCountdown=3000
    end
    return true
  elseif name=="m" then
    -- Node Game.setDive(player,state,ms): sid, 0..3, transition duration.
    -- Never create a player locally on a state-only packet.
    local sid,state,duration=args[1],args[2],args[3]
    if not validId(sid) or not validId(state) or state>3
      or (duration~=nil and (not number(duration) or duration<0)) then
      return false
    end
    local p=self.players[sid]
    if not p then return true end
    p.dive=state
    p.diveDuration=duration or 0
    return true
  elseif name=="r" then
    -- Announcement: 0 means reload AFTER this life, not a zero-second timer.
    local seconds=args[1]
    if not number(seconds) or seconds<0 then return false end
    self.updateSeconds=seconds
    return true
  elseif name=="Z" then
    -- Shutdown: -1 cancels, otherwise count down from server seconds.
    local seconds=args[1]
    if not number(seconds) or seconds< -1 then return false end
    if seconds==-1 then
      self.restartSeconds=nil
    else
      self.restartSeconds=seconds
    end
    return true
  elseif name=="0" then
    -- Pong is sent only by the Node server in reply to client ping.
    self.pongCount=self.pongCount+1
    return true
  elseif name=="W" then
    -- Crab King danger areas emitted by Node ai.js::telegraph().
    -- These effects are visual only: no client-simulated attack or damage.
    return BossEffects.add(self.bossEffects,args[1],args[2],args[3],
      args[4],args[5],args[6],args[7])
  elseif name=="J" then
    -- The JavaScript client invokes findAIBySID(sid):startAnim().
    local ai=self.animals[args[1]]
    if ai then Animation.animal(ai) end
    return true
  elseif name=="K" then
    -- sid, didHit, weaponIndex, optional skin attack-speed multiplier.
    local p=self.players[args[1]]
    if p then
      local weapon=Catalog.weaponById(args[3])
      Animation.player(p,args[2],weapon,args[4])
    end
    return true
  elseif name=="Q" then
    if validId(args[1]) then removeObject(self,args[1]) end
    return true
  elseif name=="O" then
    local p=self.players[args[1]]
    if p and number(args[2]) then p.health=args[2] end
    return true
  elseif name=="E" then
    -- E carries the socket ID, unlike the numeric SID in player-position snapshots.
    for sid,p in pairs(self.players) do
      if p.id==args[1] then
        self.players[sid]=nil
        removePaintOrder(self,"players",sid)
      end
    end
    return true
  elseif name=="R" then
    -- client/src/index.js killObjects(ownerSid): remove every item of that owner.
    local ownerSid=args[1]
    if validId(ownerSid) then
      for sid,o in pairs(self.objects) do
        if o.owner==ownerSid then removeObject(self,sid) end
      end
    end
    return true
  elseif name=="L" then
    local direction,sid=args[1],args[2]
    local o=self.objects[sid]
    if o and number(direction) then
      o.wiggleX=(o.wiggleX or 0)+C.gatherWiggle*math.cos(direction)
      o.wiggleY=(o.wiggleY or 0)+C.gatherWiggle*math.sin(direction)
    end
    return true
  elseif name=="M" then
    -- The reference shootTurret(sid,dir) rotates AND kicks the turret back
    -- opposite its shot. This is cosmetic and must follow a real Node M.
    local sid,dir=args[1],args[2]
    local obj=self.objects[sid]
    if obj and number(dir) then
      obj.dir=dir
      obj.wiggleX=(obj.wiggleX or 0)+C.gatherWiggle*math.cos(dir+math.pi)
      obj.wiggleY=(obj.wiggleY or 0)+C.gatherWiggle*math.sin(dir+math.pi)
    end
    return true
  elseif name=="X" then
    -- Projectile: x,y,dir,remainingRange,speed,projectileType,layer,sid.
    local x,y,dir,range,speed,typ,layer,sid=
      args[1],args[2],args[3],args[4],args[5],args[6],args[7],args[8]
    if number(x) and number(y) and number(dir) and number(range)
      and number(speed) and validId(sid) then
      self.projectiles[sid]={sid=sid,x=x,y=y,dir=dir,range=range,
        speed=speed,indx=typ,layer=layer or 0,skipMov=true}
    end
    return true
  elseif name=="Y" then
    local p=self.projectiles[args[1]]
    if p and number(args[2]) then p.range=args[2] end
    return true
  elseif name=="P" then
    local player=self:localPlayer()
    if player and number(player.x) and number(player.y) then
      self.lastDeath={x=player.x,y=player.y}
    end
    self.dead=true;self.spawned=false
    -- The reference stops rendering the defeated player immediately.
    -- Preserve lastDeath for its minimap marker; do not invent a corpse.
    if self.sid~=nil then self.players[self.sid]=nil end
    return true
  elseif name=="N" then
    -- Absolute counts are sent with flag 1. Only display "gained" when
    -- the Node actually increased a known prior quantity (not initial 1m).
    local key,value=args[1],args[2]
    if type(key)=="string" and number(value) then
      local previous=self.resources[key]
      local nextValue=(args[3]==1) and value or ((previous or 0)+value)
      self.resources[key]=nextValue
      if number(previous) and nextValue>previous then
        self.resourceGain[key]={amount=nextValue-previous,remaining=1.5}
      end
    end
    return true
  elseif name=="V" then
    local data=array(args[1])
    if args[2]==1 then self.inventory.weapons=data
    elseif args[2]==0 then self.inventory.items=data end
    return true
  elseif name=="S" then
    -- server/src/moomoo/modules/player.js changeItemCount(index,value).
    if validId(args[1]) and number(args[2]) then
      self.itemCounts[args[1]]=args[2]
    end
    return true
  elseif name=="T" then
    if number(args[1]) then self.xp=args[1] end
    if number(args[2]) then self.maxXP=args[2] end
    if number(args[3]) then self.age=args[3] end
    return true
  elseif name=="U" then
    if number(args[1]) then self.upgradePoints=args[1] end
    if number(args[2]) then self.upgradeAge=args[2] end
    return true
  elseif name=="p" then
    -- Server sendProfile(viewer,sid): JSON-string, not a Lua table.
    -- Parse with the existing bounded, non-evaluating JSON decoder.
    local sid,raw=args[1],args[2]
    if not validId(sid) or type(raw)~="string" or #raw>32768 then
      return false
    end
    local profile=JSON.decode(raw)
    if type(profile)~="table" or type(profile.name)~="string"
      or #profile.name>80 then return false end
    -- Keep only the fields displayed by the native profile card.
    -- Never bypass the Node's anonymous / guest privacy decisions.
    self.profiles[sid]={
      name=profile.name,guest=profile.guest==true,anon=profile.anon==true,
      role=type(profile.role)=="string" and profile.role or nil,
      clan=type(profile.clan)=="table" and
        type(profile.clan.name)=="string" and profile.clan.name or nil,
      kills=number(profile.kills) and profile.kills or nil,
      deaths=number(profile.deaths) and profile.deaths or nil,
      bestScore=number(profile.bestScore) and profile.bestScore or nil,
      lives=number(profile.lives) and profile.lives or nil,
      playtime=number(profile.playtime) and profile.playtime or nil
    }
    return true
  elseif name=="F" then
    -- Node sendStats(viewer,sid): 13 flat arguments, never a map.
    local sid=args[1]
    if not validId(sid) then return false end
    local fields={"kills","wood","food","stone","gold","damage",
      "animalDamage","healing","animals","bosses"}
    local stats={}
    for i,field in ipairs(fields) do
      if not number(args[i+1]) or args[i+1]<0 then return false end
      stats[field]=args[i+1]
    end
    if not number(args[13]) or args[13]<0 then return false end
    stats.score=args[13]
    -- Guest account IDs are privileged data; do not expose on the card.
    self.lifeStats[sid]=stats
    return true
  elseif name=="G" then
    local list=array(args[1]);self.leaderboard={}
    for i=1,#list-2,3 do
      self.leaderboard[#self.leaderboard+1]={sid=list[i],name=list[i+1],score=list[i+2]}
    end
    return true
  end
  return false
end
function World:update(dt)
  if type(dt)~="number" or dt<=0 then return end
  -- Advance the server-issued countdowns only. Stage 0 on r is a
  -- semantic "after this life" message, so it remains at zero.
  if self.updateSeconds and self.updateSeconds>0 then
    self.updateSeconds=math.max(0,self.updateSeconds-dt)
  end
  if self.restartSeconds and self.restartSeconds>0 then
    self.restartSeconds=math.max(0,self.restartSeconds-dt)
  end
  CombatText.update(self.combatText,dt)
  BossEffects.update(self.bossEffects,dt)
  for key,gain in pairs(self.resourceGain) do
    gain.remaining=gain.remaining-dt
    if gain.remaining<=0 then self.resourceGain[key]=nil end
  end
  for i=#self.mapPings,1,-1 do
    local ping=self.mapPings[i]
    ping.scale=ping.scale+dt*1000*0.05
    if ping.scale>=40 then table.remove(self.mapPings,i) end
  end
  for _,group in ipairs({self.players,self.animals}) do
    for _,entity in pairs(group) do
      Animation.update(entity,dt)
      if entity.chatCountdown and entity.chatCountdown>0 then
        entity.chatCountdown=math.max(0,entity.chatCountdown-dt*1000)
      end
      if entity.interp then
        entity.interp=math.min(1.7,entity.interp+dt*1000/170)
        entity.visualX=entity.fromX+(entity.toX-entity.fromX)*entity.interp
        entity.visualY=entity.fromY+(entity.toY-entity.fromY)*entity.interp
      end
    end
  end
  for _,o in pairs(self.objects) do
    if type(o.id)=="number" then
      local item=Catalog.itemById(o.id)
      if item and item.turnSpeed then
        o.dir=(o.dir or 0)+item.turnSpeed*dt*1000
      end
    end
    o.wiggleX=(o.wiggleX or 0)*(0.99^(dt*1000))
    o.wiggleY=(o.wiggleY or 0)*(0.99^(dt*1000))
  end
  for sid,p in pairs(self.projectiles) do
    if p.skipMov then
      p.skipMov=false
    else
      local distance=p.speed*dt*1000
      distance=math.min(distance,p.range)
      p.x=p.x+distance*math.cos(p.dir)
      p.y=p.y+distance*math.sin(p.dir)
      p.range=p.range-distance
      if p.range<=0 then self.projectiles[sid]=nil end
    end
  end
end
function World:animalKind(id)
  if not validId(id) then return nil end
  return self.serverAnimals[id] or Animals.byId(id)
end
function World:localPlayer()
  return self.sid and self.players[self.sid] or nil
end
return World
