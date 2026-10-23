-- Port of client/src/index.js::updateUpgrades and CSS #upgradeHolder.
-- The Node.js server remains authoritative: clicking sends the original H packet.
local Catalog=require("src.game.catalog")
local Assets=require("src.game.reference_assets")
local Objects=require("src.game.reference_objects")
local Icons=require("src.game.reference_icons")
local U={}
local SLOT=66
local GAP=10
local TOP=10
local MOBILE=love.system and love.system.getOS and love.system.getOS()=="Android"
  or os.getenv("MOO_IO_FORCE_ANDROID_E2E")=="1"
local function topFor() return MOBILE and 113 or TOP end

local function owns(entries,id)
  for _,v in ipairs(entries or {}) do
    if v==id then return true end
  end
  return false
end

function U.offers(world)
  local list={}
  if (world.upgradePoints or 0)<=0 then return list end
  local age=world.upgradeAge
  local inventory=world.inventory
  if type(age)~="number" or type(inventory)~="table" then return list end
  local weapons=inventory.weapons or {}
  local items=inventory.items or {}
  for i,weapon in ipairs(Catalog.weapons) do
    if weapon.age==age and
      (weapon.pre==nil or owns(weapons,weapon.pre)) then
      list[#list+1]={kind="weapon",index=i-1,id=weapon.id,data=weapon}
    end
  end
  for i,item in ipairs(Catalog.items) do
    if item.age==age and
      (item.pre==nil or owns(items,item.pre)) then
      list[#list+1]={kind="item",index=#Catalog.weapons+i-1,
        id=item.id,data=item}
    end
  end
  return list
end
local function leftFor(w,count)
  return (w-(count*SLOT+math.max(0,count-1)*GAP))/2
end

function U.draw(world,w)
  local offers=U.offers(world)
  local n=#offers
  if n==0 then return end
  local left=leftFor(w,n)
  local top=topFor()
  for i,entry in ipairs(offers) do
    local x=left+(i-1)*(SLOT+GAP)
    love.graphics.setColor(0,0,0,0.25)
    love.graphics.rectangle("fill",x,top,SLOT,SLOT,4,4)
    Icons.draw(entry.kind,entry.data,x+SLOT/2,top+SLOT/2,SLOT)
  end
  local font=love.graphics.getFont()
  love.graphics.setColor(1,1,1)
  love.graphics.printf("Select Items ("..tostring(world.upgradePoints)..")",
    0,top+SLOT+13,w,"center")
  love.graphics.setFont(font)
end

function U.hitTest(world,w,x,y)
  if type(x)~="number" or type(y)~="number" then return nil end
  local top=topFor()
  if y<top or y>=top+SLOT then return nil end
  local offers=U.offers(world)
  if #offers==0 then return nil end
  local start=leftFor(w,#offers)
  for i,offer in ipairs(offers) do
    local sx=start+(i-1)*(SLOT+GAP)
    if x>=sx and x<sx+SLOT then return offer.index end
  end
  return nil
end
return U
