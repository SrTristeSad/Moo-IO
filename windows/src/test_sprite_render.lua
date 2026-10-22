-- Regression: the first world sprite can be generated WHILE the engine
-- has a transformed player on the drawing stack. That sprite must not be
-- cached as an empty/transparent Canvas.
return function()
  local Objects=require("src.game.reference_objects")
  local Catalog=require("src.game.catalog")
  local testCanvas=love.graphics.newCanvas(1280,720)
  love.graphics.push("all")
  love.graphics.setCanvas(testCanvas)
  love.graphics.clear(0,0,0,0)
  love.graphics.translate(965,612)
  love.graphics.rotate(0.86)
  love.graphics.scale(1.8,1.8)
  local windmill=Objects.sprite({id=10,scale=Catalog.itemById(10).scale})
  local tree=Objects.sprite({type=0,scale=95,y=2000})
  love.graphics.pop()
  assert(windmill~=nil,"windmill world sprite was not created")
  assert(tree~=nil,"world resource sprite was not created")
  local function visible(sprite,name)
    local data=sprite:newImageData()
    local cx=math.floor(data:getWidth()/2)
    local cy=math.floor(data:getHeight()/2)
    local _,_,_,alpha=data:getPixel(cx,cy)
    assert(alpha>0.1,name.." is empty after being built under camera/player transform")
  end
  visible(windmill,"held windmill")
  visible(tree,"world tree")
  -- The inventory thumbnail has a different cache key. It must work too.
  local icon=Objects.sprite({id=10},true)
  assert(icon~=nil,"windmill inventory icon missing")
  visible(icon,"windmill inventory icon")
  print("MOO IO SPRITES PASS: world sprites and icons are opaque after transforms")
  testCanvas:release()
end
