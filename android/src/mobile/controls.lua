-- Moo-IO touchscreen HUD: fixed regions, pointer ownership and original game icons.
-- Left joystick moves; ATACAR is the second joystick for aiming.
-- Hold ATACAR to hit, drag that SAME finger to choose attack direction.
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
   moveOrigin=nil,aimDir=0,fireOffsetX=0,fireOffsetY=0,
   auto=false,rankOpen=false,mapOpen=false,
   rankRefresh=0,rankingCategory="gold",page=1,lastPoint=nil,
   cachedW=0,cachedH=0,cachedLayout=nil},M)
end
function M:reset()
 self.moveId=nil;self.fireId=nil
 self.moveX=0;self.moveY=0;self.moveOrigin=nil
 self.fireOffsetX=0;self.fireOffsetY=0
 self.mapOpen=false;self.rankOpen=false;self.rankRefresh=0;self.auto=false
end
function M:stopForOverlay()
 self.moveId=nil;self.fireId=nil
 self.moveOrigin=nil;self.moveX=0;self.moveY=0
 self.fireOffsetX=0;self.fireOffsetY=0
end
function M:layout(w,h)
 if self.cachedW==w and self.cachedH==h and self.cachedLayout then
   return self.cachedLayout
 end
 local u=clamp(min(w/1280,h/720),.52,1.8)
 local board=min(h*.78,w*.58)
 local panelW=min(w*.76,735*u)
 local panelH=min(h*.82,555*u)
 -- Left thumb moves. The ATACAR circle controls both direction and hits.
 -- The strip for slots 5+ sits BETWEEN the two thumb joysticks.
 local stripX=w*.50
 -- Larger real hit regions, laid out with gap between neighbouring controls.
 -- All radii are also the on-screen visual radii, so touch and artwork agree.
 local skills={
   {x=w-279*u,y=h-104*u,r=44*u},
   {x=w-342*u,y=h-191*u,r=44*u},
   {x=w-261*u,y=h-276*u,r=44*u},
   {x=w-143*u,y=h-315*u,r=44*u}
 }
 local l={u=u,move={x=142*u,y=h-132*u,r=96*u},
   fire={x=w-99*u,y=h-119*u,r=78*u},
   auto={x=w-163*u,y=h-225*u,r=40*u},
   skills=skills,chat={x=w-276*u,y=49*u,r=44*u},
   rank={x=w-155*u,y=49*u,r=42*u},
   pause={x=w-48*u,y=49*u,r=35*u},
   ping={x=230*u,y=77*u,r=36*u},
   mark={x=230*u,y=158*u,r=36*u},
   minimap={x=21*u,y=20*u,w=167*u,h=167*u},
   bigmap={x=(w-board)/2,y=(h-board)/2,w=board,h=board},
   close={x=w-52*u,y=45*u,r=35*u},
   rankPanel={x=(w-panelW)/2,y=(h-panelH)/2,w=panelW,h=panelH},
   strip={x=stripX,y=h-48*u,r=34*u,step=72*u},
   stripPrev={x=stripX-214*u,y=h-48*u,r=27*u},
   stripNext={x=stripX+214*u,y=h-48*u,r=27*u},
   chatPanel={x=w*.17,y=h*.17,w=w*.66,h=h*.23},
   chatSend={x=w*.70,y=h*.275,w=w*.12,h=h*.079},
   chatCancel={x=w*.77,y=h*.182,w=w*.055,h=h*.06}}
 self.cachedW=w;self.cachedH=h;self.cachedLayout=l
 return l
end
function M:movement()
 if self.moveId then return self.moveX,self.moveY end
 return 0,0
end
function M:aimAngle()return self.aimDir end
function M:attacking()return self.fireId~=nil end
-- Use the same captured attack pointer for targeting. It keeps control even
-- after the finger leaves the button's visual boundary.
function M:attackJoystick(x,y,l)
 local dx,dy=x-l.fire.x,y-l.fire.y
 local distance=sqrt(dx*dx+dy*dy)
 if distance<=12*l.u then
   self.fireOffsetX=0;self.fireOffsetY=0
   return false
 end
 local radius=l.fire.r*.62
 local factor=min(distance,radius)/distance
 self.fireOffsetX=dx*factor
 self.fireOffsetY=dy*factor
 self.aimDir=atan2(dy,dx)
 return true
end
function M:joystick(x,y,l)
 local dx,dy=x-self.moveOrigin.x,y-self.moveOrigin.y
 local magnitude=sqrt(dx*dx+dy*dy)
 if magnitude<l.move.r*.15 then
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
 if near(x,y,l.pause) then return "pause" end
 if near(x,y,l.chat) then self:stopForOverlay();return "chat_open" end
 if near(x,y,l.rank) then
   self:stopForOverlay();self.rankOpen=true
   return "rank_open",self.rankingCategory
 end
 if near(x,y,l.ping) then return "ping_here" end
 if near(x,y,l.mark) or inside(x,y,l.minimap) then
   self:stopForOverlay();self.mapOpen=true
   return "map_open"
 end
 -- Centre strip receives touches BEFORE the generic movement/aim zones.
 total=total or 0
 if total>4 then
   local pages=max(1,math.ceil((total-4)/5))
   self.page=clamp(self.page,1,pages)
   if pages>1 and near(x,y,l.stripPrev) then
     self.page=max(1,self.page-1);return "page",self.page
   end
   if pages>1 and near(x,y,l.stripNext) then
     self.page=min(pages,self.page+1);return "page",self.page
   end
   local first=5+(self.page-1)*5
   local count=min(5,total-first+1)
   for i=1,count do
     local slot={x=l.strip.x+(i-3)*l.strip.step,y=l.strip.y,r=l.strip.r}
     if near(x,y,slot) then return "slot",first+i-1 end
   end
 end
 -- ATACAR serves as a directional attack joystick, not a static button.
 if near(x,y,l.fire) then
   if self.fireId==nil then
     self.fireId=id
     self:attackJoystick(x,y,l)
     return "attack"
   end
   return nil
 end
 if near(x,y,l.auto) then self.auto=not self.auto;return "server_auto",self.auto end
 for i,p in ipairs(l.skills) do
   if near(x,y,p) then return "skill",i end
 end
 -- A left thumb remains captured even if it crosses the screen.
 if x<w*.35 and y>h*.38 and self.moveId==nil then
   self.moveId=id;self.moveOrigin={x=x,y=y}
   self:joystick(x,y,l)
   return "move"
 end
 -- No invisible separate right-side aiming joystick.
 -- Aiming works ONLY while holding the ATACAR button.
 return nil
end
function M:moved(id,x,y,w,h)
 if id==self.moveId and self.moveOrigin then
   self:joystick(x,y,self:layout(w,h))
   return "move"
 end
 if id==self.fireId then
   self:attackJoystick(x,y,self:layout(w,h))
   return "aim"
 end
 return nil
end
function M:released(id)
 if self.moveId==id then
   self.moveId=nil;self.moveOrigin=nil;self.moveX=0;self.moveY=0;return "move"
 end
 if self.fireId==id then
   self.fireId=nil
   self.fireOffsetX=0;self.fireOffsetY=0
   return "attack"
 end
 return nil
end
local function ring(g,p,active,accent)
 -- Small number of primitive draws; no new textures, canvases or shaders per frame.
 local r=p.r
 g.setColor(.015,.036,.037,.67);g.circle("fill",p.x+2,p.y+3,r+4)
 g.setColor(active and .23 or .09,active and .41 or .17,active and .26 or .19,.92)
 g.circle("fill",p.x,p.y,r)
 g.setColor(accent and .89 or .45,accent and .76 or .75,accent and .35 or .72,1)
 g.setLineWidth(2.4);g.circle("line",p.x,p.y,r-1)
 g.setColor(.87,.96,.93,.22);g.arc("line","open",p.x,p.y,r-5,math.pi*1.09,math.pi*1.86)
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
 ring(g,l.chat,false,false);glyph(g,"chat",l.chat,u)
 ring(g,l.rank,false,false);glyph(g,"ranking",l.rank,u)
 ring(g,l.pause,false,false);glyph(g,"pause",l.pause,u)
 ring(g,l.move,self.moveId~=nil,false)
 local x=self.moveOrigin and self.moveOrigin.x or l.move.x
 local y=self.moveOrigin and self.moveOrigin.y or l.move.y
 g.setColor(.67,.94,.79,.93)
 g.circle("fill",x+self.moveX*l.move.r*.48,y+self.moveY*l.move.r*.48,26*u)
 g.setColor(.12,.31,.23,1)
 g.circle("line",x+self.moveX*l.move.r*.48,y+self.moveY*l.move.r*.48,25*u)
 ring(g,l.fire,self:attacking(),true)
 if self:attacking() then
   local px=l.fire.x+self.fireOffsetX
   local py=l.fire.y+self.fireOffsetY
   if self.fireOffsetX~=0 or self.fireOffsetY~=0 then
     g.setColor(.95,.80,.40,.56)
     g.setLineWidth(4*u)
     g.line(l.fire.x,l.fire.y,px,py)
   end
   g.setColor(.89,.74,.41,.95)
   g.circle("fill",px,py,23*u)
   g.setColor(.16,.28,.21,1)
   g.setLineWidth(2*u)
   g.circle("line",px,py,23*u)
   glyph(g,"attack",{x=px,y=py},u*.66,true)
 else
   glyph(g,"attack",l.fire,u,false)
 end
 ring(g,l.auto,self.auto,true);glyph(g,"auto",l.auto,u,self.auto)
 -- The first four are the exact first four quick slots, not fake cooldown skills.
 for i,p in ipairs(l.skills) do
   ring(g,p,false,false)
   local id,weapon=Slots.at(world,i)
   local item=id and (weapon and Catalog.weaponById(id) or Catalog.itemById(id))
   if item and Icons.draw(weapon and "weapon" or "item",item,p.x,p.y,p.r*1.3) then
     g.setColor(.04,.13,.12,.92);g.circle("fill",p.x+p.r*.6,p.y+p.r*.6,10*u)
     g.setFont(small);g.setColor(1,1,1,1)
     g.printf(tostring(i),p.x+p.r*.6-10*u,p.y+p.r*.6-6*u,20*u,"center")
   else
     words(g,tostring(i),p)
   end
 end
 -- All inventory entries from #5 onward, horizontally in the centre.
 local total=Slots.total(world)
 local pageCount=Slots.pages(world,5)
 self.page=clamp(self.page,1,pageCount)
 if total>4 then
   local first=5+(self.page-1)*5
   local count=min(5,total-first+1)
   for i=1,count do
     local p={x=l.strip.x+(i-3)*l.strip.step,y=l.strip.y,r=l.strip.r}
     ring(g,p,false,false)
     local id,weapon=Slots.at(world,first+i-1)
     local item=id and (weapon and Catalog.weaponById(id) or Catalog.itemById(id))
     if item then Icons.draw(weapon and "weapon" or "item",item,p.x,p.y,p.r*1.34) end
   end
   if pageCount>1 then
     ring(g,l.stripPrev,false,false);words(g,"<",l.stripPrev)
     ring(g,l.stripNext,false,false);words(g,">",l.stripNext)
     g.setColor(1,1,1,1);g.setFont(small)
     g.printf(self.page.."/"..pageCount,l.strip.x-38*u,h-104*u,76*u,"center")
   end
 end
 g.pop()
end
return M
