-- Faithful display-only port of the archived client/src/libs/animText.js
-- and client/src/index.js::showText. Damage/heal numbers originate ONLY from
-- the real Node server's "8" packet. No client-calculated combat events.
local Text={}
local fonts={}
local function finite(n)
  return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge
end

local function formatAmount(value)
  local amount=math.abs(value)
  if amount==math.floor(amount) then return string.format("%.0f",amount) end
  return tostring(amount)
end

function Text.spawn(collection,x,y,value)
  if type(collection)~="table" or not finite(x) or not finite(y)
    or not finite(value) then return false end
  -- Prevent an attacker-controlled flood of authenticated display packets
  -- from retaining an unbounded number of ephemeral text objects.
  if #collection>=128 then table.remove(collection,1) end
  collection[#collection+1]={
    x=x,y=y,scale=50,startScale=50,maxScale=75,scaleSpeed=0.7,
    speed=0.18,life=500,
    text=formatAmount(value),
    color=value>=0 and "damage" or "healing"
  }
  return true
end

function Text.update(collection,dt)
  if type(collection)~="table" or not finite(dt) or dt<=0 then return end
  local delta=dt*1000 -- LÖVE seconds -> original JS milliseconds.
  for i=#collection,1,-1 do
    local t=collection[i]
    if t.life>0 then
      t.life=t.life-delta
      t.y=t.y-t.speed*delta
      t.scale=t.scale+t.scaleSpeed*delta
      if t.scale>=t.maxScale then
        t.scale=t.maxScale
        t.scaleSpeed=t.scaleSpeed*-1
      elseif t.scale<=t.startScale then
        t.scale=t.startScale
        t.scaleSpeed=0
      end
    end
    if t.life<=0 then table.remove(collection,i) end
  end
end

local function font(size)
  size=math.floor(size+0.5)
  if not fonts[size] then fonts[size]=love.graphics.newFont(size) end
  return fonts[size]
end

function Text.draw(collection,camera)
  if type(collection)~="table" or not camera then return end
  local gfx=love.graphics
  gfx.push("all")
  for _,t in ipairs(collection) do
    if t.life>0 then
      local x,y=camera:worldToScreen(t.x,t.y)
      local f=font(t.scale)
      gfx.setFont(f)
      if t.color=="healing" then
        gfx.setColor(142/255,204/255,81/255,1)
      else
        gfx.setColor(1,1,1,1)
      end
      gfx.push()
      gfx.translate(x,y)
      gfx.scale(camera.zoom)
      -- JS uses textAlign='center' and textBaseline='middle'.
      gfx.print(t.text,-f:getWidth(t.text)/2,-f:getHeight()/2)
      gfx.pop()
    end
  end
  gfx.pop()
end

return Text
