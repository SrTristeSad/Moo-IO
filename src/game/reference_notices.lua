-- Presentation of two server-authored status messages:
-- r = game update countdown (0 means after this life),
-- Z = graceful restart countdown (-1 cancels).
-- This module does not restart servers, synthesize packets, or force disconnects.
local N={}
local fontCache={}
local function finite(n)
  return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge
end
local function readable(seconds)
  local n=math.max(0,math.ceil(seconds))
  local m=math.floor(n/60)
  return string.format("%d:%02d",m,n%60)
end
function N.status(world)
  if type(world)~="table" then return nil end
  if world.restartSeconds~=nil then
    return "Servidor reiniciando em "..readable(world.restartSeconds)
  end
  if world.updateSeconds~=nil then
    if world.updateSeconds==0 then
      return "Atualizacao do jogo apos esta vida"
    end
    return "Atualizacao do jogo em "..readable(world.updateSeconds)
  end
  return nil
end
function N.draw(world,width,height)
  local notice=N.status(world)
  if not notice or not love or not love.graphics then return false end
  local g=love.graphics
  local font=fontCache[18]
  if not font then
    font=love.graphics.newFont(18)
    fontCache[18]=font
  end
  local bw=math.min(width-16,math.max(280,font:getWidth(notice)+38))
  if bw<=0 then return false end
  local bx=(width-bw)/2
  local by=math.min(height-62,97)
  if by<0 then by=0 end
  g.push("all")
  g.setColor(0.09,0.12,0.13,0.91)
  g.rectangle("fill",bx,by,bw,40,7,7)
  g.setColor(1,0.73,0.35,1)
  g.rectangle("fill",bx,by,5,40,2,2)
  g.setColor(1,1,1,1)
  g.setFont(font)
  g.printf(notice,bx+7,by+9,bw-14,"center")
  g.pop()
  return true
end
return N
