package.path="./?.lua;./?/init.lua;"..package.path
local Mobile=require("src.mobile.controls")
local Slots=require("src.mobile.slots")
local function eq(a,b)assert(a==b,tostring(a).." ~= "..tostring(b))end
local m=Mobile.new()
local w,h=1280,720
local l=m:layout(w,h)
assert(l==m:layout(w,h),"layout should reuse cached geometry on every move/draw")
assert(l~=m:layout(1365,h),"must invalidate layout after resize")
l=m:layout(w,h)
-- Larger button artwork and touch regions must match, with space between them.
local function layoutNonOverlap(w,h)
  local x=m:layout(w,h)
  local rects={{"move",x.move},{"attack",x.fire},{"auto",x.auto},
    {"ping",x.ping},{"map",x.mark},{"chat",x.chat},
    {"rank",x.rank},{"pause",x.pause}}
  for i,p in ipairs(x.skills) do rects[#rects+1]={"skill"..i,p} end
  for i=1,5 do
    rects[#rects+1]={"slot"..i,{
      x=x.strip.x+(i-3)*x.strip.step,y=x.strip.y,r=x.strip.r}}
  end
  rects[#rects+1]={"prev",x.stripPrev}
  rects[#rects+1]={"next",x.stripNext}
  for i,a in ipairs(rects) do
    local pa=a[2]
    assert(pa.x-pa.r>=0 and pa.x+pa.r<=w and pa.y-pa.r>=0 and pa.y+pa.r<=h,
      a[1].." clipped on "..w.."x"..h)
    for j=i+1,#rects do
      local b=rects[j]
      local pb=b[2]
      local dx,dy=pa.x-pb.x,pa.y-pb.y
      assert(dx*dx+dy*dy>=(pa.r+pb.r)^2,
        a[1].." overlaps "..b[1].." on "..w.."x"..h)
    end
  end
end
assert(l.fire.r>=78 and l.move.r>=96 and l.skills[1].r>=44
  and l.strip.r>=34,"controls must be enlarged for mobile")
for _,resolution in ipairs({{1280,720},{1920,1080},{960,540},{800,360},{640,360},{2400,1080}}) do
  layoutNonOverlap(resolution[1],resolution[2])
end
l=m:layout(w,h)
assert(not l.run and not l.bag and not l.gather and not l.build,"no generic extra buttons")
local world={inventory={weapons={0,1,3},items={0,3,6,10,13,15,19}}}
eq(Slots.total(world),10)
for i=1,10 do
  local id,weapon=Slots.at(world,i)
  assert(type(id)=="number")
  eq(weapon,i<=3)
end
eq(Slots.pages(world,5),2)
eq(m:movement(),0)
-- ATACAR is itself the aim joystick: drag the SAME finger to rotate the
-- weapon while continuously attacking. It never changes the movement input.
local action=m:pressed(1,l.fire.x,l.fire.y,w,h,14400,10)
eq(action,"attack");assert(m:attacking())
eq(m.moveId,nil)
eq(m:aimAngle(),0)
eq(m:moved(1,l.fire.x,l.fire.y-60,w,h),"aim")
assert(math.abs(m:aimAngle()+math.pi/2)<.001,"drag up must attack upwards")
assert(m.fireOffsetY<0 and m.fireOffsetX==0,"thumb follows attack direction")
assert(m:attacking() and m:movement()==0)
eq(m:moved(1,l.fire.x-100,l.fire.y,w,h),"aim")
assert(math.abs(math.abs(m:aimAngle())-math.pi)<.001,
  "drag left must rotate the attack to the left")
m:moved(1,l.fire.x+500,l.fire.y,w,h)
assert(m.fireOffsetX>0 and m.fireOffsetX<=l.fire.r*.62,
  "aim joystick must clamp its visual thumb, retaining pointer ownership outside")
assert(math.abs(m:aimAngle())<.001)
eq(m:released(1),"attack")
assert(not m:attacking() and m.fireOffsetX==0 and m.fireOffsetY==0)
assert(math.abs(m:aimAngle())<.001,"released attack keeps last weapon direction")
-- Left stick must work even if right attack is simultaneously held.
eq(m:pressed(2,l.move.x,l.move.y,w,h,14400,10),"move")
m:moved(2,l.move.x+55,l.move.y,w,h)
local dx,dy=m:movement()
assert(dx>.95 and math.abs(dy)<.01)
eq(m:pressed(3,l.fire.x,l.fire.y,w,h,14400,10),"attack")
assert(m.moveId==2 and m.fireId==3)
eq(m:moved(3,l.fire.x,l.fire.y+70,w,h),"aim")
assert(math.abs(m:aimAngle()-math.pi/2)<.001,
  "right thumb attack joystick aims downward while left thumb moves")
dx,dy=m:movement()
assert(dx>.95 and math.abs(dy)<.01,"attack drag must not change left joystick")
eq(m:released(3),"attack")
m:moved(2,w-100,h-130,w,h) -- pointer crossing onto attack NEVER changes owner
assert(m.moveId==2 and not m:attacking())
eq(m:released(2),"move")
dx,dy=m:movement();eq(dx,0);eq(dy,0)
-- No second invisible right-side aim area.
eq(m:pressed(4,w*.77,h*.49,w,h,14400,10),nil)
eq(m:moved(4,w*.82,h*.49,w,h),nil)
assert(math.abs(m:aimAngle()-math.pi/2)<.001)
assert(not m:attacking() and m.moveId==nil)
eq(m:released(4),nil)
-- Four first slots use original items, extra slots are in the middle.
for i,p in ipairs(l.skills) do
  local a,num=m:pressed(10+i,p.x,p.y,w,h,14400,10)
  eq(a,"skill");eq(num,i)
end
for i=1,5 do
  local x=l.strip.x+(i-3)*l.strip.step
  local a,num=m:pressed(20+i,x,l.strip.y,w,h,14400,10)
  eq(a,"slot");eq(num,i+4)
end
local a,page=m:pressed(35,l.stripNext.x,l.stripNext.y,w,h,14400,10)
eq(a,"page");eq(page,2)
a,page=m:pressed(36,l.strip.x-2*l.strip.step,l.strip.y,w,h,14400,10)
eq(a,"slot");eq(page,10)
a,page=m:pressed(37,l.stripPrev.x,l.stripPrev.y,w,h,14400,10)
eq(a,"page");eq(page,1)
a,page=m:pressed(40,l.auto.x,l.auto.y,w,h,14400,10)
eq(a,"server_auto");eq(page,true)
assert(not m:attacking(),"server E is NOT a held mouse button")
a,page=m:pressed(41,l.auto.x,l.auto.y,w,h,14400,10)
eq(a,"server_auto");eq(page,false)
eq(m:pressed(42,l.ping.x,l.ping.y,w,h,14400,10),"ping_here")
eq(m:pressed(43,l.mark.x,l.mark.y,w,h,14400,10),"map_open")
local b=m:layout(w,h).bigmap
a,page=m:pressed(44,b.x+b.w*.25,b.y+b.h*.75,w,h,14400,10)
eq(a,"ping");eq(page.x,3600);eq(page.y,10800)
eq(m:pressed(45,l.rank.x,l.rank.y,w,h,14400,10),"rank_open")
local panel=l.rankPanel
a,page=m:pressed(46,panel.x+10*l.u+(panel.w-20*l.u)*2.5/7,
  panel.y+70*l.u,w,h,14400,10)
eq(a,"rank_category");eq(page,"food")
eq(m:pressed(47,l.close.x,l.close.y,w,h,14400,10),"rank_close")
eq(m:pressed(48,l.chat.x,l.chat.y,w,h,14400,10),"chat_open")
assert(l.chatSend and l.chatCancel,"full Android keyboard chat has SEND and CLOSE")
eq(m:pressed(50,l.pause.x,l.pause.y,w,h,14400,10),"pause")
m:reset()
assert(not m:attacking() and m.moveId==nil)
print("MOO IO ANDROID TOUCH STABLE PASS")
