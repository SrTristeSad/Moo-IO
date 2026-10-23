-- Moo-IO Android HUD / two-thumb input. Actions are processed by real Node server.
local M={}
M.__index=M
local atan2=math.atan2 or function(y,x)return math.atan(y,x)end
local sqrt=math.sqrt
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
local function near(x,y,p)return (x-p.x)^2+(y-p.y)^2<=p.r^2 end
local function inBox(x,y,b)return x>=b.x and y>=b.y and x<=b.x+b.w and y<=b.y+b.h end
local messages={"Vamos!","Inimigo!","Aqui!","Preciso de ajuda!","Reunam-se!","Boa!"}
M.messages=messages
function M.new()
 return setmetatable({moveId=nil,moveOrigin=nil,moveX=0,moveY=0,
   lastX=0,lastY=-1,run=false,aimId=nil,aimOrigin=nil,aimDir=0,
   fireId=nil,auto=false,mapOpen=false,chatOpen=false,bagOpen=false,
   lastPoint=nil,opacity=.8},M)
end
function M:reset()
 self.moveId=nil;self.moveOrigin=nil;self.moveX=0;self.moveY=0
 self.aimId=nil;self.aimOrigin=nil;self.fireId=nil
 self.run=false;self.auto=false
 self.mapOpen=false;self.chatOpen=false;self.bagOpen=false
end
function M:layout(w,h)
 local u=clamp(math.min(w/1280,h/720),.7,2.3)
 local r=math.min(w*.52,h*.75)
 return {u=u,
   move={x=138*u,y=h-135*u,r=82*u},
   run={x=335*u,y=h-103*u,r=36*u},
   fire={x=w-116*u,y=h-133*u,r=66*u},
   auto={x=w-98*u,y=h-285*u,r=43*u},
   aim={x=w-259*u,y=h-259*u,r=45*u},
   gather={x=w-279*u,y=h-118*u,r=42*u},
   build={x=w-345*u,y=h-198*u,r=36*u},
   swap={x=w-360*u,y=h-102*u,r=34*u},
   bag={x=w-422*u,y=h-118*u,r=33*u},
   chat={x=270*u,y=54*u,r=31*u},
   pause={x=w-45*u,y=48*u,r=33*u},
   minimap={x=w-210*u,y=95*u,w=170*u,h=150*u},
   bigmap={x=(w-r)/2,y=(h-r)/2,w=r,h=r},
   close={x=w-70*u,y=44*u,r=35*u},
   modal={x=w*.24,y=h*.18,w=w*.52,h=h*.64}
 }
end
function M:movement()
 if self.moveId then return self.moveX,self.moveY end
 if self.run then return self.lastX,self.lastY end
 return 0,0
end
function M:aimAngle()return self.aimDir end
function M:attacking()return self.auto or self.fireId~=nil end
function M:stopForOverlay()
 self.run=false;self.auto=false;self.fireId=nil
 self.moveId=nil;self.moveOrigin=nil;self.moveX=0;self.moveY=0
 self.aimId=nil;self.aimOrigin=nil
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
   if inBox(x,y,l.bigmap) then
     scale=scale or 14400
     local p={x=clamp(math.floor((x-l.bigmap.x)/l.bigmap.w*scale+.5),0,scale),
       y=clamp(math.floor((y-l.bigmap.y)/l.bigmap.h*scale+.5),0,scale)}
     self.lastPoint=p;self.mapOpen=false
     return "ping",p
   end
   self.mapOpen=false;return "map_close"
 end
 if self.chatOpen then
   if near(x,y,l.close) then self.chatOpen=false;return "chat_close" end
   local row=math.floor((y-l.modal.y-56*l.u)/(l.modal.h/4))+1
   local col=x<l.modal.x+l.modal.w*.5 and 1 or 2
   local index=(row-1)*2+col
   if inBox(x,y,l.modal) and messages[index] then
     self.chatOpen=false
     return "chat_select",messages[index]
   end
   self.chatOpen=false;return "chat_close"
 end
 if self.bagOpen then
   if near(x,y,l.close) then self.bagOpen=false;return "bag_close" end
   if inBox(x,y,l.modal) then
     local col=math.floor((x-l.modal.x)/(l.modal.w/6))+1
     local row=math.floor((y-l.modal.y-55*l.u)/(l.modal.h*.34))
     if row>=0 and row<=1 and col>=1 and col<=6 then
       self.bagOpen=false;return "bag_slot",{row=row+1,column=col}
     end
   end
   self.bagOpen=false;return "bag_close"
 end
 if near(x,y,l.pause) then return "pause" end
 if inBox(x,y,l.minimap) then
   self:stopForOverlay();self.mapOpen=true
   return "map_open"
 end
 if near(x,y,l.chat) then
   self:stopForOverlay();self.chatOpen=true;return "chat_open"
 end
 if near(x,y,l.bag) then
   self:stopForOverlay();self.bagOpen=true;return "bag_open"
 end
 if near(x,y,l.build) then return "build" end
 if near(x,y,l.swap) then return "swap" end
 if near(x,y,l.gather) then return "interact" end
 if near(x,y,l.run) then
   self.run=not self.run;return "run"
 end
 if near(x,y,l.auto) then self.auto=not self.auto;return "attack" end
 if near(x,y,l.fire) and self.fireId==nil then
   self.fireId=id;return "attack"
 end
 if x<w*.45 and y>h*.3 and self.moveId==nil then
   self.run=false;self.moveId=id;self.moveOrigin={x=x,y=y}
   self:moveJoystick(x,y,l);return "move"
 end
 if x>w*.47 and y>h*.25 and self.aimId==nil then
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
local function ring(g,p,selected,a)
 g.setColor(selected and {.52,.74,.22,a} or {.13,.22,.18,a})
 g.circle("fill",p.x,p.y,p.r)
 g.setColor(selected and {1,.91,.45,1} or {.82,.91,.79,a})
 g.setLineWidth(math.max(2,p.r*.065))
 g.circle("line",p.x,p.y,p.r)
end
local function text(g,s,p,size)
 g.setColor(1,1,1,1)
 g.printf(s,p.x-p.r,p.y-size*.5,2*p.r,"center")
end
local function markMap(g,world,box,scale)
 scale=scale or 14400
 g.setColor(.06,.13,.075,.90)
 g.rectangle("fill",box.x,box.y,box.w,box.h,5,5)
 g.setColor(.46,.70,.37,1)
 g.rectangle("line",box.x,box.y,box.w,box.h,5,5)
 local function point(x,y)
   return box.x+clamp(x/scale,0,1)*box.w,
      box.y+clamp(y/scale,0,1)*box.h
 end
 local p=world and world:localPlayer() or nil
 if p and p.x and p.y then
   local x,y=point(p.x,p.y);g.setColor(1,1,1);g.circle("fill",x,y,6)
 end
 local mates=world and world.minimapData or {}
 for i=1,#mates-1,2 do
   if type(mates[i])=="number" and type(mates[i+1])=="number" then
     local x,y=point(mates[i],mates[i+1])
     g.setColor(.35,.8,1);g.circle("fill",x,y,4)
   end
 end
 for _,v in ipairs(world and world.mapPings or {}) do
   if type(v.x)=="number" and type(v.y)=="number" then
     local x,y=point(v.x,v.y)
     g.setColor(1,.8,.24)
     g.circle("line",x,y,9+(v.scale or 0)*.15)
   end
 end
 local marker=world and world.mapMarker
 if marker and marker.x and marker.y then
   local x,y=point(marker.x,marker.y)
   g.setColor(1,.9,.25);g.setLineWidth(3)
   g.line(x-7,y,x+7,y);g.line(x,y-7,x,y+7)
 end
end
local function label(g,s,x,y,w)
 g.setColor(1,1,1,1);g.printf(s,x,y,w,"center")
end
function M:draw(world,mapScale)
 local g=love.graphics
 local w,h=g.getDimensions()
 local l=self:layout(w,h)
 local u=l.u
 g.push("all")
 if self.mapOpen or self.chatOpen or self.bagOpen then
   g.setColor(0,0,0,.78);g.rectangle("fill",0,0,w,h)
   if self.mapOpen then
     markMap(g,world,l.bigmap,mapScale)
     label(g,"MARQUE UM PONTO PARA AVISAR O TIME",l.bigmap.x,l.bigmap.y-36*u,l.bigmap.w)
   else
     local b=l.modal
     g.setColor(.09,.16,.12,.97);g.rectangle("fill",b.x,b.y,b.w,b.h,10,10)
     g.setColor(.63,.81,.44);g.rectangle("line",b.x,b.y,b.w,b.h,10,10)
     label(g,self.chatOpen and "MENSAGENS RAPIDAS" or "MOCHILA - ESCOLHA UM ITEM",
       b.x,b.y+15*u,b.w)
     if self.chatOpen then
       for i,msg in ipairs(messages) do
         local col=(i-1)%2;local row=math.floor((i-1)/2)
         local x=b.x+17*u+col*b.w*.5
         local y=b.y+57*u+row*b.h/4
         g.setColor(.23,.34,.27,.97)
         g.rectangle("fill",x,y,b.w*.47,47*u,5,5)
         label(g,msg,x,y+12*u,b.w*.47)
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
   ring(g,l.close,false,.96);text(g,"X",l.close,22*u)
   g.pop();return
 end
 markMap(g,world,l.minimap,mapScale)
 ring(g,l.pause,false,.75);text(g,"II",l.pause,19*u)
 ring(g,l.chat,false,.75);text(g,"CHAT",l.chat,13*u)
 ring(g,l.move,false,.42)
 local px=self.moveOrigin and self.moveOrigin.x or l.move.x
 local py=self.moveOrigin and self.moveOrigin.y or l.move.y
 g.setColor(.83,.94,.8,.86)
 g.circle("fill",px+self.moveX*l.move.r*.5,py+self.moveY*l.move.r*.5,29*u)
 ring(g,l.run,self.run,.82);text(g,"CORRER",l.run,10*u)
 ring(g,l.auto,self.auto,.94);text(g,"AUTO",l.auto,13*u)
 ring(g,l.fire,self:attacking(),.94);text(g,"ATACAR",l.fire,15*u)
 ring(g,l.aim,self.aimId~=nil,.72);text(g,"MIRA",l.aim,12*u)
 ring(g,l.gather,false,.8);text(g,"COLETA",l.gather,11*u)
 ring(g,l.build,false,.82);text(g,"CONSTR.",l.build,10*u)
 ring(g,l.swap,false,.82);text(g,"TROCAR",l.swap,10*u)
 ring(g,l.bag,false,.82);text(g,"BOLSA",l.bag,10*u)
 g.pop()
end
return M
