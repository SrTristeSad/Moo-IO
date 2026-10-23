-- Layout port of reference client/public/css/main.css:
-- topInfoHolder, resourceDisplay, actionBar, mapDisplay and ageBar.
-- This module draws UI only from actual server packets, not fake values.
local C=require("src.game.config")
local Catalog=require("src.game.catalog")
local Objects=require("src.game.reference_objects")
local Icons=require("src.game.reference_icons")
local Assets=require("src.game.reference_assets")
local Upgrades=require("src.game.reference_upgrades")
local ItemInfo=require("src.game.reference_item_info")
local H={}
local mobile=love.system and love.system.getOS and love.system.getOS()=="Android" or os.getenv("MOO_IO_FORCE_ANDROID_E2E")=="1"
local fontSmall,fontMedium,fontLarge
local function fonts()
  if not fontSmall then
    fontSmall=love.graphics.newFont(13)
    fontMedium=love.graphics.newFont(20)
    fontLarge=love.graphics.newFont(24)
  end
end
local function color(r,g,b,a) love.graphics.setColor(r,g,b,a or 1) end
local function box(x,y,w,h,a)
  color(0,0,0,a or 0.25)
  love.graphics.rectangle("fill",x,y,w,h,4,4)
end
local function number(n)
  -- Font:getWidth / graphics.print expect a string, including before N/G
  -- packets have arrived. A numeric 0 crashed the first playable HUD frame.
  if type(n)~="number" or n~=n then return "0" end
  -- JS updateStatusDisplay uses the literal integer, not k/m abbreviation.
  -- On this server unlimitedResources may legitimately start at 1000000.
  return tostring(math.floor(n))
end
H.formatResource=number
local function resource(name,icon,value,x,y,left,gain)
  local content=number(value)
  local width=math.max(75,fontLarge:getWidth(content)+56)
  if left then
    box(x,y,width,45)
    Assets.draw("resources",icon.."_ico.png",x+23,y+22.5,28,28)
    color(1,1,1);love.graphics.setFont(fontLarge)
    love.graphics.print(content,x+42,y+9)
    if gain and gain.amount>0 then
      color(0.49,0.90,0.35,math.min(1,gain.remaining))
      love.graphics.setFont(fontSmall)
      love.graphics.print("+"..number(gain.amount),x+16,y-21)
    end
  else
    box(x-width,y,width,45)
    Assets.draw("resources",icon.."_ico.png",x-23,y+22.5,28,28)
    color(1,1,1);love.graphics.setFont(fontLarge)
    love.graphics.print(content,x-width+10,y+9)
    if gain and gain.amount>0 then
      color(0.49,0.90,0.35,math.min(1,gain.remaining))
      love.graphics.setFont(fontSmall)
      love.graphics.print("+"..number(gain.amount),x-width+10,y-21)
    end
  end
end
local function minimap(world,w,h)
  if love.system and love.system.getOS and love.system.getOS()=="Android" then return end
  -- client/src/index.js renderMinimap: 130x130, bottom 20, left 20.
  local x,y=20,h-150
  local size=130
  box(x,y,size,size)
  for _,ping in ipairs(world.mapPings or {}) do
    local ratio=math.max(0,math.min(1,ping.scale/40))
    color(1,1,1,1-ratio)
    love.graphics.setLineWidth(4)
    love.graphics.circle("line",
      x+ping.x/C.mapScale*size,
      y+ping.y/C.mapScale*size,ping.scale)
  end
  local p=world:localPlayer()
  if p and p.x and p.y then
    color(1,1,1)
    love.graphics.circle("fill",x+p.x/C.mapScale*size,
      y+p.y/C.mapScale*size,7)
  end
  color(1,1,1,0.35)
  local positions=world.minimapData or {}
  for i=1,#positions-1,2 do
    if type(positions[i])=="number" and type(positions[i+1])=="number" then
      love.graphics.circle("fill",x+positions[i]/C.mapScale*size,
        y+positions[i+1]/C.mapScale*size,7)
    end
  end
  local function mark(position,r,g,b)
    if not position then return end
    color(r,g,b)
    local mx=x+position.x/C.mapScale*size
    local my=y+position.y/C.mapScale*size
    love.graphics.setLineWidth(3)
    love.graphics.line(mx-7,my-7,mx+7,my+7)
    love.graphics.line(mx-7,my+7,mx+7,my-7)
  end
  mark(world.lastDeath,252/255,85/255,83/255)
  mark(world.mapMarker,1,1,1)
end
local function leaderboard(world,w)
  local count=math.min(10,#world.leaderboard)
  if count<=0 then return end
  local x,y=w-260,20
  local line=25
  box(x,y,240,18+count*line)
  love.graphics.setFont(fontMedium)
  for i=1,count do
    local entry=world.leaderboard[i]
    local n=string.format("%d. %s",i,tostring(entry.name or "unknown"))
    color(1,1,1)
    love.graphics.print(n:sub(1,18),x+10,y+7+(i-1)*line)
    local score=number(entry.score)
    color(1,1,1)
    love.graphics.print(score,x+230-fontMedium:getWidth(score),
      y+7+(i-1)*line)
  end
end
-- Same boxes and ten-row limit as leaderboard() above: open a
-- real Node player profile on the exact visible leaderboard row.
function H.leaderboardHitTest(world,w,x,y)
  if type(x)~="number" or type(y)~="number" then return nil end
  local count=math.min(10,#world.leaderboard)
  if count==0 or x<w-260 or x>=w-20 or y<27 or y>=27+count*25 then
    return nil
  end
  local index=math.floor((y-27)/25)+1
  local entry=world.leaderboard[index]
  if entry and type(entry.sid)=="number" and entry.sid>=0 and
    entry.sid%1==0 then return entry.sid end
  return nil
end
local function kills(world,w)
  local count=math.max(0,math.floor(world.resources.kills or 0))
  local x=w-260
  local n=math.min(10,#world.leaderboard)
  local y=20+(n>0 and (18+n*25) or 0)+10
  local content=number(count)
  box(x,y,240,44)
  Assets.draw("icons","skull.png",x+213,y+22,30,30)
  color(1,1,1)
  love.graphics.setFont(fontLarge)
  love.graphics.print(content,x+10,y+9)
end
local function ageBar(world,w,h)
  color(1,1,1)
  love.graphics.setFont(fontLarge)
  local label="AGE "..tostring(world.age or 1)
  love.graphics.print(label,(w-fontLarge:getWidth(label))/2,h-142)
  box(w/2-162,h-116,324,20)
  local ratio=0
  if type(world.maxXP)=="number" and world.maxXP>0 then
    ratio=math.max(0,math.min(1,(world.xp or 0)/world.maxXP))
  end
  color(1,1,1)
  love.graphics.rectangle("fill",w/2-157,h-111,314*ratio,10,3,3)
end
local function actionBarEntries(world)
  local weapons=world.inventory.weapons
  local items=world.inventory.items
  local entries={}
  for _,id in ipairs(weapons) do
    if type(id)=="number" then
      local data=Catalog.weaponById(id)
      if data then entries[#entries+1]={kind="weapon",id=id,data=data} end
    end
  end
  for _,id in ipairs(items) do
    if type(id)=="number" then
      local data=Catalog.itemById(id)
      if data then entries[#entries+1]={kind="item",id=id,data=data} end
    end
  end
  return entries
end
-- Only the Node's "a" packet can establish buildIndex/weaponIndex.
-- Do not highlight a slot optimistically on click, and do not assume
-- the default weapon has been confirmed before the first attributes frame.
function H.isSelected(world,entry)
  if not entry then return false end
  local player=world:localPlayer()
  if not player or type(player.buildIndex)~="number" then return false end
  if player.buildIndex>=0 then
    return entry.kind=="item" and entry.id==player.buildIndex
  end
  return player.buildIndex==-1 and entry.kind=="weapon"
    and type(player.weaponIndex)=="number"
    and entry.id==player.weaponIndex
end
-- Both hotkeys and hit tests use the exact same visible, server-synced slots.
function H.slotForKey(world,key)
  if type(key)~="string" or not key:match("^[1-9]$") then return nil end
  local entry=actionBarEntries(world)[tonumber(key)]
  if not entry then return nil end
  return entry.id,entry.kind=="weapon"
end
local function actionBar(world,w,h)
  local entries=actionBarEntries(world)
  local count=#entries
  if count==0 then return end
  local slot,space=mobile and 48 or 66,mobile and 6 or 10
  local width=count*(slot+space)-space
  local origin=(w-width)/2
  local y=mobile and h-63 or h-83
  for i,entry in ipairs(entries) do
    local x=origin+(i-1)*(slot+space)
    box(x,y,slot,slot)
    Icons.draw(entry.kind,entry.data,x+slot/2,y+slot/2,slot)
    if H.isSelected(world,entry) then
      -- Show only confirmed equipment; a rejected "z" does not alter the UI.
      love.graphics.push("all")
      color(0.53,0.86,0.31,1)
      love.graphics.setLineWidth(4)
      love.graphics.rectangle("line",x+2,y+2,slot-4,slot-4,4,4)
      love.graphics.pop()
    end
    -- Reference showItemInfo() reads itemCounts by groupId.
    -- Display the live group count only for placeable structures.
    if entry.kind=="item" then
      local group=Catalog.groupById(entry.data.groupId)
      if group and group.limit then
        local count=world.itemCounts[group.id] or 0
        love.graphics.setFont(fontSmall)
        local shown=tostring(count).."/"..tostring(group.limit)
        color(1,1,1)
        love.graphics.print(shown,x+slot-4-fontSmall:getWidth(shown),
          y+slot-16)
      end
    end
  end
end
local function chatBox(active,text,w,h)
  if not active then return end
  local bw=math.min(440,w-40)
  local bx=(w-bw)/2
  local by=h-246 -- client CSS #chatHolder bottom:200px
  box(bx,by,bw,46)
  love.graphics.setFont(fontMedium)
  color(1,1,1)
  love.graphics.print((text or "").."|",bx+9,by+10)
end
function H.mapHitTest(w,h,x,y)
  return type(x)=="number" and type(y)=="number"
    and x>=20 and x<150 and y>=h-150 and y<h-20
end
-- Native LÖVE click target maps to original actionBarItem onclick/selectToBuild.
-- CSS: 66 x 66, 5px margins on each side, bottom 17px.
function H.hitTest(world,w,h,x,y)
  if mobile then return nil end -- Four tactical slots and backpack replace hidden desktop bar
  if type(x)~="number" or type(y)~="number" then return nil end
  local entries=actionBarEntries(world)
  if #entries==0 then return nil end
  local slot,space=mobile and 48 or 66,mobile and 6 or 10
  local origin=(w-(#entries*(slot+space)-space))/2
  local top=mobile and h-63 or h-83
  if y<top or y>=top+slot then return nil end
  for i,entry in ipairs(entries) do
    local left=origin+(i-1)*(slot+space)
    if x>=left and x<left+slot then
      return entry.id,entry.kind=="weapon"
    end
  end
  return nil
end
-- The browser attaches showItemInfo() to every actionBarItem and upgradeItem
-- onmouseover, hiding it on mouseout. This is the same hit geometry.
function H.hoveredItem(world,w,h,x,y)
  if type(x)~="number" or type(y)~="number" then return nil end
  local offers=Upgrades.offers(world)
  if #offers>0 then
    local start=(w-(#offers*66+(#offers-1)*10))/2
    if y>=10 and y<76 then
      for i,entry in ipairs(offers) do
        local left=start+(i-1)*76
        if x>=left and x<left+66 then return entry end
      end
    end
  end
  local entries=actionBarEntries(world)
  if #entries==0 or y<h-83 or y>=h-17 then return nil end
  local left=(w-(#entries*76-10))/2
  for i,entry in ipairs(entries) do
    local sx=left+(i-1)*76
    if x>=sx and x<sx+66 then return entry end
  end
  return nil
end
local function mobileStats(world,w,h)
  local g=love.graphics
  local p=world:localPlayer()
  local values=world.resources or {}
  local unit=math.max(.55,math.min(w/1280,h/720,1.8))
  -- Horizontal top status bar: keep the minimap, ping and chat unobstructed.
  -- All numbers come from the authoritative world snapshots (not mock HUD data).
  local x=269*unit
  local y=13*unit
  local width=math.max(380*unit,math.min(600*unit,w-x-430*unit))
  local height=64*unit
  local health=math.max(0,tonumber(p and p.health) or 0)
  local maximum=math.max(1,tonumber(p and p.maxHealth) or 100)
  local name=(p and p.name or "Moo IO"):sub(1,16)
  g.push("all")
  g.setColor(.03,.085,.071,.88)
  g.rectangle("fill",x,y,width,height,8*unit,8*unit)
  g.setLineWidth(1.6*unit)
  g.setColor(.40,.64,.49,.75)
  g.rectangle("line",x,y,width,height,8*unit,8*unit)
  g.setFont(fontSmall)
  g.setColor(.95,.96,.88,1)
  g.print(name,x+10*unit,y+7*unit)
  local lifeX=x+145*unit
  local lifeW=math.max(75*unit,math.min(160*unit,width*.31))
  local lifeY=y+8*unit
  g.setColor(.19,.22,.19,1)
  g.rectangle("fill",lifeX,lifeY,lifeW,17*unit,4*unit,4*unit)
  g.setColor(.77,.24,.22,1)
  g.rectangle("fill",lifeX,lifeY,lifeW*math.min(1,health/maximum),17*unit,4*unit,4*unit)
  g.setColor(.97,.97,.93,1)
  g.printf("VIDA "..math.floor(health).."/"..math.floor(maximum),
    lifeX,lifeY+2*unit,lifeW,"center")
  g.setColor(.98,.84,.46,1)
  g.print("OURO "..math.floor(values.points or 0),lifeX+lifeW+12*unit,y+8*unit)
  g.setColor(.93,.95,.91,1)
  local food="COMIDA "..math.floor(values.food or 0)
  local wood="MADEIRA "..math.floor(values.wood or 0)
  local stone="PEDRA "..math.floor(values.stone or 0)
  local kills="ABATES "..math.floor(values.kills or 0)
  g.print(food,x+10*unit,y+38*unit)
  g.print(wood,x+145*unit,y+38*unit)
  g.print(stone,x+285*unit,y+38*unit)
  g.print(kills,x+width-110*unit,y+38*unit)
  g.pop()
end
function H.draw(world,chatActive,chatText,suppressItemInfo)
  fonts()
  local w,h=love.graphics.getDimensions()
  if mobile then
    mobileStats(world,w,h)
    Upgrades.draw(world,w)
    return
  end
  leaderboard(world,w)
  kills(world,w)
  resource("food","food",world.resources.food,w-20,h-175,
    false,world.resourceGain.food)
  resource("wood","wood",world.resources.wood,w-20,h-120,
    false,world.resourceGain.wood)
  resource("stone","stone",world.resources.stone,w-20,h-65,
    false,world.resourceGain.stone)
  resource("points","gold",world.resources.points,20,h-205,
    true,world.resourceGain.points)
  minimap(world,w,h)
  ageBar(world,w,h)
  actionBar(world,w,h)
  chatBox(chatActive,chatText,w,h)
  Upgrades.draw(world,w)
  if not suppressItemInfo and love.mouse and love.mouse.getPosition then
    local x,y=love.mouse.getPosition()
    local entry=H.hoveredItem(world,w,h,x,y)
    if entry then ItemInfo.draw(entry,world) end
  end
end
return H
