-- Focused regression for the annotated gameplay screenshot.
return function()
  local Animals=require("src.game.animals")
  local Assets=require("src.game.reference_assets")
  local Config=require("src.game.config")
  local World=require("src.game.world_state")
  local View=require("src.game.reference_view")
  local Camera=require("src.camera")
  local Hud=require("src.game.reference_hud")
  for original,fallback in pairs(Animals.fallbackArt) do
    assert(Assets.get("animals",fallback..".png"),
      "Upload fallback cannot be loaded for "..original)
  end
  assert(Animals.byId(10).src=="yeti_1")
  assert(Animals.fallbackArt[Animals.byId(10).src]=="vince")
  local world=World.new()
  local camera=Camera.new()
  camera:follow(Config.mapScale/2,Config.mapScale/2)
  local can=love.graphics.newCanvas(1280,720)
  love.graphics.push("all")
  love.graphics.setCanvas(can)
  love.graphics.clear(0,0,0,0)
  View.draw(world,camera,0.016,{showGrid=true})
  love.graphics.pop()
  can:release()
  -- Render only the HUD on transparent canvas. The old large opaque
  -- blocks around AGE and inventory must not return.
  local overlay=love.graphics.newCanvas(1280,720)
  love.graphics.push("all")
  love.graphics.setCanvas(overlay)
  love.graphics.clear(0,0,0,0)
  Hud.draw(world,false,"",true)
  love.graphics.pop()
  local source=overlay:newImageData()
  local _,_,_,ageAlpha=source:getPixel(640,566)
  assert(ageAlpha<0.1,"The unwanted AGE background box is back")
  overlay:release()
  print("MOO IO HUD PASS: fallback art and original unboxed HUD")
end
