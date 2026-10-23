
-- One-touch Android abilities, backed ONLY by the original MooMoo.io packets.
-- Weapons are equipped (z); the game's real consumables and structures are
-- activated by selecting them (z) and using the existing F(1)/F(0) action.
-- The server remains authoritative for resources, eligibility and placement.
local Slots=require("src.mobile.slots")
local Catalog=require("src.game.catalog")
local A={}
function A.activate(world,index,direction,send,packetNull,manualHeld)
  local id,isWeapon=Slots.at(world,index)
  if id==nil then return false,"Opcao nao desbloqueada." end
  if type(send)~="function" then return false,"Transporte indisponivel." end
  if isWeapon then
    if not Catalog.weaponById(id) then return false,"Arma desconhecida." end
    return send("z",{id,true})
  end
  local item=Catalog.itemById(id)
  if not item then return false,"Acao desconhecida." end
  -- A second pointer can hold fire while tapping skills. In that situation,
  -- equip the structure/food, but let the attack finger do the actual action:
  -- do NOT send F(0), which would cancel the already held manual fire.
  local p=world and world.localPlayer and world:localPlayer()
  local selected=p and p.buildIndex==id
  if not selected then
    local ok,err=send("z",{id,false})
    if not ok then return false,err end
  end
  if manualHeld then return true,"armed" end
  local ok,err=send("F",{1,direction})
  if not ok then return false,err end
  -- Never turn off auto-gather (K); only stop this single F press.
  local stopped,why=send("F",{0,packetNull})
  if not stopped then return false,why end
  return true,item.consume and "consume" or "build"
end
return A
