-- Lua/LÖVE port of the reference Canvas drawing order and sprite rules.
-- Source: al007ex/moomoo-clone/client/src/index.js and client/public/img.
-- No improvised animal, weapon or tree illustrations.
local C=require("src.game.config")
local Catalog=require("src.game.catalog")
local Animals=require("src.game.animals")
local Shapes=require("src.game.reference_primitives")
local Objects=require("src.game.reference_objects")
local Assets=require("src.game.reference_assets")
local CombatText=require("src.game.reference_combat_text")
local BossEffects=require("src.game.reference_boss_effects")
local SecretMap=require("src.game.reference_secret_map")
local View={}
-- client/src/index.js updateGame waterMult / waterPlus (Canvas only).
local waterMult=1
local waterPlus=1
function View.advanceWater(dt)
  if type(dt)~="number" or dt<=0 then return waterMult end
  waterMult=waterMult+waterPlus*C.waveSpeed*dt*1000
  if waterMult>=C.waveMax then
    waterMult=C.waveMax
    waterPlus=-1
  elseif waterMult<=1 then
    waterMult=1
    waterPlus=1
  end
  return waterMult
end
local pi=math.pi
local cos,sin=math.cos,math.sin

local skinColors={
  "#bf8f54","#cbb091","#896c4b","#fadadc","#ececec",
  "#c37373","#4c4c4c","#ecaff7","#738cc3","#8bc373"
}
local variants={[0]="",[1]="_g",[2]="_d",[3]="_r",[4]="_e"}
local hatById,tailById={},{}
for _,v in ipairs(Catalog.hats) do hatById[v.id]=v end
for _,v in ipairs(Catalog.accessories) do tailById[v.id]=v end
local function see(e,camera,w,h,scale)
  if type(e.x)~="number" or type(e.y)~="number" then return false end
  local x,y=camera:worldToScreen(e.visualX or e.x,e.visualY or e.y)
  local s=(scale or e.scale or 120)*camera.zoom
  return x+s>=0 and x-s<=w and y+s>=0 and y-s<=h
end
function View.riverGeometry(camera)
  -- World Y, not player Y or mouse dragging. This is the exact map centre
  -- used by client/src/index.js::renderWaterBodies.
  local _,y=camera:worldToScreen(0,C.mapScale/2)
  local bank=(C.riverWidth+C.riverPadding)*camera.zoom
  local water=(C.riverWidth+(waterMult-1)*250)*camera.zoom
  return y,bank,water
end
local function river(camera,w)
  local y,bank,water=View.riverGeometry(camera)
  Shapes.color("#dbc666")
  love.graphics.rectangle("fill",0,y-bank/2,w,bank)
  Shapes.color("#91b2db")
  love.graphics.rectangle("fill",0,y-water/2,w,water)
end
local function ground(camera,w,h)
  Shapes.color("#b6db66")
  love.graphics.rectangle("fill",0,0,w,h)
  local _,snow=camera:worldToScreen(0,C.snowBiomeTop)
  if snow>0 then
    Shapes.color("#ffffff")
    love.graphics.rectangle("fill",0,0,w,math.min(h,snow))
  end
  local _,desert=camera:worldToScreen(0,C.mapScale-C.snowBiomeTop)
  if desert<h then
    Shapes.color("#dbc666")
    love.graphics.rectangle("fill",0,math.max(0,desert),w,
      h-math.max(0,desert))
  end
  river(camera,w)
  -- The running Node server adds a valid west-of-map secret region absent
  -- from the archived browser renderer. Draw the Node-configured geography
  -- without altering original river, snow or desert east of x=0.
  SecretMap.draw(camera,w,h,waterMult)
end
local function grid(camera,w,h)
  -- Same transparent grid and spacing used by the reference Canvas client.
  love.graphics.setColor(0,0,0,0.06)
  love.graphics.setLineWidth(4)
  -- JS grid is maxScreenHeight/18 (60 world units), then transformed by
  -- resize()'s cover scale. Keep it aligned to the same camera world origin.
  local step=60*camera.zoom
  local originX,originY=camera:worldToScreen(0,0)
  local x=originX%step
  while x<w do
    love.graphics.line(x,0,x,h)
    x=x+step
  end
  local y=originY%step
  while y<h do
    love.graphics.line(0,y,w,y)
    y=y+step
  end
end
local function boundaries(camera,w,h)
  local x0,y0=camera:worldToScreen(0,0)
  local x1,y1=camera:worldToScreen(C.mapScale,C.mapScale)
  love.graphics.setColor(0,0,0,0.09)
  if x0>0 then
    -- Preserve the 9% reference edge shade everywhere EXCEPT inside the
    -- Node-authoritative west gorge / basins / waterfall.
    SecretMap.shadeOutside(camera,w,h)
  end
  if x1<w then love.graphics.rectangle("fill",math.max(0,x1),0,w-math.max(0,x1),h) end
  if y0>0 then love.graphics.rectangle("fill",0,0,w,math.min(h,y0)) end
  if y1<h then love.graphics.rectangle("fill",0,math.max(0,y1),w,h-math.max(0,y1)) end
end

-- Reuse five render buckets instead of checking every structure five times.
-- Preserve the authoritative object paint order within each layer.
local buckets={[-1]={},[0]={},[1]={},[2]={},[3]={}}
local function prepareLayers(objects,camera,w,h)
  for _,list in pairs(buckets) do
    for i=#list,1,-1 do list[i]=nil end
  end
  for i=1,#objects do
    local o=objects[i]
    local target=buckets[Objects.layer(o)]
    if target and see(o,camera,w,h,tonumber(o.scale) or 100) then
      target[#target+1]=o
    end
  end
end
local function drawObjectLayer(camera,layer)
  for _,o in ipairs(buckets[layer]) do
    local x,y=camera:worldToScreen(o.x,o.y)
    Objects.draw(o,x+(o.wiggleX or 0)*camera.zoom,
      y+(o.wiggleY or 0)*camera.zoom,camera.zoom)
  end
end
-- Packet X includes the projectile TYPE, not an image name or diameter.
-- Resolve the actual source and dimensions from the original items list.
-- Four types use original sprites; two are original Canvas circles.
function View.projectileStyle(projectile)
  if type(projectile)~="table" or type(projectile.indx)~="number"
    or projectile.indx%1~=0 then return nil end
  local spec=Catalog.projectiles[projectile.indx+1]
  if not spec or type(spec.scale)~="number" then return nil end
  return {
    layer=projectile.layer or spec.layer or 0,
    radius=spec.scale,
    src=spec.src,
    circle=not spec.src and spec.indx==1
  }
end
local function drawProjectiles(world,camera,w,h,layer)
  for _,p in pairs(world.projectiles) do
    local spec=View.projectileStyle(p)
    if spec and spec.layer==layer and
      see(p,camera,w,h,spec.radius) then
      local x,y=camera:worldToScreen(p.visualX or p.x,p.visualY or p.y)
      love.graphics.push("all")
      love.graphics.translate(x,y)
      love.graphics.rotate(p.dir or 0)
      if spec.src then
        -- The original drawImage uses (scale,scale) image dimensions;
        -- no zoom is applied twice when rotating the actual source PNG.
        Assets.draw("weapons",spec.src..".png",0,0,
          spec.radius*camera.zoom,spec.radius*camera.zoom)
      elseif spec.circle then
        Shapes.circle(0,0,spec.radius*camera.zoom,
          "#939393",Shapes.outline)
      end
      love.graphics.pop()
    end
  end
end
-- Crab King's surface/dive states originate from the Node I packet.
-- No alternative artwork is fabricated for underwater states.
function View.animalOpacity(animal,kind)
  if not kind or not kind.boss then return 1 end
  if animal.state==2 then return 0.2 end
  if animal.state==1 then return 0.55 end
  if animal.state==3 then return 0.7 end
  return 1
end
local function renderAnimal(a,camera,world)
  local kind=world and world:animalKind(a.index) or Animals.byId(a.index)
  if not kind or not kind.src then return end
  local x,y=camera:worldToScreen(a.visualX or a.x,a.visualY or a.y)
  -- renderAI: tmpScale = scale * 1.2 * spriteMlt
  local radius=kind.scale*1.2*(kind.spriteMlt or 1)*camera.zoom
  local angle=(a.dir or 0)+(a.dirPlus or 0)-pi/2
  local alpha=View.animalOpacity(a,kind)
  -- Only real supplied PNGs: an absent enemy sprite must not make
  -- a server-authoritative enemy completely invisible.
  local rendered=Assets.draw("animals",kind.src..".png",
    x,y,radius*2,radius*2,angle,alpha)
  if not rendered then
    local candidate=Animals.fallbackArt and Animals.fallbackArt[kind.src]
    if candidate then
      Assets.draw("animals",candidate..".png",
        x,y,radius*2,radius*2,angle,alpha)
    end
  end
end
local function drawWeapon(weapon,variant,scale)
  local filename,fallback=Assets.weaponFilename(
    weapon.src,variants[variant or 0] or "")
  if not filename then return end
  -- The upstream has no bow_1_d.png. Use only the EXISTING original bow
  -- image in this exceptional case, never a newly invented sprite.
  local x,y=scale+(weapon.xOff or 0),(weapon.yOff or 0)
  local ok=Assets.draw("weapons",filename,x,y,weapon.length,weapon.width)
  if not ok and not fallback and variant and variant~=0 then
    Assets.draw("weapons",weapon.src..".png",x,y,
      weapon.length,weapon.width)
  end
  local proj=type(weapon.projectile)=="number"
    and Catalog.projectiles[weapon.projectile+1] or nil
  if proj and not weapon.hideProjectile and proj.src then
    Assets.draw("weapons",proj.src..".png",scale,0,proj.scale,proj.scale)
  end
end
local function drawTail(player)
  local tailId=player.tail
  local tail=type(tailId)=="number" and tailById[tailId] or nil
  if not tail then return end
  local x=-20-(tail.xOff or 0)
  Assets.draw("accessories","access_"..tailId..".png",x,0,
    tail.scale,tail.scale,tail.spin and (player.skinRot or 0) or 0)
end
local function drawHat(player)
  local hatId=player.skin
  local hat=type(hatId)=="number" and hatById[hatId] or nil
  if not hat then return end
  love.graphics.push()
  love.graphics.rotate(pi/2)
  Assets.draw("hats","hat_"..hatId..".png",0,0,hat.scale,hat.scale)
  if hat.topSprite then
    Assets.draw("hats","hat_"..hatId.."_top.png",0,0,
      hat.scale,hat.scale,player.skinRot or 0)
  end
  love.graphics.pop()
end
local function drawHeldItem(index,scale)
  local item=Catalog.itemById(index)
  if not item then return end
  local image=Objects.sprite({id=index,scale=item.scale})
  if image then
    local center=scale-(item.holdOffset or 0)+image:getWidth()/2
    love.graphics.setColor(1,1,1)
    love.graphics.draw(image,center,0,0,1,1,
      image:getWidth()/2,image:getHeight()/2)
  end
end
local function playerBody(p,dt)
  local scale=p.scale or C.playerScale
  local weapon=Catalog.weaponById(p.weaponIndex or 0)
  local build=type(p.buildIndex)=="number" and p.buildIndex or -1
  local armAngle=(pi/4)*((weapon and weapon.armS) or 1)
  local handAngle=build<0 and ((weapon and weapon.hndS) or 1) or 1
  local handDist=build<0 and ((weapon and weapon.hndD) or 1) or 1
  local col=skinColors[(tonumber(p.skinColor) or 0)+1] or skinColors[1]
  drawTail(p)
  if weapon and build<0 and not weapon.aboveHand then
    drawWeapon(weapon,p.variant,scale)
  end
  Shapes.circle(scale*cos(armAngle),scale*sin(armAngle),14,col,Shapes.outline)
  Shapes.circle(scale*handDist*cos(-armAngle*handAngle),
    scale*handDist*sin(-armAngle*handAngle),14,col,Shapes.outline)
  if weapon and build<0 and weapon.aboveHand then
    drawWeapon(weapon,p.variant,scale)
  end
  if build>=0 then drawHeldItem(build,scale) end
  Shapes.circle(0,0,scale,col,Shapes.outline)
  drawHat(p)
end
-- The browser uses getAttackDir() for the LOCAL player and the server's
-- direction for everyone else. Neither choice changes combat authority.
-- Both gameplay aim updates and local rendering use this same rule.
-- The server's K(0) locks direction; drawing must not keep tracking
-- the mouse after it has stopped receiving new direction packets.
function View.localAim(locked,cursor,lastSent)
  if locked then
    return type(lastSent)=="number" and lastSent or 0
  end
  return type(cursor)=="number" and cursor or 0
end
function View.playerDrawAngle(player,localAim)
  local direction=type(localAim)=="number" and localAim or (player.dir or 0)
  return direction+(player.dirPlus or 0)
end
-- Node setDive sends m(sid,state,duration) for player sprites, just as I
-- carries states for the Crab King. Fade the EXACT body/weapon/hat PNGs and
-- primitives in place; no replacement, fake sprite, or predicted movement.
function View.playerOpacity(player)
  if not player then return 1 end
  if player.dive==1 then return 0.55 end
  if player.dive==2 then return 0.2 end
  if player.dive==3 then return 0.7 end
  return 1
end
local diveShader=nil
local function playerDiveShader()
  if diveShader then return diveShader end
  -- Shape primitives use their own setColor calls; a shader multiplies
  -- their final alpha AND the original reference image alpha uniformly.
  diveShader=love.graphics.newShader([[
    uniform float diveOpacity;
    vec4 effect(vec4 color, Image texture, vec2 textureCoords, vec2 screenCoords) {
      vec4 originalPixel = Texel(texture, textureCoords) * color;
      return vec4(originalPixel.rgb, originalPixel.a * diveOpacity);
    }
  ]])
  return diveShader
end
local function drawPlayer(p,camera,dt,localAim)
  local x,y=camera:worldToScreen(p.visualX or p.x,p.visualY or p.y)
  p.skinRot=(p.skinRot or 0)+dt*1000*0.002
  love.graphics.push("all")
  local opacity=View.playerOpacity(p)
  if opacity<1 then
    local shader=playerDiveShader()
    shader:send("diveOpacity",opacity)
    love.graphics.setShader(shader)
  end
  love.graphics.translate(x,y)
  love.graphics.rotate(View.playerDrawAngle(p,localAim))
  love.graphics.scale(camera.zoom)
  playerBody(p,dt)
  love.graphics.pop()
end
local chatFont=nil
local function drawChatBubble(p,x,y,scale)
  if not p.chatMessage or (p.chatCountdown or 0)<=0 then return end
  if not chatFont then chatFont=love.graphics.newFont(32) end
  local previous=love.graphics.getFont()
  love.graphics.setFont(chatFont)
  local content=p.chatMessage
  local tw=chatFont:getWidth(content)
  local bubbleW=tw+17
  local bubbleH=47
  local cx=x
  local cy=y-scale-90
  love.graphics.setColor(0,0,0,0.2)
  love.graphics.rectangle("fill",cx-bubbleW/2,cy-bubbleH/2,bubbleW,bubbleH,6,6)
  love.graphics.setColor(1,1,1)
  love.graphics.print(content,cx-tw/2,cy-chatFont:getHeight()/2)
  love.graphics.setFont(previous)
end
-- Render labels at original Canvas world coordinates; CSS HUD is separate.
function View.isTeammate(world,p)
  local me=world:localPlayer()
  return p.sid==world.sid or (me and type(me.team)=="string"
    and #me.team>0 and p.team==me.team) or false
end
function View.playerNameVisible(world,p)
  -- JS hides the name and health bar of enemy skin 10 (Assassin).
  return p.skin~=10 or View.isTeammate(world,p)
end
function View.animalName(a,world)
  local kind=world and world:animalKind(a.index) or Animals.byId(a.index)
  if not kind then return nil end
  if type(kind.name)=="string" then return kind.name end
  if type(a.nameIndex)=="number" and a.nameIndex%1==0 then
    return C.cowNames[a.nameIndex+1]
  end
  return nil
end
local labelFonts={}
local function font(size)
  size=math.max(10,math.floor(size))
  if not labelFonts[size] then labelFonts[size]=love.graphics.newFont(size) end
  return labelFonts[size]
end
local function labelText(content,sz)
  if type(content)~="string" or content=="" then return 0 end
  local f=font(sz)
  love.graphics.setFont(f)
  local w=f:getWidth(content)
  local top=-C.nameY
  -- JS uses strokeText with darkOutlineColor and rounded 8/11px stroke.
  Shapes.color(Shapes.darkOutline)
  local radius=(sz==30) and 4 or 5.5
  for i=0,7 do
    local angle=i*pi/4
    love.graphics.print(content,-w/2+cos(angle)*radius,
      top-f:getHeight()/2+sin(angle)*radius)
  end
  love.graphics.setColor(1,1,1)
  love.graphics.print(content,-w/2,top-f:getHeight()/2)
  return w
end
function View.healthBarOffset(entityScale)
  return 2*(entityScale or C.playerScale)+C.nameY
end
local function labelHealth(health,maxHealth,friendly,entityScale)
  if type(health)~="number" or health<=0
    or type(maxHealth)~="number" or maxHealth<=0 then return end
  local bar=C.healthBarWidth
  local pad=C.healthBarPad
  local ratio=math.max(0,math.min(1,health/maxHealth))
  local offset=View.healthBarOffset(entityScale)
  Shapes.color(Shapes.darkOutline)
  love.graphics.rectangle("fill",-bar-pad,offset,bar*2+pad*2,17,8,8)
  Shapes.color(friendly and "#8ecc51" or "#cc5151")
  love.graphics.rectangle("fill",-bar,offset+pad,bar*2*ratio,
    17-pad*2,7,7)
end
local function labels(world,camera,w,h)
  local previous=love.graphics.getFont()
  -- Original Canvas lists all players before animals, in creation order.
  for _,p in ipairs(world:orderedPlayers()) do
    -- The reference draws all server-visible bodies and labels, even when
    -- the centre is outside the viewport; broad cosmetics can cross an edge.
    if p.x and p.y and p.invisible~=1 then
      if View.playerNameVisible(world,p) then
        local x,y=camera:worldToScreen(p.visualX or p.x,p.visualY or p.y)
        local s=p.scale or C.playerScale
        love.graphics.push()
        love.graphics.translate(x,y-s*camera.zoom)
        love.graphics.scale(camera.zoom)
        local name=(type(p.team)=="string" and
          "["..p.team.."] " or "")..tostring(p.name or "")
        local textWidth=labelText(name,30)
        if p.isLeader==1 or p.isLeader==true then
          Assets.draw("icons","crown.png",
            -textWidth/2-C.crownPad,-C.nameY-5,
            C.crownIconScale,C.crownIconScale)
        end
        if p.icon==1 then
          Assets.draw("icons","skull.png",
            textWidth/2+C.crownPad,-C.nameY-5,
            C.crownIconScale,C.crownIconScale)
        end
        labelHealth(p.health,p.maxHealth,View.isTeammate(world,p),s)
        love.graphics.pop()
      end
    end
  end
  for _,a in ipairs(world:orderedAnimals()) do
    if a.x and a.y then
      local kind=world and world:animalKind(a.index) or Animals.byId(a.index)
      if kind then
        local x,y=camera:worldToScreen(a.visualX or a.x,a.visualY or a.y)
        love.graphics.push()
        love.graphics.translate(x,y-(kind.scale or 75)*camera.zoom)
        love.graphics.scale(camera.zoom)
        labelText(View.animalName(a,world),kind.nameScale or 30)
        labelHealth(a.health,kind.health,false,kind.scale)
        love.graphics.pop()
      end
    end
  end
  love.graphics.setFont(previous)
  -- Original updateGame calls textManager.update after all labels and
  -- before chat speech bubbles. The lifetime advances in World:update.
  CombatText.draw(world.combatText,camera)
  -- In client/src/index.js speech bubbles come after all world name/HP labels.
  for _,p in ipairs(world:orderedPlayers()) do
    if p.x and p.y and p.invisible~=1 then
      local x,y=camera:worldToScreen(p.visualX or p.x,p.visualY or p.y)
      drawChatBubble(p,x,y,(p.scale or C.playerScale)*camera.zoom)
    end
  end
end
function View.draw(world,camera,dt,options)
  -- Generate at most three expensive new object sprites per frame.
  -- They are cached permanently; deferred sprites show next frame.
  Objects.beginFrame(3)
  local w,h=love.graphics.getDimensions()
  -- Aiming is local presentation only. The actual attack and target
  -- direction are still transmitted via the original D/F Node packets.
  local function aimFor(player)
    if player.sid==world.sid and options then return options.localAim end
    return nil
  end
  View.advanceWater(dt or 0)
  ground(camera,w,h)
  if not options or options.showGrid~=false then
    grid(camera,w,h)
  end
  -- Show server-defined attack areas on the ground, below animals/players.
  -- This makes the imminent boss hit visible without changing collisions.
  BossEffects.draw(world.bossEffects,camera)
  local objects=world:orderedObjects()
  prepareLayers(objects,camera,w,h)
  -- The JS engine iterates the same players[] and ais[] arrays for each
  -- rendering pass, preserving overlap and zIndex across frames.
  local players=world:orderedPlayers()
  local animals=world:orderedAnimals()
  drawObjectLayer(camera,-1)
  drawProjectiles(world,camera,w,h,0)
  for _,p in ipairs(players) do
    if (p.zIndex or 0)==0 and p.x and p.y and p.invisible~=1
      then drawPlayer(p,camera,dt or 0,aimFor(p)) end
  end
  for _,a in ipairs(animals) do
    local kind=world and world:animalKind(a.index) or Animals.byId(a.index)
    if kind and a.x and a.y then renderAnimal(a,camera,world) end
  end
  drawObjectLayer(camera,0)
  drawProjectiles(world,camera,w,h,1)
  drawObjectLayer(camera,1)
  for _,p in ipairs(players) do
    if (p.zIndex or 0)==1 and p.x and p.y and p.invisible~=1
      then drawPlayer(p,camera,dt or 0,aimFor(p)) end
  end
  drawObjectLayer(camera,2)
  drawObjectLayer(camera,3)
  boundaries(camera,w,h)
  -- The JS reference composites this violet-blue tint after game objects
  -- and before world labels, not over the HTML/CSS HUD.
  love.graphics.setColor(0,0,70/255,0.35)
  love.graphics.rectangle("fill",0,0,w,h)
  love.graphics.setColor(1,1,1,1)
  labels(world,camera,w,h)
end
return View
