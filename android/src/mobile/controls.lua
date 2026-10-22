-- Moo-IO mobile controls: real game input, no client-side world simulation.
local Mobile={}
Mobile.__index=Mobile
local atan2=math.atan2 or function(y,x) return math.atan(y,x) end
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
local function distance(x,y,c)return math.sqrt((x-c.x)^2+(y-c.y)^2)end
local function inside(x,y,r)
  return x>=r.x and y>=r.y and x<=r.x+r.size and y<=r.y+r.size
end
function Mobile.new()
  return setmetatable({moveId=nil,moveOrigin=nil,moveX=0,moveY=0,
    aimId=nil,aimOrigin=nil,aimDir=0,fireId=nil,
    auto=false,mapOpen=false,lastPoint=nil},Mobile)
end
function Mobile:reset()
  self.moveId=nil;self.moveOrigin=nil;self.moveX=0;self.moveY=0
  self.aimId=nil;self.aimOrigin=nil;self.fireId=nil
  self.auto=false;self.mapOpen=false
end
function Mobile:layout(w,h)
  local u=clamp(math.min(w/1280,h/720),.7,2.1)
  local big=math.min(h*.76,w*.62)
  return {unit=u,move={x=135*u,y=h-125*u,r=79*u},
    fire={x=w-117*u,y=h-132*u,r=66*u},
    auto={x=w-91*u,y=h-276*u,r=45*u},
    pause={x=w-48*u,y=43*u,r=35*u},
    minimap={x=18*u,y=18*u,size=126*u},
    bigmap={x=(w-big)/2,y=(h-big)/2,size=big},
    close={x=w-77*u,y=42*u,r=40*u}}
end
function Mobile:movement()return self.moveX,self.moveY end
function Mobile:aimAngle()return self.aimDir end
function Mobile:attacking()return self.auto or self.fireId~=nil end
function Mobile:moveJoystick(x,y,layout)
  if not self.moveOrigin then return end
  local dx,dy=x-self.moveOrigin.x,y-self.moveOrigin.y
  local d=math.sqrt(dx*dx+dy*dy)
  if d<layout.move.r*.12 then self.moveX=0;self.moveY=0;return end
  self.moveX=dx/math.max(d,1)
  self.moveY=dy/math.max(d,1)
end
function Mobile:pressed(id,x,y,w,h,mapScale)
  local l=self:layout(w,h)
  if self.mapOpen then
    if distance(x,y,l.close)<=l.close.r then self.mapOpen=false;return "map_close" end
    if inside(x,y,l.bigmap) then
      local scale=mapScale or 14400
      local wx=clamp(math.floor((x-l.bigmap.x)/l.bigmap.size*scale+.5),0,scale)
      local wy=clamp(math.floor((y-l.bigmap.y)/l.bigmap.size*scale+.5),0,scale)
      self.lastPoint={x=wx,y=wy}
      self.mapOpen=false
      return "ping",{x=wx,y=wy}
    end
    self.mapOpen=false
    return "map_close"
  end
  if distance(x,y,l.pause)<=l.pause.r then return "pause" end
  if inside(x,y,l.minimap) then self.mapOpen=true;return "map_open" end
  if distance(x,y,l.auto)<=l.auto.r then
    self.auto=not self.auto
    return "attack"
  end
  if distance(x,y,l.fire)<=l.fire.r and not self.fireId then
    self.fireId=id
    return "attack"
  end
  if x<w*.48 and y>h*.25 and not self.moveId then
    self.moveId=id;self.moveOrigin={x=x,y=y}
    self:moveJoystick(x,y,l)
    return "move"
  end
  if x>=w*.48 and y>h*.18 and not self.aimId then
    self.aimId=id;self.aimOrigin={x=x,y=y}
    return "aim"
  end
  return nil
end
function Mobile:moved(id,x,y,w,h)
  local l=self:layout(w,h)
  if id==self.moveId then self:moveJoystick(x,y,l);return "move" end
  if id==self.aimId and self.aimOrigin then
    local dx,dy=x-self.aimOrigin.x,y-self.aimOrigin.y
    if dx*dx+dy*dy>(15*l.unit)^2 then
      self.aimDir=atan2(dy,dx)
      self.aimOrigin={x=x-dx*.45,y=y-dy*.45}
    end
    return "aim"
  end
  return nil
end
function Mobile:released(id)
  if id==self.moveId then
    self.moveId=nil;self.moveOrigin=nil;self.moveX=0;self.moveY=0
    return "move"
  end
  if id==self.aimId then self.aimId=nil;self.aimOrigin=nil;return "aim" end
  if id==self.fireId then self.fireId=nil;return "attack" end
  return nil
end
local function circle(g,c,r,fill,border)
  g.setColor(fill);g.circle("fill",c.x,c.y,r)
  g.setColor(border);g.setLineWidth(math.max(2,r*.055))
  g.circle("line",c.x,c.y,r)
end
local function dot(g,x,y,r,col)
  g.setColor(col);g.circle("fill",x,y,r)
end
local function drawMap(g,world,r,mapScale)
  local scale=mapScale or 14400
  g.setColor(.055,.095,.075,.94)
  g.rectangle("fill",r.x,r.y,r.size,r.size,8,8)
  g.setColor(.35,.63,.34,.9)
  g.setLineWidth(2)
  g.rectangle("line",r.x,r.y,r.size,r.size,8,8)
  local function pos(x,y)
    return r.x+clamp(x/scale,0,1)*r.size,
      r.y+clamp(y/scale,0,1)*r.size
  end
  local p=world and world:localPlayer() or nil
  if p and p.x and p.y then
    local x,y=pos(p.x,p.y);dot(g,x,y,6,{.95,1,.9,1})
  end
  local mates=world and world.minimapData or {}
  for i=1,#mates-1,2 do
    if type(mates[i])=="number" and type(mates[i+1])=="number" then
      local x,y=pos(mates[i],mates[i+1])
      dot(g,x,y,4,{.52,.83,1,1})
    end
  end
  for _,v in ipairs(world and world.mapPings or {}) do
    if type(v.x)=="number" and type(v.y)=="number" then
      local x,y=pos(v.x,v.y)
      g.setColor(1,.9,.35,1);g.setLineWidth(2)
      g.circle("line",x,y,8+(v.scale or 0)*.15)
    end
  end
  local mark=world and world.mapMarker
  if mark and mark.x and mark.y then
    local x,y=pos(mark.x,mark.y)
    g.setColor(1,.9,.4,1);g.setLineWidth(3)
    g.line(x-8,y,x+8,y);g.line(x,y-8,x,y+8)
  end
end
function Mobile:draw(world,mapScale)
  local g=love.graphics
  local w,h=g.getDimensions()
  local l=self:layout(w,h)
  local u=l.unit
  g.push("all")
  if self.mapOpen then
    g.setColor(0,0,0,.79);g.rectangle("fill",0,0,w,h)
    drawMap(g,world,l.bigmap,mapScale)
    g.setColor(1,1,1,1)
    g.printf("TOQUE NO MAPA PARA MARCAR E AVISAR O TIME",
      l.bigmap.x,l.bigmap.y-34*u,l.bigmap.size,"center")
    circle(g,l.close,l.close.r,{.3,.17,.15,.94},{1,.6,.5,1})
    g.printf("X",l.close.x-14*u,l.close.y-17*u,28*u,"center")
    g.pop();return
  end
  drawMap(g,world,l.minimap,mapScale)
  circle(g,l.pause,l.pause.r,{.1,.19,.14,.79},{.85,.98,.83,1})
  g.setColor(1,1,1,1)
  g.printf("II",l.pause.x-14*u,l.pause.y-13*u,28*u,"center")
  local m=self.moveOrigin or l.move
  circle(g,m,l.move.r,{.08,.11,.09,.33},{.88,1,.86,.38})
  dot(g,m.x+self.moveX*l.move.r*.52,
    m.y+self.moveY*l.move.r*.52,28*u,{.70,.89,.65,.82})
  local active=self:attacking()
  circle(g,l.fire,l.fire.r,
    active and {.78,.29,.22,.94} or {.28,.37,.32,.80},
    active and {1,.76,.54,1} or {.92,.96,.89,.88})
  g.setColor(1,1,1,1)
  g.printf("ATACAR",l.fire.x-63*u,l.fire.y-11*u,126*u,"center")
  circle(g,l.auto,l.auto.r,
    self.auto and {.35,.66,.20,.96} or {.19,.24,.20,.82},
    self.auto and {.85,1,.68,1} or {.87,.91,.85,.75})
  g.setColor(1,1,1,1)
  g.printf("AUTO",l.auto.x-40*u,l.auto.y-12*u,80*u,"center")
  g.pop()
end
return Mobile
