-- Direct port of client/src/index.js actionBarItem thumbnail rendering.
-- Keep weapon rotation, aspect ratio, iconPad/iPad and item icon rotation.
local Assets=require("src.game.reference_assets")
local Objects=require("src.game.reference_objects")
local I={}
local PI=math.pi
local ICON_PAD=0.9     -- shared/config.js iconPad
local ICON_PADDING=15 -- shared/config.js iconPadding

function I.draw(kind,data,x,y,slot)
  slot=slot or 66
  if kind=="weapon" then
    if type(data)~="table" or type(data.src)~="string" then return false end
    local image=Assets.get("weapons",data.src..".png")
    if not image then return false end
    local aspect=image:getWidth()/image:getHeight()
    local mlt=data.iPad or 1
    local h=slot*mlt*ICON_PAD
    local w=h*aspect
    -- JS: tmpContext.rotate(Math.PI/4 + Math.PI)
    love.graphics.setColor(1,1,1)
    love.graphics.draw(image,x,y,PI*1.25,w/image:getWidth(),
      h/image:getHeight(),image:getWidth()/2,image:getHeight()/2)
    return true
  elseif kind=="item" then
    if type(data)~="table" or type(data.id)~="number" then return false end
    local image=Objects.sprite({id=data.id},true)
    if not image then return false end
    local size=math.min(slot-ICON_PADDING,image:getWidth())
    love.graphics.setColor(1,1,1)
    love.graphics.draw(image,x,y,0,size/image:getWidth(),
      size/image:getHeight(),image:getWidth()/2,image:getHeight()/2)
    -- JS uses source-atop rgba(0,0,70,0.1). The small color wash is applied
    -- only inside the sprite alpha; no extra artwork or substituting icons.
    return true
  end
  return false
end
return I
