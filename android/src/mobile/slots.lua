-- Shared mapping of server-owned weapon/item IDs onto mobile buttons.
-- Four first slots belong on the right, remaining entries appear in the centre.
-- Neither this module nor the client grants ownership or creates items.
local S={}
function S.list(world)
  local inv=world and world.inventory or {}
  local all={}
  for _,id in ipairs(inv.weapons or {}) do
    if type(id)=="number" then all[#all+1]={id=id,kind="weapon"} end
  end
  for _,id in ipairs(inv.items or {}) do
    if type(id)=="number" then all[#all+1]={id=id,kind="item"} end
  end
  return all
end
function S.at(world,index)
  if type(index)~="number" or index~=math.floor(index) or index<1 then return nil end
  local inv=world and world.inventory or {}
  local weapons=inv.weapons or {}
  if index<=#weapons then
    local id=weapons[index]
    if type(id)=="number" then return id,true end
    return nil
  end
  local items=inv.items or {}
  local id=items[index-#weapons]
  if type(id)=="number" then return id,false end
  return nil
end
function S.total(world)
  local inv=world and world.inventory or {}
  return #(inv.weapons or {})+#(inv.items or {})
end
function S.pages(world,perPage)
  perPage=perPage or 5
  return math.max(1,math.ceil(math.max(0,S.total(world)-4)/perPage))
end
return S
