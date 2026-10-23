-- Graphical map extension derived from the RUNNING Node server's
-- shared/config.js secretPool and modules/effects.js::secretDistance.
-- The archived JS renderer lacks this map extension: this is NOT a claim
-- of pixel-for-pixel parity with an unavailable official secret-area client.
-- Original river/biome geometry for x >= 0 stays untouched.
local Config=require("src.game.config")
local S={}
local sqrt,abs,min,max=math.sqrt,math.abs,math.min,math.max

-- Exact signed-distance union from server/src/moomoo/modules/effects.js:
-- >=0 is outside; <=0 means a valid secret position WEST of x=0.
function S.signedDistance(x,y)
  local secret=Config.secretPool
  local mid=Config.mapScale/2
  local distance=-x
  local band=abs(y-mid)-secret.gorgeHalf
  if x>=secret.gorgeX0 then
    distance=min(distance,max(band,0))
  end
  for _,pool in ipairs(secret.pool) do
    local dx,dy=x-pool[1],y-pool[2]
    distance=min(distance,sqrt(dx*dx+dy*dy)-pool[3])
  end
  local waterfall=secret.waterfall
  if abs(y-waterfall.y)<waterfall.half+60 and x<waterfall.x then
    distance=min(distance,abs(y-waterfall.y)-waterfall.half)
  end
  return distance
end
function S.inside(x,y)
  return type(x)=="number" and type(y)=="number"
    and x<0 and S.signedDistance(x,y)<=0
end
function S.inPool(x,y)
  if not S.inside(x,y) then return false end
  for _,pool in ipairs(Config.secretPool.pool) do
    local dx,dy=x-pool[1],y-pool[2]
    if dx*dx+dy*dy <= (pool[3]*0.9)^2 then return true end
  end
  return false
end
-- The server permits a rectangular gorge, FIVE circular basins and an
-- indefinitely extending waterfall corridor. Draw their union directly,
-- with the same map coordinates used by server-side collision checks.
local function shape(camera,w)
  local g=love.graphics
  local z=Config.secretPool
  local center=Config.mapScale/2
  local zx=camera.zoom
  local function rectWorld(x,y,ww,hh)
    local sx,sy=camera:worldToScreen(x,y)
    g.rectangle("fill",sx,sy,ww*zx,hh*zx)
  end
  local gorge=z.gorgeX0
  rectWorld(gorge,center-z.gorgeHalf,-gorge,z.gorgeHalf*2)
  for _,p in ipairs(z.pool) do
    local sx,sy=camera:worldToScreen(p[1],p[2])
    g.circle("fill",sx,sy,p[3]*zx,80)
  end
  local wf=z.waterfall
  local left=camera:screenToWorld(0,0)
  left=min(left-10,wf.x-10)
  rectWorld(left,wf.y-wf.half-60,wf.x-left,wf.half*2+120)
end
-- Call from View.ground BEFORE the grid, entities and world labels.
-- Use stencilling to prevent water pixels and coloured land from spilling
-- into the forbidden western void or the original east-side map.
function S.draw(camera,w,h,waveMult)
  local x0=camera:worldToScreen(0,0)
  if x0<=0 then return false end
  local g=love.graphics
  g.push("all")
  g.setScissor(0,0,min(w,math.ceil(x0)),h)
  local left=0
  local width=min(w,math.ceil(x0))
  -- No fake PNG artwork: only existing MooMoo terrain palette.
  g.setColor(0.20,0.26,0.19,1)
  g.rectangle("fill",left,0,width,h)
  g.stencil(function() shape(camera,w) end,"replace",1)
  g.setStencilTest("equal",1)
  g.setColor(182/255,219/255,102/255,1)
  g.rectangle("fill",left,0,width,h)
  local z=Config.secretPool
  local zoom=camera.zoom
  local wf=z.waterfall
  local start=min(camera:screenToWorld(0,0)-10,wf.x-10)
  local function rectWorld(x,y,ww,hh)
    local sx,sy=camera:worldToScreen(x,y)
    g.rectangle("fill",sx,sy,ww*zoom,hh*zoom)
  end
  -- Sandy banks of the gorge, pools and the waterfall.
  g.setColor(219/255,198/255,102/255,1)
  rectWorld(z.gorgeX0,Config.mapScale/2-z.gorgeHalf,
    -z.gorgeX0,z.gorgeHalf*2)
  for _,p in ipairs(z.pool) do
    local sx,sy=camera:worldToScreen(p[1],p[2])
    g.circle("fill",sx,sy,p[3]*zoom,80)
  end
  rectWorld(start,wf.y-wf.half-60,wf.x-start,wf.half*2+120)
  -- Water shares the ORIGINAL river colour and animated wave width.
  g.setColor(145/255,178/255,219/255,1)
  local delta=(max(1,min(1.3,waveMult or 1))-1)*250
  local riverWidth=Config.riverWidth+delta
  rectWorld(z.gorgeX0,Config.mapScale/2-riverWidth/2,
    -z.gorgeX0,riverWidth)
  for _,p in ipairs(z.pool) do
    local sx,sy=camera:worldToScreen(p[1],p[2])
    g.circle("fill",sx,sy,p[3]*0.9*zoom,80)
  end
  rectWorld(start,wf.y-wf.half,wf.x-start,wf.half*2)
  g.setStencilTest()
  g.pop()
  return true
end
-- The stock renderer darkens every pixel with world x<0. That hides the
-- secret extension. Shade ONLY forbidden west, preserving the stock
-- reference 0.09 outside-world tint but not tinting server-walkable ground.
function S.shadeOutside(camera,w,h)
  local x0=camera:worldToScreen(0,0)
  if x0<=0 then return false end
  local g=love.graphics
  g.push("all")
  g.setScissor(0,0,min(w,math.ceil(x0)),h)
  g.stencil(function() shape(camera,w) end,"replace",1)
  g.setStencilTest("equal",0)
  g.setColor(0,0,0,0.09)
  g.rectangle("fill",0,0,min(w,x0),h)
  g.setStencilTest()
  g.pop()
  return true
end
return S
