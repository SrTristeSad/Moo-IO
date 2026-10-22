-- Exact original MooMoo.io death transition:
-- client/src/index.js killPlayer() -> #diedText, grow at 0.1 px per ms
-- (up to 120px), then show the familiar opening menu after 3000ms.
-- client/public/css/main.css: background rgba(0,0,0,0.25),
-- centered vertically and horizontally, with white "YOU DIED".
-- NOT a new menu or an invented respawn timer/mechanic.
local Config=require("src.game.config")
local Death={}
Death.__index=Death
Death.DURATION=(Config.deathFadeout or 3000)/1000
function Death.new()
  return setmetatable({elapsed=0,active=false},Death)
end
function Death:start()
  self.elapsed=0
  self.active=true
end
function Death:reset()
  self.elapsed=0
  self.active=false
end
function Death:fontSize()
  -- The reference updateGame adds 0.1 * deltaMillis until 120px,
  -- then rounds to whole pixels (0 is invisible at packet P).
  return math.min(120,math.floor(self.elapsed*100+0.5))
end
function Death:update(dt)
  if not self.active then return false end
  if type(dt)~="number" or dt<=0 then return false end
  self.elapsed=math.min(Death.DURATION,self.elapsed+dt)
  return self.elapsed>=Death.DURATION
end
local fonts={}
function Death:draw(width,height)
  if not self.active then return end
  local gfx=love.graphics
  width=width or gfx.getWidth()
  height=height or gfx.getHeight()
  gfx.push("all")
  gfx.setColor(0,0,0,0.25)
  gfx.rectangle("fill",0,0,width,height)
  local size=self:fontSize()
  if size>0 then
    local font=fonts[size]
    if not font then
      font=gfx.newFont(size)
      fonts[size]=font
    end
    gfx.setFont(font)
    gfx.setColor(1,1,1,1)
    gfx.printf("YOU DIED",0,math.floor((height-font:getHeight())/2),
      width,"center")
  end
  gfx.pop()
end
return Death
