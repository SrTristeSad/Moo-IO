-- Geometry and biome helpers from al007ex/moomoo-clone's
-- shared/config.js and server/src/moomoo/modules/effects.js
-- Reference: 06f7c1ca965a7628671676c8d9a7efd3997bb5e7
local C=require("src.game.config")
local G={}
local function hypot(x,y) return math.sqrt(x*x+y*y) end
function G.riverBounds(config)
  config=config or C
  local middle=config.mapScale/2
  return middle-config.riverWidth/2,middle+config.riverWidth/2
end
function G.isRiver(x,y,config)
  config=config or C
  local top,bottom=G.riverBounds(config)
  return x>=0 and y>=top and y<=bottom
end
function G.isSnow(y,config)
  config=config or C
  return y<=config.snowBiomeTop
end
function G.secretDistance(x,y,config)
  config=config or C
  local z=config.secretPool
  local middle=config.mapScale/2
  local n=-x
  local band=math.abs(y-middle)-z.gorgeHalf
  if x>=z.gorgeX0 then n=math.min(n,math.max(band,0)) end
  for _,p in ipairs(z.pool) do
    n=math.min(n,hypot(x-p[1],y-p[2])-p[3])
  end
  if math.abs(y-z.waterfall.y)<z.waterfall.half+60 and x<z.waterfall.x then
    n=math.min(n,math.abs(y-z.waterfall.y)-z.waterfall.half)
  end
  return n
end
function G.inSecretPool(x,y,config)
  config=config or C
  for _,p in ipairs(config.secretPool.pool) do
    if hypot(x-p[1],y-p[2])<=p[3]*0.9 then return true end
  end
  return false
end
function G.inSecretArea(x,y,config)
  return x<0 and G.secretDistance(x,y,config)<=0
end
return G
