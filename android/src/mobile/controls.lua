-- Moo-IO Android: two independent FLOATING joysticks and a compact survival HUD.
-- Left touch moves; right floating control aims in the inner zone and attacks in the outer zone.
-- Buttons remain server-authoritative and never create imaginary abilities.
local Slots=require("src.mobile.slots")
local Catalog=require("src.game.catalog")
local Icons=require("src.game.reference_icons")
local M={}
M.__index=M
local sqrt=math.sqrt
local atan2=math.atan2 or function(y,x)return math.atan(y,x)end
local min,max=math.min,math.max
local function clamp(v,a,b)return max(a,min(b,v))end
local function near(x,y,p)return (x-p.x)^2+(y-p.y)^2<=p.r*p.r end
local function inside(x,y,b)return x>=b.x and y>=b.y and x<=b.x+b.w and y<=b.y+b.h end
local categories={"gold","health","food","wood","stone","kills","points"}
local names={gold="OURO",health="VIDA",food="COMIDA",wood="MADEIRA",stone="PEDRA",kills="ABATES",points="PONTOS"}
M.categories=categories
M.rankingNames=names
local font,small=nil,nil
local function fonts()
 if not font then
   font=love.graphics.newFont(17)
   small=love.graphics.newFont(12)
 end
end
function M.new()
 return setmetatable({moveId=nil,fireId=nil,moveX=0,moveY=0,
   moveOrigin=nil,fireOrigin=nil,fireActive=false,aimDir=0,
   aimLocked=false,lockedDir=nil,fireOffsetX=0,fireOffsetY=0,
   uiScale=1.20,uiOpacity=.90,moveScale=1,fireScale=1,deadzone=.15,
   auto=false,rankOpen=false,mapOpen=false,
   rankRefresh=0,rankingCategory="gold",lastPoint=nil,
   barScroll=0,barCount=0,barTouchId=nil,barTouchX=nil,
   barTouchMoved=false,barTouchIndex=nil,
   topCollapsed=false,abilityPulse=nil,abilityPulseAt=0,
   cachedW=0,cachedH=0,cachedLayout=nil},M)
end
function M:reset()
 self.moveId=nil;self.fireId=nil
 self.moveX=0;self.moveY=0;self.moveOrigin=nil;self.fireOrigin=nil
 self.fireOffsetX=0;self.fireOffsetY=0;self.fireActive=false
 self.barTouchId=nil;self.barTouchX=nil;self.barTouchIndex=nil
 self.barTouchMoved=false;self.barTouchDistance=0
 self.barScroll=0;self.barCount=0
 self.mapOpen=false;self.rankOpen=false;self.rankRefresh=0;self.auto=false
 self.aimLocked=false;self.lockedDir=nil
end
function M:stopForOverlay()
 self.moveId=nil;self.fireId=nil
 self.moveOrigin=nil;self.fireOrigin=nil;self.moveX=0;self.moveY=0
 self.fireOffsetX=0;self.fireOffsetY=0;self.fireActive=false
 self.barTouchId=nil;self.barTouchX=nil;self.barTouchIndex=nil
 self.barTouchMoved=false;self.barTouchDistance=0
end
function M:configure(size,opacity,movement,attack,deadzone)
 local nextSize=clamp(tonumber(size) or 1.20,.85,1.55)
 local nextOpacity=clamp(tonumber(opacity) or .90,.50,1)
 local nextMove=clamp(tonumber(movement) or 1,.75,1.50)
 local nextFire=clamp(tonumber(attack) or 1,.75,1.50)
 local nextDeadzone=clamp(tonumber(deadzone) or .15,.05,.30)
 if self.uiScale~=nextSize or self.moveScale~=nextMove
   or self.fireScale~=nextFire then self.cachedLayout=nil end
 self.uiScale=nextSize;self.uiOpacity=nextOpacity
 self.moveScale=nextMove;self.fireScale=nextFire;self.deadzone=nextDeadzone
end
function M:abilityFeedback(index,now)
 self.abilityPulse=index
 self.abilityPulseAt=tonumber(now) or 0
end
function M:layout(w,h)
 if self.cachedW==w and self.cachedH==h and self.cachedLayout then
   return self.cachedLayout
 end
 local u=clamp(min(w/1280,h/720)*self.uiScale,.50,2.15)
 local board=min(h*.78,w*.58)
 local panelW=min(w*.76,735*u)
 local panelH=min(h*.82,555*u)
 -- Only the weapons, constructions and consumables actually unlocked by
 -- the MooMoo.io server appear in one continuous, centered bottom row.
 -- Overflow is touch-scrollable in the SAME row, never split into pages.
 -- Touch joysticks have no static base until a finger touches the playfield.
 local barX=w*.50
 local topY=53*u
 local l={u=u,move={x=142*u,y=h-128*u,r=86*u*self.moveScale},
   fire={x=w-135*u,y=h-132*u,r=86*u*self.fireScale},
   auto={x=w-88*u,y=h*.47,r=39*u},
   lock={x=w-88*u,y=h*.47+96*u,r=35*u},
   hotbar={x=barX,y=h-76*u,r=35*u,step=73*u,
     clipX=w*.255,clipW=w*.49},
   shop={x=w-452*u,y=topY,r=35*u},
   clan={x=w-531*u,y=topY,r=35*u},
   tribe={x=w-373*u,y=topY,r=35*u},
   chat={x=w-294*u,y=topY,r=35*u},
   rank={x=w-215*u,y=topY,r=35*u},
   pause={x=w-136*u,y=topY,r=35*u},
   fold={x=w-57*u,y=topY,r=35*u},
   ping={x=235*u,y=85*u,r=37*u},
   mark={x=235*u,y=181*u,r=37*u},
   minimap={x=21*u,y=20*u,w=167*u,h=167*u},
   bigmap={x=(w-board)/2,y=(h-board)/2,w=board,h=board},
   close={x=w-52*u,y=45*u,r=30*u},
   rankPanel={x=(w-panelW)/2,y=(h-panelH)/2,w=panelW,h=panelH},
    chatPanel={x=w*.17,y=h*.17,w=w*.66,h=h*.23},
   chatSend={x=w*.70,y=h*.275,w=w*.12,h=h*.079},
   chatCancel={x=w*.77,y=h*.182,w=w*.055,h=h*.06}}
 self.cachedW=w;self.cachedH=h;self.cachedLayout=l
 return l
end
-- A single, continuous skill/quick-action row. The authoritative V packets
-- decide which weapon/build options are available. No client-side unlocks.
-- If too many exist to fit between the two thumbs, swipe the SAME row.
function M:hotbar(total,w,h)
 local l=self:layout(w,h)
 total=max(0,math.floor(tonumber(total) or 0))
 local view=l.hotbar
 -- Respect the requested HUD scale, but keep at least six buttons usable
 -- when enough screen space exists. New unlocks extend the same line.
 local rowU=min(l.u,view.clipW/(6*73))
 local step=73*rowU
 local radius=35*rowU
 -- Include outline, active pulse and shadow in the horizontal scroll extent:
 -- first/last ability circles must not be cut at the clipping boundary.
 local edge=radius+8*rowU
 local width=total>0 and ((total-1)*step+2*edge) or 0
 local overflow=max(0,width-view.clipW)
 if total~=self.barCount then
   -- When a new unlock arrives after spawn, bring it into view automatically.
   self.barScroll=total>self.barCount and self.barCount>0 and overflow or 0
   self.barCount=total
 end
 self.barScroll=clamp(self.barScroll,0,overflow)
 local left=view.clipX+max(0,(view.clipW-width)/2)+edge-self.barScroll
 local slots={}
 for i=1,total do
   slots[i]={x=left+(i-1)*step,y=view.y,r=radius,index=i}
 end
 -- The action-number badges are below the ring and its shadow. Previous
 -- vertical scissor used just 5*rowU and cut off the bottom of the circles.
 local top=view.y-radius-11*rowU
 local bottom=min(h,view.y+radius+25*rowU)
 return slots,{scroll=self.barScroll,maxScroll=overflow,
   clipX=view.clipX,clipW=view.clipW,top=top,bottom=bottom,
   rowU=rowU,edge=edge}
end

-- Geometry shared by HP/level drawing and regression checks: all numbers
-- live INSIDE the corresponding bar/capsule, not floating above the HUD.
function M:statusLayout(w,h)
 local u=self:layout(w,h).u
 local hpW=240*u
 local xpW=146*u
 local gap=12*u
 local hpX=(w-hpW-xpW-gap)/2
 local y=h-154*u
 local height=29*u
 return {life={x=hpX,y=y,w=hpW,h=height},
   level={x=hpX+hpW+gap,y=y,w=xpW,h=height}}
end
function M:movement()
 if self.moveId then return self.moveX,self.moveY end
 return 0,0
end
function M:aimAngle()
 if self.aimLocked and self.lockedDir~=nil then return self.lockedDir end
 return self.aimDir
end
-- Only call after the Node K(0) command was sent successfully.
-- Freezing the facing direction never turns AUTO or manual fire on/off.
function M:setDirectionLock(locked)
 locked=locked==true
 if locked and not self.aimLocked then self.lockedDir=self:aimAngle() end
 self.aimLocked=locked
 if not locked then self.lockedDir=nil end
 return self.aimLocked
end
-- The floating right control is always a single pointer. Aiming does not
-- imply firing: firing is enabled only after moving past the outer threshold.
function M:attacking()return self.fireId~=nil and self.fireActive end
function M:aiming()return self.fireId~=nil end
function M:attackJoystick(x,y,l)
 local origin=self.fireOrigin or l.fire
 local dx,dy=x-origin.x,y-origin.y
 local distance=sqrt(dx*dx+dy*dy)
 local dead=12*l.u
 -- Hysteresis avoids spamming F(1)/F(0) while the thumb hovers around
 -- the boundary between aiming and firing.
 if self.fireActive then
   if distance<=l.fire.r*.56 then self.fireActive=false end
 elseif distance>=l.fire.r*.72 then
   self.fireActive=true
 end
 if distance<=dead then
   self.fireOffsetX=0;self.fireOffsetY=0
   return false
 end
 local radius=l.fire.r*.75
 local factor=min(distance,radius)/distance
 self.fireOffsetX=dx*factor
 self.fireOffsetY=dy*factor
 self.aimDir=atan2(dy,dx)
 return true
end
function M:joystick(x,y,l)
 local dx,dy=x-self.moveOrigin.x,y-self.moveOrigin.y
 local magnitude=sqrt(dx*dx+dy*dy)
 if magnitude<l.move.r*self.deadzone then
   self.moveX=0;self.moveY=0
 else
   self.moveX=dx/magnitude;self.moveY=dy/magnitude
 end
end
function M:pressed(id,x,y,w,h,scale,total)
 local l=self:layout(w,h)
 if self.mapOpen then
   if near(x,y,l.close) then self.mapOpen=false;return "map_close" end
   if inside(x,y,l.bigmap) then
     scale=scale or 14400
     local mark={x=clamp(math.floor((x-l.bigmap.x)*scale/l.bigmap.w+.5),0,scale),
       y=clamp(math.floor((y-l.bigmap.y)*scale/l.bigmap.h+.5),0,scale)}
     self.lastPoint=mark
     self.mapOpen=false
     return "ping",mark
   end
   self.mapOpen=false;return "map_close"
 end
 if self.rankOpen then
   if near(x,y,l.close) then self.rankOpen=false;return "rank_close" end
   local b=l.rankPanel
   if inside(x,y,{x=b.x+10*l.u,y=b.y+57*l.u,w=b.w-20*l.u,h=45*l.u}) then
     local index=clamp(math.floor((x-b.x-10*l.u)/(b.w-20*l.u)*#categories)+1,1,#categories)
     self.rankingCategory=categories[index]
     return "rank_category",self.rankingCategory
   end
   return nil
 end
 if near(x,y,l.fold) then
   self.topCollapsed=not self.topCollapsed
   return "top_toggle",self.topCollapsed
 end
 if not self.topCollapsed then
   if near(x,y,l.pause) then return "pause" end
   if near(x,y,l.shop) then self:stopForOverlay();return "shop_open" end
   if near(x,y,l.clan) then self:stopForOverlay();return "clan_open" end
   if near(x,y,l.tribe) then self:stopForOverlay();return "tribe_open" end
   if near(x,y,l.chat) then self:stopForOverlay();return "chat_open" end
   if near(x,y,l.rank) then
     self:stopForOverlay();self.rankOpen=true
     return "rank_open",self.rankingCategory
   end
 end
 if near(x,y,l.ping) then return "ping_here" end
 if near(x,y,l.mark) or inside(x,y,l.minimap) then
   self:stopForOverlay();self.mapOpen=true
   return "map_open"
 end
 -- The bottom shortcuts form ONE persistent line, not an inventory page.
 -- Capture the pointer until release so swiping never accidentally equips.
 if near(x,y,l.auto) then self.auto=not self.auto;return "server_auto",self.auto end
 if near(x,y,l.lock) then return "lock_aim" end
 local slots,bar=self:hotbar(total,w,h)
 if self.barTouchId==nil and x>=bar.clipX and x<=bar.clipX+bar.clipW
   and y>=bar.top and y<=bar.bottom then
   self.barTouchId=id
   self.barTouchX=x
   self.barTouchMoved=false
   self.barTouchIndex=nil
   for _,p in ipairs(slots) do
     if near(x,y,p) then self.barTouchIndex=p.index;break end
   end
   return "bar_hold"
 end
 -- Floating left movement: any open place in the lower-left touch zone.
 if x<w*.35 and y>h*.38 and self.moveId==nil then
   self.moveId=id;self.moveOrigin={x=x,y=y}
   self:joystick(x,y,l)
   return "move"
 end
 -- Single floating right control: touch starts aim-only; pull outward
 -- to attack+aim. Returning inward stops only manual fire, not AUTO.
 if x>w*.68 and y>h*.38 and self.fireId==nil then
   self.fireId=id;self.fireActive=false;self.fireOrigin={x=x,y=y}
   self:attackJoystick(x,y,l)
   return "attack"
 end
 return nil
end
function M:moved(id,x,y,w,h)
 if id==self.barTouchId then
   local previous=self.barTouchX or x
   local delta=x-previous
   self.barTouchX=x
   if not self.barTouchMoved and math.abs(delta)>0 then
     self.barTouchDistance=(self.barTouchDistance or 0)+math.abs(delta)
     if self.barTouchDistance>=12*self:layout(w,h).u then
       self.barTouchMoved=true
     end
   end
   if self.barTouchMoved then
     local _,bar=self:hotbar(self.barCount,w,h)
     self.barScroll=clamp(self.barScroll-delta,0,bar.maxScroll)
   end
   return "bar_scroll"
 end
 if id==self.moveId and self.moveOrigin then
   self:joystick(x,y,self:layout(w,h))
   return "move"
 end
 if id==self.fireId then
   local previous=self.fireActive
   local aimed=self:attackJoystick(x,y,self:layout(w,h))
   -- Even when the thumb changes direction only, relay aim immediately.
   -- When crossing the boundary, the client also sends F(1) / F(0).
   return "aim",previous~=self.fireActive
 end
 return nil
end
function M:released(id)
 if id==self.barTouchId then
   local index=not self.barTouchMoved and self.barTouchIndex or nil
   self.barTouchId=nil;self.barTouchX=nil
   self.barTouchIndex=nil;self.barTouchMoved=false;self.barTouchDistance=0
   if index then return "slot",index end
   return "bar_release"
 end
 if self.moveId==id then
   self.moveId=nil;self.moveOrigin=nil;self.moveX=0;self.moveY=0;return "move"
 end
 if self.fireId==id then
   self.fireId=nil;self.fireOrigin=nil;self.fireActive=false
   self.fireOffsetX=0;self.fireOffsetY=0
   return "attack"
 end
 return nil
end
local currentHudOpacity=1
local function ring(g,p,active,accent)
 -- Small number of primitive draws; no new textures, canvases or shaders per frame.
 local r=p.r
 g.setColor(.015,.036,.037,.67*currentHudOpacity);g.circle("fill",p.x+2,p.y+3,r+4)
 g.setColor(active and .23 or .09,active and .41 or .17,active and .26 or .19,.92*currentHudOpacity)
 g.circle("fill",p.x,p.y,r)
 g.setColor(accent and .89 or .45,accent and .76 or .75,accent and .35 or .72,currentHudOpacity)
 g.setLineWidth(2.4);g.circle("line",p.x,p.y,r-1)
 g.setColor(.87,.96,.93,.22*currentHudOpacity);g.arc("line","open",p.x,p.y,r-5,math.pi*1.09,math.pi*1.86)
end
local function words(g,str,p,size)
 g.setColor(.97,.98,.94,1)
 g.setFont(size and small or font)
 g.printf(str,p.x-p.r*1.1,p.y-(size and 6 or 9),p.r*2.2,"center")
end
-- Original vector glyphs (no copyrighted MOBA UI assets). Draw once per frame,
-- with no filesystem access, shaders or new Canvas allocations.
local function glyph(g,kind,p,u,active)
 g.push()
 g.translate(p.x,p.y)
 g.scale(u,u)
 g.setLineWidth(2.8)
 if kind=="attack" then
   g.rotate(-.65)
   g.setColor(active and 1 or .93,active and .7 or .88,.67,1)
   g.polygon("fill",-5,-29,5,-29,8,13,-8,13)
   g.setColor(.21,.33,.31,1)
   g.polygon("fill",0,-23,3,5,0,15,-3,5)
   g.setColor(1,.86,.44,1)
   g.rectangle("fill",-20,10,40,6,2,2)
   g.rectangle("fill",-3,15,6,14,2,2)
 elseif kind=="shop" then
   g.setColor(.95,.83,.44,1)
   g.rectangle("line",-18,-17,36,33,3,3)
   g.line(-21,-17,-12,-26,12,-26,21,-17)
   g.line(-4,-17,-4,16);g.line(5,-17,5,16)
 elseif kind=="tribe" then
   g.setColor(.89,.81,.52,1)
   g.line(-15,23,-15,-24)
   g.polygon("fill",-12,-23,18,-16,3,-2,-12,-8)
 elseif kind=="clan" then
   g.setColor(.66,.9,.73,1)
   g.polygon("line",0,-24,20,-14,17,14,0,24,-17,14,-20,-14)
   g.line(-11,0,11,0);g.line(0,-12,0,13)
 elseif kind=="lock" then
   -- A small padlock: open when free, closed and highlighted when fixed.
   g.setColor(active and .98 or .71,active and .79 or .90,
     active and .38 or .85,1)
   g.setLineWidth(3.2)
   if active then
     g.arc("line","open",0,-7,10,math.pi,2*math.pi)
   else
     g.arc("line","open",-4,-7,10,math.pi*.85,math.pi*1.87)
   end
   g.rectangle("line",-16,-7,32,28,4,4)
   g.circle("fill",0,3,3.8)
   g.rectangle("fill",-1.5,3,3,8)
 elseif kind=="auto" then
   g.setColor(active and .91 or .67,active and .9 or .82,.48,1)
   g.arc("line","open",0,0,18,-.3,math.pi*1.37)
   g.polygon("fill",-17,-12,-20,-1,-9,-6)
   g.circle("fill",0,0,4)
 elseif kind=="chat" then
   g.setColor(.81,.96,.87,1)
   g.rectangle("line",-21,-17,42,29,8,8)
   g.polygon("fill",-12,10,-12,22,-1,11)
   g.circle("fill",-10,-3,2.5);g.circle("fill",0,-3,2.5)
   g.circle("fill",10,-3,2.5)
 elseif kind=="ping" then
   g.setColor(1,.83,.39,1)
   g.polygon("line",0,-23,21,0,0,23,-21,0)
   g.rectangle("fill",-2.4,-12,4.8,16,2,2)
   g.circle("fill",0,11,3)
 elseif kind=="map" then
   g.setColor(.71,.9,.78,1)
   g.polygon("line",-21,-15,-8,-20,7,-13,21,-19,21,17,7,21,-8,15,-21,19)
   g.line(-8,-20,-8,15);g.line(7,-13,7,21)
 elseif kind=="ranking" then
   g.setColor(1,.87,.42,1)
   g.arc("line","open",0,-10,14,0,math.pi)
   g.line(-14,-10,-10,2,-4,7,4,7,10,2,14,-10)
   g.line(-3,8,-3,18);g.line(3,8,3,18)
   g.line(-13,18,13,18)
 elseif kind=="pause" then
   g.setColor(.87,.96,.9,1)
   g.rectangle("fill",-11,-15,8,30,2,2)
   g.rectangle("fill",3,-15,8,30,2,2)
 end
 g.pop()
end
local function map(g,world,b,scale)
 scale=scale or 14400
 g.setColor(.045,.13,.09,.90);g.rectangle("fill",b.x,b.y,b.w,b.h,7,7)
 g.setColor(.20,.36,.27,.8)
 for i=1,5 do
   local k=i/6
   g.line(b.x+b.w*k,b.y,b.x+b.w*k,b.y+b.h)
   g.line(b.x,b.y+b.h*k,b.x+b.w,b.y+b.h*k)
 end
 g.setColor(.59,.79,.49,.93);g.rectangle("line",b.x,b.y,b.w,b.h,7,7)
 local function dot(x,y,r,red,green,blue)
   if type(x)~="number" or type(y)~="number" then return end
   g.setColor(red,green,blue,1)
   g.circle("fill",b.x+clamp(x/scale,0,1)*b.w,b.y+clamp(y/scale,0,1)*b.h,r)
 end
 local player=world and world:localPlayer()
 if player then dot(player.x,player.y,5,1,1,.81) end
 local mates=world and world.minimapData or {}
 for i=1,#mates-1,2 do dot(mates[i],mates[i+1],3,.30,.82,1) end
 for _,p in ipairs(world and world.mapPings or {}) do dot(p.x,p.y,5,1,.81,.24) end
 local marker=world and world.mapMarker
 if marker then dot(marker.x,marker.y,6,1,.94,.38) end
end
function M:drawChat(draft)
 local g=love.graphics
 local w,h=g.getDimensions()
 local l=self:layout(w,h)
 fonts()
 local b=l.chatPanel
 g.push("all")
 g.setColor(.015,.035,.035,.80)
 g.rectangle("fill",0,0,w,h)
 g.setColor(.055,.15,.13,.97)
 g.rectangle("fill",b.x,b.y,b.w,b.h,12,12)
 g.setColor(.48,.74,.55,1)
 g.setLineWidth(2)
 g.rectangle("line",b.x,b.y,b.w,b.h,12,12)
 g.setFont(font)
 g.setColor(.94,.97,.88,1)
 g.print("CHAT DA PARTIDA",b.x+22*l.u,b.y+13*l.u)
 g.setColor(.11,.24,.22,.98)
 g.rectangle("fill",w*.20,h*.275,w*.48,h*.079,8,8)
 g.setColor(.60,.78,.72,1)
 g.rectangle("line",w*.20,h*.275,w*.48,h*.079,8,8)
 g.setFont(font)
 local text=tostring(draft or "")
 if #text>75 then text=text:sub(-75) end
 g.setColor(.96,.98,.96,1)
 g.print((#text>0 and text or "Digite sua mensagem...")..
   (#text>0 and "|" or ""),w*.21,h*.293)
 local send=l.chatSend
 g.setColor(.29,.58,.37,1)
 g.rectangle("fill",send.x,send.y,send.w,send.h,8,8)
 g.setColor(1,1,1,1)
 g.printf("ENVIAR",send.x,send.y+send.h*.30,send.w,"center")
 local exit=l.chatCancel
 g.setColor(.35,.27,.23,1)
 g.rectangle("fill",exit.x,exit.y,exit.w,exit.h,6,6)
 g.setColor(.98,.96,.94,1)
 g.printf("X",exit.x,exit.y+exit.h*.25,exit.w,"center")
 g.setFont(small)
 g.setColor(.77,.87,.80,1)
 g.print("Ate 30 caracteres. ENTER tambem envia.",b.x+22*l.u,b.y+b.h-27*l.u)
 g.pop()
end
function M:draw(world,scale)
 local g=love.graphics
 local w,h=g.getDimensions()
 local l=self:layout(w,h)
 local u=l.u
 currentHudOpacity=self.uiOpacity
 fonts()
 g.push("all")
 if self.mapOpen or self.rankOpen then
   g.setColor(0,.012,.012,.83);g.rectangle("fill",0,0,w,h)
   if self.mapOpen then
     map(g,world,l.bigmap,scale)
     g.setFont(font);g.setColor(.94,.97,.86,1)
     g.printf("TOQUE NO MAPA PARA MARCAR",l.bigmap.x,l.bigmap.y-29*u,l.bigmap.w,"center")
   else
     local b=l.rankPanel
     g.setColor(.055,.12,.11,.97);g.rectangle("fill",b.x,b.y,b.w,b.h,11,11)
     g.setColor(.5,.73,.56,1);g.rectangle("line",b.x,b.y,b.w,b.h,11,11)
     g.setFont(font)
     g.setColor(.96,.98,.94,1)
     g.printf("TOP 10  /  "..names[self.rankingCategory],b.x,b.y+15*u,b.w,"center")
     local cell=(b.w-20*u)/#categories
     for i,category in ipairs(categories) do
       local bx=b.x+10*u+(i-1)*cell
       g.setColor(category==self.rankingCategory and .28 or .12,
         category==self.rankingCategory and .47 or .23,.24,.95)
       g.rectangle("fill",bx,b.y+58*u,cell-3*u,36*u,4,4)
       g.setColor(1,1,1,1);g.setFont(small)
       g.printf(names[category],bx,b.y+70*u,cell-3*u,"center")
     end
     g.setFont(font)
     local data=world and world.categoryRankings and world.categoryRankings[self.rankingCategory] or {}
     for i=1,min(10,#data) do
       local item=data[i];local y=b.y+108*u+(i-1)*36*u
       if i%2==0 then
         g.setColor(.18,.27,.24,.8)
         g.rectangle("fill",b.x+10*u,y-3*u,b.w-20*u,32*u,3,3)
       end
       g.setColor(.95,.85,.49,1);g.print(i..".",b.x+25*u,y)
       g.setColor(.96,.97,.94,1);g.print(tostring(item.name or "?"):sub(1,23),b.x+72*u,y)
       g.printf(tostring(math.floor(item.score or 0)),b.x+b.w-157*u,y,130*u,"right")
     end
     if #data==0 then
       g.setColor(.85,.87,.85,1)
       g.printf("AGUARDANDO DADOS DO SERVIDOR",b.x,b.y+148*u,b.w,"center")
     end
   end
   ring(g,l.close,false,true);words(g,"X",l.close)
   g.pop()
   return
 end
 map(g,world,l.minimap,scale)
 ring(g,l.ping,false,true);glyph(g,"ping",l.ping,u)
 ring(g,l.mark,false,false);glyph(g,"map",l.mark,u)
 -- Keep the actual map and ping actions visible next to the minimap.
 g.setFont(small);g.setColor(.97,.97,.94,self.uiOpacity)
 g.printf("PING",l.ping.x-31*u,l.ping.y+29*u,62*u,"center")
 g.printf("MAPA",l.mark.x-31*u,l.mark.y+29*u,62*u,"center")
 -- Collapse the busy top-right navigation to one small touch control.
 -- This does not hide ping/map, auto attack, joystick or the skill line.
 if not self.topCollapsed then
   ring(g,l.shop,false,true);glyph(g,"shop",l.shop,u)
   ring(g,l.clan,false,false);glyph(g,"clan",l.clan,u)
   ring(g,l.tribe,false,false);glyph(g,"tribe",l.tribe,u)
   ring(g,l.chat,false,false);glyph(g,"chat",l.chat,u)
   ring(g,l.rank,false,false);glyph(g,"ranking",l.rank,u)
   ring(g,l.pause,false,false);glyph(g,"pause",l.pause,u)
   g.setFont(small);g.setColor(1,1,1,self.uiOpacity)
   g.printf("LOJA",l.shop.x-35*u,l.shop.y+25*u,70*u,"center")
   g.printf("CLA",l.clan.x-35*u,l.clan.y+25*u,70*u,"center")
   g.printf("TRIBO",l.tribe.x-35*u,l.tribe.y+25*u,70*u,"center")
   g.printf("CHAT",l.chat.x-35*u,l.chat.y+25*u,70*u,"center")
   g.printf("TOP",l.rank.x-35*u,l.rank.y+25*u,70*u,"center")
   g.printf("MENU",l.pause.x-35*u,l.pause.y+25*u,70*u,"center")
 end
 ring(g,l.fold,false,true)
 g.setColor(.88,.94,.82,self.uiOpacity);g.setLineWidth(3*u)
 local x,y=l.fold.x,l.fold.y
 if self.topCollapsed then
   g.line(x-12*u,y-7*u,x+12*u,y-7*u)
   g.line(x-12*u,y,x+12*u,y)
   g.line(x-12*u,y+7*u,x+12*u,y+7*u)
 else
   g.line(x-10*u,y-7*u,x+10*u,y-7*u)
   g.line(x-10*u,y+7*u,x+10*u,y+7*u)
 end
 g.setFont(small);g.setColor(1,1,1,self.uiOpacity)
 g.printf(self.topCollapsed and "ABRIR" or "OCULTAR",
   l.fold.x-39*u,l.fold.y+25*u,78*u,"center")
 -- No anchored joystick circles: bases are created at the finger-down points.
 if self.moveOrigin then
   local base={x=self.moveOrigin.x,y=self.moveOrigin.y,r=l.move.r}
   ring(g,base,true,false)
   local x=base.x+self.moveX*l.move.r*.48
   local y=base.y+self.moveY*l.move.r*.48
   g.setColor(.67,.94,.79,self.uiOpacity)
   g.circle("fill",x,y,27*u*self.moveScale)
   g.setColor(.12,.31,.23,1);g.circle("line",x,y,26*u*self.moveScale)
 end
 if self.fireOrigin then
   local base={x=self.fireOrigin.x,y=self.fireOrigin.y,r=l.fire.r}
   -- Inner cyan radius = precision aim only. Outer gold threshold =
   -- aim+manual fire. No second combat button is introduced.
   ring(g,base,self.fireActive,self.fireActive)
   g.setLineWidth(2*u)
   g.setColor(.28,.88,.93,.80*self.uiOpacity)
   g.circle("line",base.x,base.y,base.r*.56)
   g.setColor(.96,.75,.29,.92*self.uiOpacity)
   g.circle("line",base.x,base.y,base.r*.72)
   local px=base.x+self.fireOffsetX
   local py=base.y+self.fireOffsetY
   if self.fireOffsetX~=0 or self.fireOffsetY~=0 then
     g.setColor(self.fireActive and .99 or .34,
       self.fireActive and .67 or .82,
       self.fireActive and .23 or .93,.77*self.uiOpacity)
     g.setLineWidth(3*u);g.line(base.x,base.y,px,py)
   end
   g.setColor(self.fireActive and .96 or .38,
     self.fireActive and .70 or .86,
     self.fireActive and .31 or .93,self.uiOpacity)
   g.circle("fill",px,py,23*u*self.fireScale)
   g.setColor(.12,.27,.25,1);g.setLineWidth(2*u)
   g.circle("line",px,py,23*u*self.fireScale)
   glyph(g,"attack",{x=px,y=py},u*.66,self.fireActive)
   g.setFont(small);g.setColor(1,1,1,self.uiOpacity)
   g.printf(self.fireActive and "MIRA + ATAQUE" or "SOMENTE MIRA",
     base.x-75*u,base.y+base.r+8*u,150*u,"center")
 end
 ring(g,l.auto,self.auto,true);glyph(g,"auto",l.auto,u,self.auto)
 g.setColor(.97,.97,.94,1);g.setFont(small)
 g.printf(self.auto and "AUTO ON" or "AUTO",l.auto.x-41*u,l.auto.y+43*u,82*u,"center")
 -- Fixed-direction action is independent from AUTO and both joysticks.
 ring(g,l.lock,self.aimLocked,self.aimLocked)
 glyph(g,"lock",l.lock,u*.80,self.aimLocked)
 g.setFont(small);g.setColor(.97,.97,.94,1)
 g.printf(self.aimLocked and "MIRA FIXA" or "TRAVAR",
   l.lock.x-46*u,l.lock.y+39*u,92*u,"center")
 -- Compact, lined-up HP and level capsules directly over the skill row.
 -- Health numbers are centered *inside* the health bar. No heart icon.
 local player=world and world.localPlayer and world:localPlayer()
 local life=max(0,tonumber(player and player.health) or 0)
 local maxLife=max(1,tonumber(player and player.maxHealth) or 100)
 local xp=max(0,tonumber(world and world.xp) or 0)
 local maxXP=max(1,tonumber(world and world.maxXP) or 300)
 local level=max(1,math.floor(tonumber(world and world.age) or 1))
 local status=self:statusLayout(w,h)
 local hp=status.life
 g.setColor(.025,.075,.075,.92*self.uiOpacity)
 g.rectangle("fill",hp.x,hp.y,hp.w,hp.h,hp.h*.45,hp.h*.45)
 g.setColor(.89,.20,.26,self.uiOpacity)
 g.rectangle("fill",hp.x+3*u,hp.y+3*u,
   (hp.w-6*u)*clamp(life/maxLife,0,1),hp.h-6*u,
   hp.h*.38,hp.h*.38)
 g.setColor(.75,.92,.86,.92*self.uiOpacity)
 g.setLineWidth(2*u)
 g.rectangle("line",hp.x,hp.y,hp.w,hp.h,hp.h*.45,hp.h*.45)
 -- Keep the text INSIDE the bar even at smaller mobile resolutions.
 local statusFont=hp.h>=font:getHeight()+4*u and font or small
 g.setFont(statusFont)
 local hpText=math.floor(life).."/"..math.floor(maxLife)
 local hpTextY=hp.y+(hp.h-statusFont:getHeight())*.5
 g.setColor(0,0,0,.72*self.uiOpacity)
 g.printf(hpText,hp.x+1*u,hpTextY+1*u,hp.w,"center")
 g.setColor(1,1,1,1)
 g.printf(hpText,hp.x,hpTextY,hp.w,"center")
 -- The "Nv" label belongs inside the rounded level capsule; experience
 -- progress has its own quiet track on the right, all within this capsule.
 local xpBox=status.level
 g.setColor(.025,.075,.075,.94*self.uiOpacity)
 g.rectangle("fill",xpBox.x,xpBox.y,xpBox.w,xpBox.h,
   xpBox.h*.48,xpBox.h*.48)
 g.setColor(.70,.85,.71,.92*self.uiOpacity)
 g.setLineWidth(2*u)
 g.rectangle("line",xpBox.x,xpBox.y,xpBox.w,xpBox.h,
   xpBox.h*.48,xpBox.h*.48)
 local levelW=68*u
 g.setColor(.20,.31,.24,.95*self.uiOpacity)
 g.rectangle("fill",xpBox.x+2*u,xpBox.y+2*u,levelW,xpBox.h-4*u,
   (xpBox.h-4*u)*.45,(xpBox.h-4*u)*.45)
 g.setFont(statusFont)
 g.setColor(.98,.87,.47,1)
 g.printf("Nv "..level,xpBox.x+2*u,
   xpBox.y+(xpBox.h-statusFont:getHeight())*.5,levelW,"center")
 local trackX=xpBox.x+76*u
 local trackY=xpBox.y+xpBox.h*.37
 local trackW=xpBox.w-85*u
 local trackH=xpBox.h*.26
 g.setColor(.10,.19,.18,.9*self.uiOpacity)
 g.rectangle("fill",trackX,trackY,trackW,trackH,trackH*.5,trackH*.5)
 g.setColor(.98,.80,.34,self.uiOpacity)
 g.rectangle("fill",trackX,trackY,trackW*clamp(xp/maxXP,0,1),
   trackH,trackH*.5,trackH*.5)
 -- The auto-gather/attack mode is an independent toggle: a held manual
 -- attack and opening an overlay never change the active auto state.
 local slots,bar=self:hotbar(Slots.total(world),w,h)
 -- Clip only the bottom row. More unlocked options extend horizontally,
 -- and the same row can be swiped. No arrows, pages or invented skills.
 g.setScissor(bar.clipX,bar.top,bar.clipW,bar.bottom-bar.top)
 for _,p in ipairs(slots) do
   if p.x+p.r>=bar.clipX and p.x-p.r<=bar.clipX+bar.clipW then
     local id,weapon=Slots.at(world,p.index)
     local selected=false
     if player and type(player.buildIndex)=="number" then
       if player.buildIndex>=0 then
         selected=not weapon and id==player.buildIndex
       else
         selected=weapon and id==player.weaponIndex
       end
     end
     local pulse=0
     if self.abilityPulse==p.index and love.timer and love.timer.getTime then
       pulse=clamp(1-(love.timer.getTime()-self.abilityPulseAt)/.27,0,1)
     end
     ring(g,p,selected or pulse>0,selected or pulse>0)
     if pulse>0 then
       g.setLineWidth((1+3*pulse)*bar.rowU)
       g.setColor(.98,.86,.42,.8*pulse)
       g.circle("line",p.x,p.y,p.r+4*bar.rowU)
     end
     local item=id and (weapon and Catalog.weaponById(id) or Catalog.itemById(id))
     if item then Icons.draw(weapon and "weapon" or "item",item,p.x,p.y,p.r*1.3) end
     -- Draw a proper circular keycap as part of the ability wheel, rather
     -- than placing a number on top of the bottom ring where it gets cut.
     local badgeR=p.r*.31
     local badgeY=p.y+p.r*.80
     g.setColor(.018,.045,.056,.97*self.uiOpacity)
     g.circle("fill",p.x,badgeY,badgeR)
     g.setColor(selected and .99 or .34,selected and .77 or .86,
       selected and .35 or .86,self.uiOpacity)
     g.setLineWidth(2*bar.rowU)
     g.circle("line",p.x,badgeY,badgeR-1*bar.rowU)
     g.setColor(1,1,1,1);g.setFont(small)
     g.printf(tostring(p.index),p.x-badgeR,
       badgeY-small:getHeight()*.5,2*badgeR,"center")
   end
 end
 g.setScissor()
 -- Subtle edge marks indicate more unlocked actions off-screen.
 if bar.maxScroll>0 then
   g.setFont(font);g.setColor(.74,.97,.86,.88*self.uiOpacity)
   if bar.scroll>0 then g.print("<",bar.clipX-13*l.u,l.hotbar.y-13*l.u) end
   if bar.scroll<bar.maxScroll then
     g.print(">",bar.clipX+bar.clipW+2*l.u,l.hotbar.y-13*l.u)
   end
 end
 g.pop()
end
return M
