local Camera={}
Camera.__index=Camera
-- JS resize(): scaleFillNative = max(screenWidth/1920,screenHeight/1080).
-- The LÖVE gameplay canvas must use the same virtual 1920x1080 world view;
-- the HTML-style HUD remains in physical window coordinates.
local REFERENCE_WIDTH=1920
local REFERENCE_HEIGHT=1080
local function fillScale(w,h)
  return math.max(w/REFERENCE_WIDTH,h/REFERENCE_HEIGHT)
end
function Camera.new()
  local w,h=love.graphics.getDimensions()
  return setmetatable({
    x=0,y=0,width=w,height=h,zoom=fillScale(w,h),hasTarget=false
  },Camera)
end
function Camera:resize(w,h)
  self.width,self.height=w,h
  self.zoom=fillScale(w,h)
end
function Camera:worldToScreen(x,y)
  return (x-self.x)*self.zoom+self.width/2,(y-self.y)*self.zoom+self.height/2
end
function Camera:screenToWorld(x,y)
  return (x-self.width/2)/self.zoom+self.x,(y-self.height/2)/self.zoom+self.y
end
function Camera:follow(x,y) self.x=x self.y=y self.hasTarget=true end
-- Client reference updateGame(): camSpd = min(dist * 0.01 * deltaMs, dist).
function Camera:followReference(x,y,dt)
  if not self.hasTarget then
    self:follow(x,y)
    return
  end
  local dx,dy=x-self.x,y-self.y
  local distance=math.sqrt(dx*dx+dy*dy)
  if distance<=0.05 then
    self.x=x;self.y=y
    return
  end
  local speed=math.min(distance*0.01*math.max(0,dt or 0)*1000,distance)
  self.x=self.x+dx*(speed/distance)
  self.y=self.y+dy*(speed/distance)
end
return Camera
