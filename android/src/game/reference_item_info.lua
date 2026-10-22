-- MooMoo.io client #itemInfoHolder port. Source:
-- client/src/index.js showItemInfo(item,isWeapon,isStoreItem)
-- client/public/css/main.css: left:20px top:20px max-width:250px.
-- Uses ONLY values from shared/config/items.js and the server's S packets.
local Catalog=require("src.game.catalog")
local Info={}
local fonts={}
local function titleCase(s)
  return (s or ""):gsub("^%l",string.upper)
end
function Info.describe(entry,world)
  if not entry or type(entry.data)~="table" then return nil end
  local item=entry.data
  local info={name=titleCase(item.name),description=item.desc or "",
    requirements={},count=nil,limit=nil,kind=entry.kind}
  if entry.kind=="weapon" then
    info.class=item.type==0 and "primary" or "secondary"
  elseif entry.kind=="item" then
    local req=item.req or {}
    for i=1,#req-1,2 do
      if type(req[i])=="string" and type(req[i+1])=="number" then
        info.requirements[#info.requirements+1]={
          name=req[i],amount=req[i+1],
          owned=world.resources[req[i]] or 0
        }
      end
    end
    local group=Catalog.groupById(item.groupId)
    if group and group.limit then
      info.count=world.itemCounts[group.id] or 0
      info.limit=group.limit
    end
  elseif entry.kind=="store" then
    info.price=item.price
  end
  return info
end
local function font(size)
  if not fonts[size] then fonts[size]=love.graphics.newFont(size) end
  return fonts[size]
end
local function put(str,x,y,size,r,g,b)
  local gfx=love.graphics
  local f=font(size)
  gfx.setFont(f)
  gfx.setColor(r or 1,g or 1,b or 1)
  gfx.print(tostring(str),x,y)
  return f:getHeight()
end
function Info.draw(entry,world)
  local info=Info.describe(entry,world)
  if not info then return false end
  local gfx=love.graphics
  local left,top,width=20,20,250
  local descFont=font(22)
  local wrapWidth=width-16
  local _,wrap=descFont:getWrap(info.description,wrapWidth)
  local descLines=math.max(1,#wrap)
  local lines=#info.requirements+(info.class and 1 or 0)
    +(info.price and 1 or 0)
  local height=10+font(30):getHeight()+8+
    descLines*descFont:getHeight()+math.max(0,lines)*27+
    ((info.limit~=nil) and 28 or 0)+12
  gfx.push("all")
  gfx.setColor(0,0,0,0.25)
  gfx.rectangle("fill",left,top,width,height,4,4)
  local x,y=left+10,top+5
  put(info.name,x,y,30)
  y=y+font(30):getHeight()+4
  gfx.setColor(1,1,1,0.65)
  gfx.setFont(descFont)
  gfx.printf(info.description,x,y,wrapWidth,"left")
  y=y+descLines*descFont:getHeight()+8
  if info.class then
    y=y+put(info.class,x,y,22)
  end
  if info.price then
    y=y+put("Price: "..tostring(info.price).." coins",x,y,22)
  end
  for _,req in ipairs(info.requirements) do
    put(req.name,x,y,22)
    local f=font(22)
    gfx.setFont(f)
    local label=" x"..tostring(req.amount)
    gfx.setColor(1,1,1,0.6)
    gfx.print(label,x+f:getWidth(req.name),y)
    y=y+f:getHeight()
  end
  if info.limit~=nil then
    put(tostring(info.count).."/"..tostring(info.limit),
      left+width-80,top+height-30,22)
  end
  gfx.pop()
  return true
end
return Info
