-- In-game profile/stats modal driven by the ORIGINAL Node V -> p/F protocol.
-- Read-only presentation. No client-calculated kills or fabricated account data.
local P={}
P.__index=P
local fonts={}
local function font(size)
  if not fonts[size] then fonts[size]=love.graphics.newFont(size) end
  love.graphics.setFont(fonts[size])
end
local function label(s,x,y,sz,color)
  font(sz)
  love.graphics.setColor(unpack(color or {1,1,1}))
  love.graphics.print(tostring(s),x,y)
end
local function number(n)
  if type(n)~="number" then return "-" end
  if n==math.floor(n) then return string.format("%.0f",n) end
  return string.format("%.1f",n)
end
local function stat(row,name,value,x,y)
  font(13)
  love.graphics.setColor(0.68,0.76,0.77)
  love.graphics.print(name,x,y)
  love.graphics.setColor(1,1,1)
  love.graphics.print(number(value),x+104,y)
end
function P.new()
  return setmetatable({sid=nil},P)
end
function P:open(sid)
  if type(sid)~="number" or sid%1~=0 or sid<0 then return false end
  self.sid=sid
  return true
end
function P:close()
  self.sid=nil
end
function P:isOpen()
  return self.sid~=nil
end
function P:geometry(w,h)
  local width=math.min(498,math.max(220,w-24))
  local height=math.min(478,math.max(260,h-24))
  return math.floor((w-width)/2),math.floor((h-height)/2),width,height
end
-- Return (consumed,closed). The caller must send Node V(-1) on close,
-- not just hide the local view while the server continues watching stats.
function P:click(x,y,w,h)
  if not self:isOpen() then return false,false end
  if type(x)~="number" or type(y)~="number" then return true,false end
  local bx,by,bw,bh=self:geometry(w,h)
  local outside=x<bx or x>=bx+bw or y<by or y>=by+bh
  local exit=x>=bx+bw-39 and x<bx+bw-7 and
    y>=by+11 and y<by+44
  if outside or exit then
    self:close()
    return true,true
  end
  return true,false
end
function P:draw(world)
  if not self:isOpen() then return false end
  local g=love.graphics
  local w,h=g.getDimensions()
  local bx,by,bw,bh=self:geometry(w,h)
  local info=type(world.profiles)=="table" and world.profiles[self.sid]
  local stats=type(world.lifeStats)=="table" and world.lifeStats[self.sid]
  g.push("all")
  g.setColor(0,0,0,0.45)
  g.rectangle("fill",0,0,w,h)
  g.setColor(0.11,0.15,0.16,0.97)
  g.rectangle("fill",bx,by,bw,bh,10,10)
  g.setColor(0.32,0.45,0.44)
  g.setLineWidth(2)
  g.rectangle("line",bx+1,by+1,bw-2,bh-2,10,10)
  label("PLAYER PROFILE",bx+20,by+17,21)
  g.setColor(0.30,0.33,0.34)
  g.rectangle("fill",bx+bw-40,by+11,32,33,5,5)
  label("X",bx+bw-30,by+17,18)
  local name=info and info.name
  if not name then
    local player=world.players and world.players[self.sid]
    name=player and player.name or "SID "..self.sid
  end
  font(21)
  g.setColor(1,1,1)
  g.printf(tostring(name),bx+20,by+60,bw-40,"left")
  local caption=info and (info.anon and "Anonymous" or
    info.guest and "Guest" or "Account") or "Waiting for Node profile..."
  if info and info.clan then caption=caption.."  |  "..info.clan end
  if info and info.role and info.role~="user" then
    caption=caption.."  |  "..info.role
  end
  font(12)
  g.setColor(0.68,0.80,0.72)
  g.printf(caption,bx+20,by+93,bw-40)
  g.setColor(0.33,0.42,0.41)
  g.rectangle("fill",bx+18,by+126,bw-36,1)
  label("ACCOUNT TOTALS",bx+20,by+139,15,{0.88,0.93,0.91})
  if info and not info.guest then
    stat(1,"Kills",info.kills,bx+22,by+174)
    stat(2,"Deaths",info.deaths,bx+bw/2,by+174)
    stat(3,"Best score",info.bestScore,bx+22,by+200)
    stat(4,"Lives",info.lives,bx+bw/2,by+200)
    stat(5,"Playtime (s)",info.playtime,bx+22,by+226)
  else
    label(info and "No permanent account totals" or
      "Waiting for Node profile...",bx+22,by+178,13,
      {0.70,0.75,0.74})
  end
  g.setColor(0.33,0.42,0.41)
  g.rectangle("fill",bx+18,by+262,bw-36,1)
  label("THIS LIFE - SERVER STATS",bx+20,by+274,15,{0.88,0.93,0.91})
  local data={
    {"Kills",stats and stats.kills},{"Score",stats and stats.score},
    {"Wood",stats and stats.wood},{"Food",stats and stats.food},
    {"Stone",stats and stats.stone},{"Gold",stats and stats.gold},
    {"Damage",stats and stats.damage},{"Animal dmg",stats and stats.animalDamage},
    {"Healing",stats and stats.healing},{"Animals",stats and stats.animals},
    {"Bosses",stats and stats.bosses}
  }
  if not stats then
    label("Waiting for Node stats...",bx+22,by+310,13,
      {0.70,0.75,0.74})
  else
    for i,item in ipairs(data) do
      local column=(i-1)%2
      local row=math.floor((i-1)/2)
      stat(row,item[1],item[2],
        bx+22+column*(bw/2-1),by+309+row*24)
    end
  end
  g.pop()
  return true
end
return P
