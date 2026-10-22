-- Canvas getResSprite/getItemSprite port from client/src/index.js.
-- The shape, palette, rotation and cache keys follow the JavaScript source.
-- Objects are rendered ONLY when received from the authoritative Node server.
local C=require("src.game.config")
local Catalog=require("src.game.catalog")
local P=require("src.game.reference_primitives")
local O={}
local cache={}
local pi=math.pi
local cos,sin=math.cos,math.sin
local function randomInt(a,b)
  a=math.ceil(a);b=math.floor(b)
  if b<a then return a end
  return love.math.random(a,b)
end
local function resourceBiome(y)
  if y>=C.mapScale-C.snowBiomeTop then return 2 end
  if y<=C.snowBiomeTop then return 1 end
  return 0
end
function O.layer(obj)
  local id=obj and obj.id
  if type(id)=="number" then
    local item=Catalog.itemById(id)
    if item then
      local group=Catalog.groupById(item.groupId)
      return group and group.layer or 2
    end
  end
  if obj.type==0 then return 3 end
  if obj.type==2 then return 0 end
  if obj.type==4 then return -1 end
  return 2
end
local function drawResource(typ,s,biome)
  local snowOrDesert=biome~=0
  if typ==0 then
    for i=0,1 do
      local scale=s*(i==0 and 1 or 0.5)
      local color=snowOrDesert and (i==0 and "#e3f1f4" or "#ffffff")
        or (i==0 and "#9ebf57" or "#b4db62")
      -- Organic rounded canopy instead of sharp seven-point star.
      P.blob(8,scale,scale*0.86,color,i==0 and P.outline or nil)
    end
  elseif typ==1 then
    if biome==2 then
      P.star(6,s*0.3,s*0.71,"#606060",P.outline)
      P.circle(0,0,s*0.55,"#89a54c",P.outline)
      P.circle(0,0,s*0.3,"#a5c65b")
    else
      P.blob(6,s,s*0.7,biome==1 and "#e3f1f4" or "#89a54c",P.outline)
      local berryColor=biome==1 and "#6a64af" or "#c15555"
      for i=0,3 do
        local range=randomInt(s/3.5,s/2.3)
        P.circle(range*cos(pi*i/2),range*sin(pi*i/2),
          randomInt(10,12),berryColor,P.outline)
      end
    end
  elseif typ==2 or typ==3 then
    local base=typ==3 and "#e0c655" or (biome==2 and "#938d77" or "#939393")
    local light=typ==3 and "#ebdca3" or (biome==2 and "#b2ab90" or "#bcbcbc")
    P.star(3,s,s,base,P.outline)
    P.star(3,s*0.55,s*0.65,light)
  else
    return false
  end
  return true
end
local function drawItem(item)
  local name=item.name
  local s=item.scale
  if name=="apple" then
    P.circle(0,0,s,"#c15555",P.outline)
    P.leaf(0,-s,25,0,"#89a54c",P.outline)
  elseif name=="cookie" or name=="cheese" then
    P.circle(0,0,s,name=="cookie" and "#cca861" or "#f4f3ac",P.outline)
    for i=0,3 do
      local dist=randomInt(s/2.5,s/1.7)
      P.circle(dist*cos(pi*i/2),dist*sin(pi*i/2),
        randomInt(4,5),name=="cookie" and "#937c4b" or "#c3c28b")
    end
  elseif name=="wood wall" or name=="stone wall" or name=="castle wall" then
    local castle=name=="castle wall"
    local wood=name=="wood wall"
    local base=castle and "#83898e" or (wood and "#a5974c" or "#939393")
    local top=castle and "#9da4aa" or (wood and "#c9b758" or "#bcbcbc")
    local sides=castle and 4 or 3
    P.star(sides,s*1.1,s*1.1,base,P.outline)
    P.star(sides,s*0.65,s*0.65,top)
  elseif name=="spikes" or name=="greater spikes"
    or name=="poison spikes" or name=="spinning spikes" then
    local center=s*0.6
    P.star(name=="spikes" and 5 or 6,s,center,
      name=="poison spikes" and "#7b935d" or "#939393",P.outline)
    P.circle(0,0,center,"#a5974c",P.outline)
    P.circle(0,0,center/2,"#c9b758")
  elseif name=="windmill" or name=="faster windmill" or name=="power mill" then
    P.circle(0,0,s,"#a5974c",P.outline)
    P.rectCircle(0,0,s*1.5,29,4,"#c9b758",P.outline)
    P.circle(0,0,s*0.5,"#a5974c",P.outline)
  elseif name=="mine" then
    P.star(3,s,s,"#939393",P.outline)
    P.star(3,s*0.55,s*0.65,"#bcbcbc")
  elseif name=="sapling" then
    for i=0,1 do
      local scale=s*(i==0 and 1 or 0.5)
      P.star(7,scale,scale*0.7,i==0 and "#9ebf57" or "#b4db62",
        i==0 and P.outline or nil)
    end
  elseif name=="pit trap" then
    P.star(3,s*1.1,s*1.1,"#a5974c",P.outline)
    P.star(3,s*0.65,s*0.65,P.outline)
  elseif name=="boost pad" then
    P.rect(0,0,s*2,s*2,"#7e7f82",P.outline)
    P.triangle(s,"#dbd97d")
  elseif name=="turret" then
    P.circle(0,0,s,"#a5974c",P.outline)
    P.rect(0,-25,s*0.9,50,"#939393")
    P.circle(0,0,s*0.6,"#939393",P.outline)
  elseif name=="platform" then
    local total=s*2
    local width=total/4
    local x=-s/2
    for _=1,4 do
      P.rect(x-width/2,0,width,total,"#cebd5f",P.outline)
      x=x+total/4
    end
  elseif name=="healing pad" then
    P.rect(0,0,s*2,s*2,"#7e7f82",P.outline)
    P.rectCircle(0,0,s*0.65,20,4,"#db6e6e",nil)
  elseif name=="spawn pad" then
    P.rect(0,0,s*2,s*2,"#7e7f82",P.outline)
    P.circle(0,0,s*0.6,"#71aad6",P.outline)
  elseif name=="blocker" then
    P.circle(0,0,s,"#7e7f82",P.outline)
    love.graphics.push();love.graphics.rotate(pi/4)
    P.rectCircle(0,0,s*0.65,20,4,"#db6e6e",nil)
    love.graphics.pop()
  elseif name=="teleporter" then
    P.circle(0,0,s,"#7e7f82",P.outline)
    love.graphics.push();love.graphics.rotate(pi/4)
    P.circle(0,0,s*0.5,"#d76edb")
    love.graphics.pop()
  else
    return false
  end
  return true
end

local function buildSprite(key,size,rotation,draw)
  if cache[key]~=nil then return cache[key] or nil end
  local dim=math.floor(size)
  if dim<2 or dim>1200 then return nil end
  local image=love.graphics.newCanvas(dim,dim)
  image:setFilter("linear","linear")
  love.graphics.push("all")
  love.graphics.setCanvas(image)
  -- A sprite can be requested for the first time while a player is
  -- translated, rotated or scaled. Canvas rendering must start in its own
  -- coordinate system, or the sprite is rasterized outside its texture and
  -- becomes invisible even while its inventory icon remains visible.
  love.graphics.origin()
  love.graphics.setShader()
  love.graphics.setScissor()
  love.graphics.clear(0,0,0,0)
  love.graphics.translate(dim/2,dim/2)
  love.graphics.rotate(rotation)
  love.graphics.setLineStyle("smooth")
  local ok=draw()
  love.graphics.pop()
  if not ok then
    cache[key]=false
    return nil
  end
  cache[key]=image
  return image
end

function O.sprite(obj,asIcon)
  local item=type(obj.id)=="number" and Catalog.itemById(obj.id) or nil
  if item then
    -- getItemSprite(asIcon): action bar uses 0-degree rotation and a stroke
    -- scaled to canvas width/81. World items use a 90-degree rotation.
    local key=(asIcon and "item-icon:" or "item:")..tostring(item.id)
    local size=item.scale*2.5+P.width+(item.spritePadding or 0)
    return buildSprite(key,size,asIcon and 0 or pi/2,function()
      local originalWidth=P.width
      if asIcon then P.width=originalWidth*(math.floor(size)/81) end
      local ok=drawItem(item)
      P.width=originalWidth
      return ok
    end)
  end
  local typ,scale=obj.type,obj.scale
  if type(typ)~="number" or type(scale)~="number" then return nil end
  local biome=resourceBiome(obj.y)
  local key=table.concat({"res",typ,scale,biome},":")
  return buildSprite(key,scale*2.1+P.width,love.math.random()*pi,
    function() return drawResource(typ,scale,biome) end)
end
-- Original GameObject.init copies these visual properties from items.list.
-- Packet H transmits only id/owner, so restore them from the same static
-- catalog used by the server. Do not create any new world entities.
function O.renderStyle(obj)
  local item=obj and type(obj.id)=="number" and Catalog.itemById(obj.id)
  if not item then return 1,nil end
  return item.hideFromEnemy and 0.6 or 1,item.blocker
end
function O.draw(obj,x,y,zoom)
  local sprite=O.sprite(obj)
  if not sprite then return false end
  local alpha,blocker=O.renderStyle(obj)
  -- JS renderGameObjects: translate/rotate the whole object, draw its sprite,
  -- then render the blocker radius in translucent red over the world.
  love.graphics.push("all")
  love.graphics.translate(x,y)
  love.graphics.rotate(type(obj.id)=="number" and (obj.dir or 0) or 0)
  love.graphics.scale(zoom or 1)
  love.graphics.setColor(1,1,1,alpha)
  love.graphics.draw(sprite,0,0,0,1,1,
    sprite:getWidth()/2,sprite:getHeight()/2)
  if type(blocker)=="number" and blocker>0 then
    love.graphics.setColor(219/255,110/255,110/255,0.3)
    love.graphics.setLineWidth(6)
    love.graphics.circle("line",0,0,blocker)
  end
  love.graphics.pop()
  return true
end
return O
