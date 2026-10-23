-- Moo-IO Android tactical HUD, built for 2-thumb controls.
-- Original visual language: do not ship copyrighted MOBA icons or textures.
-- The four skill-shaped slots trigger the first four REAL, server-owned quick slots.
local Catalog=require("src.game.catalog")
local Icons=require("src.game.reference_icons")
local M={}
M.__index=M
local sqrt=math.sqrt
local atan2=math.atan2 or function(y,x)return math.atan(y,x)end
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
local function near(x,y,p)return (x-p.x)^2+(y-p.y)^2<=p.r*p.r end
local function inside(x,y,b)return x>=b.x and y>=b.y and x<=b.x+b.w and y<=b.y+b.h end
local messages={"Vamos!","Inimigo!","Aqui!","Preciso de ajuda!","Reunam-se!","Boa!"}
local categories={"gold","health","food","wood","stone","kills","points"}
local names={gold="OURO",health="VIDA",food="COMIDA",wood="MADEIRA",
  stone="PEDRA",kills="ABATES",points="PONTOS"}
M.messages=messages
M.categories=categories
M.rankingNames=names
function M.new()
 return setmetatable({
   moveId=nil,moveOrigin=nil,moveX=0,moveY=0,lastX=0,lastY=-1,
   run=false,aimId=nil,aimOrigin=nil,aimDir=0,fireId=nil,auto=false,
   mapOpen=false,chatOpen=false,bagOpen=false,rankOpen=false,
   rankingCategory="gold",rankRefresh=0,lastPoint=nil,opacity=.85
 },M)
end
function M:reset()
 self.moveId=nil;self.moveOrigin=nil;self.moveX=0;self.moveY=0
 self.aimId=nil;self.aimOrigin=nil;self.fireId=nil
 self.auto=false;self.run=false
 self.mapOpen=false;self.chatOpen=false;self.bagOpen=false;self.rankOpen=false
 self.rankRefresh=0
end
function M:layout(w,h)
 local u=clamp(math.min(w/1280,h/720),.55,1.8)
 local side=math.min(h*.78,w*.58)
 local rankW=math.min(w*.72,660*u)
 local rankH=math.min(h*.77,535*u)
 local buttons={
   {x=w-274*u,y=h-116*u,r=39*u},
   {x=w-327*u,y=h-209*u,r=39*u},
   {x=w-246*u,y=h-307*u,r=39*u},
   {x=w-143*u,y=h-344*u,r=39*u}
 }
 return {u=u,
   move={x=137*u,y=h-139*u,r=82*u},
   run={x=285*u,y=h-95*u,r=34*u},
   fire={x=w-111*u,y=h-131*u,r=67*u},
   auto={x=w-153*u,y=h-243*u,r=39*u},
   skills=buttons,
   gather={x=w-421*u,y=h-99*u,r=33*u},
   build={x=w-430*u,y=h-185*u,r=33*u},
   swap={x=w-351*u,y=h-64*u,r=27*u},
   bag={x=w-517*u,y=h-185*u,r=32*u},
   chat={x=280*u,y=54*u,r=31*u},
   pause={x=w-44*u,y=45*u,r=28*u},
   rank={x=w-149*u,y=45*u,r=36*u},
   ping={x=220*u,y=80*u,r=27*u},
   mark={x=220*u,y=154*u,r=27*u},
   minimap={x=22*u,y=24*u,w=168*u,h=168*u},
   bigmap={x=(w-side)/2,y=(h-side)/2,w=side,h=side},
   close={x=w-53*u,y=42*u,r=28*u},
   modal={x=w*.24,y=h*.16,w=w*.52,h=h*.69},
   rankPanel={x=(w-rankW)/2,y=(h-rankH)/2,w=rankW,h=rankH}
 }
end
function M:movement()
 if self.moveId then return self.moveX,self.moveY end
 if self.run then return self.lastX,self.lastY end
 return 0,0
end
function M:aimAngle()return self.aimDir end
function M:attacking()return self.fireId~=nil end
function M:stopForOverlay()
 self.run=false;self.fireId=nil;self.moveId=nil;self.moveOrigin=nil
 self.moveX=0;self.moveY=0;self.aimId=nil;self.aimOrigin=nil
end
function M:moveJoystick(x,y,l)
 if not self.moveOrigin then return end
 local dx,dy=x-self.moveOrigin.x,y-self.moveOrigin.y
 local d=sqrt(dx*dx+dy*dy)
 if d<l.move.r*.12 then self.moveX=0;self.moveY=0;return end
 self.moveX=dx/d;self.moveY=dy/d
 self.lastX=self.moveX;self.lastY=self.moveY
end
function M:pressed(id,x,y,w,h,scale)
 local l=self:layout(w,h)
 if self.mapOpen then
   if near(x,y,l.close) then self.mapOpen=false;return "map_close" end
   if inside(x,y,l.bigmap) then
     scale=scale or 14400
     local point={x=clamp(math.floor((x-l.bigmap.x)/l.bigmap.w*scale+.5),0,scale),
       y=clamp(math.floor((y-l.bigmap.y)/l.bigmap.h*scale+.5),0,scale)}
     self.lastPoint=point;self.mapOpen=false
     return "ping",point
   end
   self.mapOpen=false;return "map_close"
 end
 if self.rankOpen then
   if near(x,y,l.close) then self.rankOpen=false;return "rank_close" end
   local panel=l.rankPanel
   if inside(x,y,{x=panel.x+12*l.u,y=panel.y+57*l.u,
       w=panel.w-24*l.u,h=49*l.u}) then
     local index=clamp(math.floor((x-(panel.x+12*l.u))/((panel.w-24*l.u)/#categories))+1,1,#categories)
     self.rankingCategory=categories[index]
     self.rankRefresh=0
     return "rank_category",self.rankingCategory
   end
   return nil
 end
 if self.chatOpen then
   if near(x,y,l.close) then self.chatOpen=false;return "chat_close" end
   local b=l.modal
   local row=math.floor((y-b.y-57*l.u)/(b.h/4))+1
   local col=x<b.x+b.w*.5 and 1 or 2
   local index=(row-1)*2+col
   if inside(x,y,b) and messages[index] then
     self.chatOpen=false;return "chat_select",messages[index]
   end
   self.chatOpen=false;return "chat_close"
 end
 if self.bagOpen then
   if near(x,y,l.close) then self.bagOpen=false;return "bag_close" end
   local b=l.modal
   if inside(x,y,b) then
     local col=math.floor((x-b.x)/(b.w/6))+1
     local row=math.floor((y-b.y-57*l.u)/(b.h*.34))
     if row>=0 and row<=1 and col>=1 and col<=6 then
       self.bagOpen=false;return "bag_slot",{row=row+1,column=col}
     end
   end
   self.bagOpen=false;return "bag_close"
 end
 if near(x,y,l.pause) then return "pause" end
 if near(x,y,l.ping) then return "ping_here" end
 if near(x,y,l.mark) or inside(x,y,l.minimap) then
   self:stopForOverlay();self.mapOpen=true;return "map_open"
 end
 if near(x,y,l.rank) then
   self:stopForOverlay();self.rankOpen=true;self.rankRefresh=0
   return "rank_open",self.rankingCategory
 end
 if near(x,y,l.chat) then self:stopForOverlay();self.chatOpen=true;return "chat_open" end
 if near(x,y,l.bag) then self:stopForOverlay();self.bagOpen=true;return "bag_open" end
 for i,button in ipairs(l.skills) do
   if near(x,y,button) then return "skill",i end
 end
 if near(x,y,l.auto) then self.auto=not self.auto;return "server_auto",self.auto end
 if near(x,y,l.fire) and self.fireId==nil then
   self.fireId=id;return "attack"
 end
 if near(x,y,l.build) then return "build" end
 if near(x,y,l.swap) then return "swap" end
 if near(x,y,l.gather) then return "interact" end
 if near(x,y,l.run) then self.run=not self.run;return "run" end
 if x<w*.44 and y>h*.31 and self.moveId==nil then
   self.run=false;self.moveId=id;self.moveOrigin={x=x,y=y}
   self:moveJoystick(x,y,l);return "move"
 end
 if x>w*.46 and y>h*.22 and self.aimId==nil then
   self.aimId=id;self.aimOrigin={x=x,y=y};return "aim"
 end
 return nil
end
function M:moved(id,x,y,w,h)
 local l=self:layout(w,h)
 if self.moveId==id then self:moveJoystick(x,y,l);return "move" end
 if self.aimId==id and self.aimOrigin then
   local dx,dy=x-self.aimOrigin.x,y-self.aimOrigin.y
   if dx*dx+dy*dy>(12*l.u)^2 then
     self.aimDir=atan2(dy,dx)
     self.aimOrigin={x=x-dx*.55,y=y-dy*.55}
   end
   return "aim"
 end
 return nil
end
function M:released(id)
 if self.moveId==id then
   self.moveId=nil;self.moveOrigin=nil;self.moveX=0;self.moveY=0;return "move"
 end
 if self.aimId==id then self.aimId=nil;self.aimOrigin=nil;return "aim" end
 if self.fireId==id then self.fireId=nil;return "attack" end
 return nil
end
local function ring(g,p,selected,alpha)
 g.setColor(selected and {.52,.73,.27,alpha} or {.13,.21,.18,alpha})
 g.circle("fill",p.x,p.y,p.r)
 g.setColor(selected and {1,.89,.46,1} or {.80,.94,.82,alpha})
 g.setLineWidth(math.max(2,p.r*.065));g.circle("line",p.x,p.y,p.r)
end
local function text(g,s,p,size)
 g.setColor(1,1,1,1)
 g.printf(s,p.x-p.r,p.y-size*.5,p.r*2,"center")
end
local function label(g,s,x,y,width)
 g.setColor(1,1,1,1);g.printf(s,x,y,width,"center")
end
local function map(g,world,b,scale)
 scale=scale or 14400
 g.setColor(.055,.12,.073,.97);g.rectangle("fill",b.x,b.y,b.w,b.h,7,7)
 local step=b.w/6
 g.setColor(.22,.36,.25,.55)
 for i=1,5 do
   local px=b.x+b.w*i/6
   local py=b.y+b.h*i/6
   g.line(px,b.y,px,b.y+b.h);g.line(b.x,py,b.x+b.w,py)
 end
 g.setColor(.48,.74,.37,1);g.rectangle("line",b.x,b.y,b.w,b.h,7,7)
 local function point(x,y)
   return b.x+clamp(x/scale,0,1)*b.w,b.y+clamp(y/scale,0,1)*b.h
 end
 local p=world and world:localPlayer()
 if p and type(p.x)=="number" and type(p.y)=="number" then
   local x,y=point(p.x,p.y)
   g.setColor(1,1,.9,1);g.circle("fill",x,y,5)
 end
 local mates=world and world.minimapData or {}
 for i=1,#mates-1,2 do
   if type(mates[i])=="number" and type(mates[i+1])=="number" then
     local x,y=point(mates[i],mates[i+1])
     g.setColor(.36,.86,1);g.circle("fill",x,y,4)
   end
 end
 for _,p in ipairs(world and world.mapPings or {}) do
   if type(p.x)=="number" and type(p.y)=="number" then
     local x,y=point(p.x,p.y)
     g.setColor(1,.86,.35,1);g.circle("line",x,y,8+(p.scale or 0)*.15)
   end
 end
 local mark=world and world.mapMarker
 if mark and type(mark.x)=="number" and type(mark.y)=="number" then
   local x,y=point(mark.x,mark.y)
   g.setColor(1,.94,.34,1);g.setLineWidth(3)
   g.line(x-8,y,x+8,y);g.line(x,y-8,x,y+8)
 end
end
function M:draw(world,scale)
 local g=love.graphics
 local w,h=g.getDimensions()
 local l=self:layout(w,h)
 local u=l.u
 g.push("all")
 if self.mapOpen or self.chatOpen or self.bagOpen or self.rankOpen then
   g.setColor(0,0,0,.8);g.rectangle("fill",0,0,w,h)
   if self.mapOpen then
     map(g,world,l.bigmap,scale)
     label(g,"TOQUE NUM PONTO PARA MARCAR PARA A EQUIPE",
       l.bigmap.x,l.bigmap.y-34*u,l.bigmap.w)
   elseif self.rankOpen then
     local b=l.rankPanel
     g.setColor(.09,.16,.12,.98);g.rectangle("fill",b.x,b.y,b.w,b.h,12,12)
     g.setColor(.54,.80,.39);g.rectangle("line",b.x,b.y,b.w,b.h,12,12)
     label(g,"TOP 10 - "..(names[self.rankingCategory] or "OURO"),
       b.x,b.y+17*u,b.w)
     local tabW=(b.w-24*u)/#categories
     for i,c in ipairs(categories) do
       local x=b.x+12*u+(i-1)*tabW
       g.setColor(c==self.rankingCategory and {.32,.57,.22,1} or {.2,.3,.25,1})
       g.rectangle("fill",x,b.y+57*u,tabW-3*u,40*u,4,4)
       label(g,names[c],x,b.y+70*u,tabW-3*u)
     end
     local list=world and world.categoryRankings and world.categoryRankings[self.rankingCategory] or {}
     for i=1,math.min(10,#list) do
       local entry=list[i];local y=b.y+112*u+(i-1)*36*u
       if i%2==0 then
         g.setColor(.16,.24,.18,.65)
         g.rectangle("fill",b.x+16*u,y-3*u,b.w-32*u,32*u)
       end
       g.setColor(1,.92,.62);g.print(tostring(i)..".",b.x+30*u,y)
       g.setColor(.93,.96,.9);g.print(tostring(entry.name or "?"):sub(1,21),b.x+76*u,y)
       g.printf(tostring(math.floor(entry.score or 0)),b.x+b.w-158*u,y,123*u,"right")
     end
     if #list==0 then label(g,"SEM DADOS - AGUARDANDO SERVIDOR",b.x,b.y+150*u,b.w) end
   else
     local b=l.modal
     g.setColor(.09,.16,.12,.97);g.rectangle("fill",b.x,b.y,b.w,b.h,9,9)
     g.setColor(.63,.81,.44);g.rectangle("line",b.x,b.y,b.w,b.h,9,9)
     label(g,self.chatOpen and "MENSAGENS RAPIDAS" or "MOCHILA - EQUIPAMENTOS",
       b.x,b.y+16*u,b.w)
     if self.chatOpen then
       for i,msg in ipairs(messages) do
         local col=(i-1)%2;local row=math.floor((i-1)/2)
         local x=b.x+12*u+col*b.w*.5
         local y=b.y+57*u+row*b.h/4
         g.setColor(.23,.34,.27,.97);g.rectangle("fill",x,y,b.w*.46,48*u,5,5)
         label(g,msg,x,y+12*u,b.w*.46)
       end
     else
       local inv=world and world.inventory or {}
       for row,items in ipairs({inv.weapons or {},inv.items or {}}) do
         for col=1,math.min(6,#items) do
           local x=b.x+(col-1)*b.w/6
           local y=b.y+57*u+(row-1)*b.h*.34
           g.setColor(.22,.29,.25,.94)
           g.rectangle("fill",x+4*u,y,b.w/6-8*u,b.h*.29,5,5)
           label(g,(row==1 and "ARMA " or "ITEM ")..items[col],
             x+4*u,y+13*u,b.w/6-8*u)
         end
       end
     end
   end
   ring(g,l.close,false,.96);text(g,"X",l.close,20*u)
   g.pop();return
 end
 map(g,world,l.minimap,scale)
 ring(g,l.ping,false,.88);text(g,"!",l.ping,25*u)
 ring(g,l.mark,false,.88);text(g,"MAP",l.mark,11*u)
 ring(g,l.rank,false,.88);text(g,"TOP10",l.rank,11*u)
 ring(g,l.pause,false,.82);text(g,"II",l.pause,18*u)
 ring(g,l.chat,false,.79);text(g,"CHAT",l.chat,12*u)
 ring(g,l.move,false,.4)
 local px=self.moveOrigin and self.moveOrigin.x or l.move.x
 local py=self.moveOrigin and self.moveOrigin.y or l.move.y
 g.setColor(.84,.95,.8,.87)
 g.circle("fill",px+self.moveX*l.move.r*.5,py+self.moveY*l.move.r*.5,28*u)
 ring(g,l.run,self.run,.82);text(g,"CORRER",l.run,9*u)
 ring(g,l.fire,self:attacking(),.98);text(g,"ATACAR",l.fire,15*u)
 for i,p in ipairs(l.skills) do
   ring(g,p,false,.91)
   local weapons=world and world.inventory and world.inventory.weapons or {}
   local items=world and world.inventory and world.inventory.items or {}
   local kind,id
   if i<=#weapons then
     kind,id="weapon",weapons[i]
   else
     kind,id="item",items[i-#weapons]
   end
   local data=kind=="weapon" and Catalog.weaponById(id) or
     kind=="item" and Catalog.itemById(id) or nil
   if not (data and Icons.draw(kind,data,p.x,p.y,p.r*1.45)) then
     text(g,tostring(i),p,19*u)
   else
     g.setColor(.04,.09,.06,.95)
     g.rectangle("fill",p.x+p.r*.36,p.y+p.r*.34,17*u,17*u,4*u,4*u)
     g.setColor(1,1,1,1)
     g.print(tostring(i),p.x+p.r*.43,p.y+p.r*.37)
   end
 end
 ring(g,l.auto,self.auto,.96);text(g,"AUTO",l.auto,13*u)
 ring(g,l.gather,false,.82);text(g,"COLETA",l.gather,10*u)
 ring(g,l.build,false,.82);text(g,"CONSTR.",l.build,10*u)
 ring(g,l.swap,false,.82);text(g,"TROCA",l.swap,9*u)
 ring(g,l.bag,false,.82);text(g,"BOLSA",l.bag,10*u)
 g.pop()
end
return M
