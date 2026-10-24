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
assert(not l.run and not l.bag and not l.gather and not l.build,"no generic extra buttons")
local world={inventory={weapons={0,1,3},items={0,3,6,10,13,15,19}}}
eq(Slots.total(world),10)
for i=1,10 do
  local id,weapon=Slots.at(world,i)
  assert(type(id)=="number")
  eq(weapon,i<=3)
end
-- Growth always stays in ONE row. All unlocked options are reachable
-- by a swipe instead of a second page; taps equip only on finger release.
local three,shortBar=m:hotbar(3,w,h)
eq(#three,3);eq(three[2].x,w*.50);eq(shortBar.maxScroll,0)
local two=m:hotbar(2,w,h)
eq(two[1].x+two[2].x,w)
assert(two[1].x>three[1].x,"added choices must recenter the row")
local six,sixBar=m:hotbar(6,w,h)
eq(#six,6);eq(sixBar.maxScroll,0);eq(six[1].index,1)
eq(six[3].x+six[4].x,w)
local ten,tenBar=m:hotbar(10,w,h)
eq(#ten,10)
assert(tenBar.maxScroll>0 and tenBar.scroll==tenBar.maxScroll,
  "newly unlocked options should automatically become visible")
assert(m.page==nil and l.stripPrev==nil and l.stripNext==nil,
  "one continuous row must not have inventory paging controls")
-- Visual HUD regression: the old vertical scissor clipped the circular
-- abilities and the slot numbers against a straight horizontal edge.
local function verifySkillHUD(sw,sh)
  local skills=Mobile.new()
  local shown,bounds=skills:hotbar(6,sw,sh)
  local margin=4*bounds.rowU
  assert(#shown==6 and bounds.maxScroll==0)
  for _,button in ipairs(shown) do
    assert(button.x-button.r-margin>=bounds.clipX and
      button.x+button.r+margin<=bounds.clipX+bounds.clipW,
      "skill border/shadow must fit entirely within the scissor")
    local numberBottom=button.y+button.r*.80+button.r*.31
    assert(numberBottom+2*bounds.rowU<=bounds.bottom,
      "skill keycap number cannot be vertically cropped")
    assert(button.y-button.r-margin>=bounds.top,
      "skill wheel top shadow cannot be cropped")
  end
  local status=skills:statusLayout(sw,sh)
  assert(status.life.x+status.life.w<status.level.x,
    "health and level boxes should not overlap")
  assert(status.life.y==status.level.y and status.life.h==status.level.h,
    "health and level must be aligned")
  assert(status.level.y+status.level.h<bounds.top,
    "health and level must fit ABOVE the skill wheel")
end
verifySkillHUD(1280,720)
verifySkillHUD(1600,757) -- dimensions of the user's Android HUD screenshot
verifySkillHUD(800,360)

assert(l.clan.y==l.shop.y and l.shop.y==l.tribe.y,
  "Clan, Shop and Tribe must share the top HUD row")
assert(l.auto.x>w*.8 and l.auto.y<h*.55,
  "automatic attack button belongs to right side")
assert(l.lock.x==l.auto.x and
  l.lock.y-l.lock.r>l.auto.y+l.auto.r,
  "direction lock must be a separate button below AUTO")
-- Touching TRAVAR only emits an action; the local client must wait for a
-- successful K(0) server command before showing it as locked.
eq(m:pressed(173,l.lock.x,l.lock.y,w,h,14400,10),"lock_aim")
eq(m.aimLocked,false)
m.aimDir=1.15
eq(m:setDirectionLock(true),true)
eq(m:aimAngle(),1.15)
m:stopForOverlay()
assert(m.aimLocked and m:aimAngle()==1.15,
  "opening options or shop cannot unlock direction")
eq(m:setDirectionLock(false),false)
eq(m:aimAngle(),1.15)
assert(l.lock.y+l.lock.r < l.hotbar.y-14*l.u,
  "fixed-direction button must not interfere with ability row")
eq(m.topCollapsed,false)
local folded,foldState=m:pressed(170,l.fold.x,l.fold.y,w,h,14400,10)
eq(folded,"top_toggle");eq(foldState,true)
assert(m:pressed(171,l.shop.x,l.shop.y,w,h,14400,10)~="shop_open",
  "hidden shop button must not receive touches")
eq(m:pressed(172,l.fold.x,l.fold.y,w,h,14400,10),"top_toggle")
eq(m.topCollapsed,false)
m:abilityFeedback(2,1.25)
eq(m.abilityPulse,2);eq(m.abilityPulseAt,1.25)
eq(m:movement(),0)
-- ONE floating right joystick with distinct aim-only and attack zones.
-- Touch-down and dragging inside the ring MUST NEVER transmit manual fire.
local action=m:pressed(1,l.fire.x,l.fire.y,w,h,14400,10)
eq(action,"attack");assert(m:aiming() and not m:attacking())
eq(m.moveId,nil);eq(m:aimAngle(),0)
local mode,changed=m:moved(1,l.fire.x,l.fire.y-45,w,h)
eq(mode,"aim");eq(changed,false)
assert(math.abs(m:aimAngle()+math.pi/2)<.001,"inner upward drag must aim without firing")
assert(m.fireOffsetY<0 and m.fireOffsetX==0)
assert(not m:attacking() and m:movement()==0)
mode,changed=m:moved(1,l.fire.x-100,l.fire.y,w,h)
eq(mode,"aim");eq(changed,true)
assert(m:attacking(),"crossing outer ring must start firing")
assert(math.abs(math.abs(m:aimAngle())-math.pi)<.001,"outer left drag must aim left")
mode,changed=m:moved(1,l.fire.x-80,l.fire.y,w,h)
eq(changed,false);assert(m:attacking(),"hysteresis prevents spurious stops")
m:moved(1,l.fire.x+500,l.fire.y,w,h)
assert(m.fireOffsetX>0 and m.fireOffsetX<=l.fire.r*.75,
  "outer thumb visually clamps while captured pointer keeps aiming")
assert(math.abs(m:aimAngle())<.001)
mode,changed=m:moved(1,l.fire.x+40,l.fire.y,w,h)
eq(mode,"aim");eq(changed,true)
assert(m:aiming() and not m:attacking(),
  "moving inward stops only manual fire but retains aiming pointer")
mode,changed=m:moved(1,l.fire.x+90,l.fire.y,w,h)
eq(changed,true);assert(m:attacking(),"moving outward again restarts fire")
eq(m:released(1),"attack")
assert(not m:attacking() and not m:aiming()
  and m.fireOffsetX==0 and m.fireOffsetY==0)
assert(math.abs(m:aimAngle())<.001,"release retains last aim")
-- Lock direction while still aiming: changing the joystick angle should
-- change the underlying thumb, but never change the locked facing angle.
eq(m:pressed(174,l.fire.x,l.fire.y,w,h,14400,10),"attack")
eq(m:moved(174,l.fire.x,l.fire.y+56,w,h),"aim")
local heldDir=m:aimAngle()
eq(m:pressed(175,l.lock.x,l.lock.y,w,h,14400,10),"lock_aim")
m:setDirectionLock(true)
eq(m:moved(174,l.fire.x+110,l.fire.y,w,h),"aim")
assert(math.abs(m:aimAngle()-heldDir)<.001 and m:attacking(),
  "locked direction is held even during an outer-zone attack gesture")
eq(m:released(174),"attack")
assert(m.aimLocked and math.abs(m:aimAngle()-heldDir)<.001,
  "releasing the attack finger must preserve direction lock")
eq(m:pressed(176,l.lock.x,l.lock.y,w,h,14400,10),"lock_aim")
m:setDirectionLock(false)
assert(math.abs(m:aimAngle())<.001,
  "unlocking restores the joystick's most recent direction")
-- Left stick must work even if right attack is simultaneously held.
eq(m:pressed(2,l.move.x,l.move.y,w,h,14400,10),"move")
m:moved(2,l.move.x+55,l.move.y,w,h)
local dx,dy=m:movement()
assert(dx>.95 and math.abs(dy)<.01)
eq(m:pressed(3,l.fire.x,l.fire.y,w,h,14400,10),"attack")
assert(m.moveId==2 and m.fireId==3 and not m:attacking())
eq(m:moved(3,l.fire.x,l.fire.y+70,w,h),"aim")
assert(math.abs(m:aimAngle()-math.pi/2)<.001,
  "right thumb aims downward while left thumb moves")
assert(not m:attacking(),"inner drag cannot trigger firing")
eq(m:moved(3,l.fire.x,l.fire.y+110,w,h),"aim")
assert(m:attacking(),"multitouch outer drag must start firing")
dx,dy=m:movement()
assert(dx>.95 and math.abs(dy)<.01,"attack drag must not change left joystick")
eq(m:released(3),"attack")
m:moved(2,w-100,h-130,w,h) -- pointer crossing onto attack NEVER changes owner
assert(m.moveId==2 and not m:attacking())
eq(m:released(2),"move")
dx,dy=m:movement();eq(dx,0);eq(dy,0)
-- Second floating touch location is independent of the nominal rest positions.
local rx,ry=w*.77,h*.49
eq(m:pressed(4,rx,ry,w,h,14400,10),"attack")
assert(m.fireOrigin.x==rx and m.fireOrigin.y==ry and not m:attacking())
eq(m:moved(4,rx+40,ry,w,h),"aim")
assert(not m:attacking(),"floating joystick first aims only")
eq(m:moved(4,rx+100,ry,w,h),"aim")
assert(m:attacking(),"floating joystick switches to firing after outer drag")
assert(math.abs(m:aimAngle())<.001)
eq(m:released(4),"attack")
assert(m.fireOrigin==nil and not m:attacking())
-- No dormant base at a fixed screen coordinate.
assert(m.moveOrigin==nil and m.fireOrigin==nil)
-- Swiping along a single row does not select items or start combat.
m:hotbar(3,w,h)
local shown,bar=m:hotbar(Slots.total(world),w,h)
eq(#shown,10);assert(bar.maxScroll>0)
local visible=shown[#shown]
assert(visible.x>=bar.clipX and visible.x<=bar.clipX+bar.clipW)
eq(m:pressed(25,visible.x,visible.y,w,h,14400,10),"bar_hold")
local picked,index=m:released(25)
eq(picked,"slot");eq(index,10)
local middleX=bar.clipX+bar.clipW*.5
eq(m:pressed(26,middleX,l.hotbar.y,w,h,14400,10),"bar_hold")
eq(m:moved(26,middleX+400,l.hotbar.y,w,h),"bar_scroll")
local scrolled=m:hotbar(10,w,h)
assert(scrolled[1].x>shown[1].x,"swipe must reveal earlier options")
eq(m:released(26),"bar_release")
assert(not m:attacking() and m.moveId==nil,
  "swiping action row cannot trigger attack or movement")
local left=m:hotbar(10,w,h)
local first=left[1]
assert(first.x>=bar.clipX and first.x<=bar.clipX+bar.clipW)
eq(m:pressed(27,first.x,first.y,w,h,14400,10),"bar_hold")
picked,index=m:released(27)
eq(picked,"slot");eq(index,1)
local a,page
a,page=m:pressed(40,l.auto.x,l.auto.y,w,h,14400,10)
eq(a,"server_auto");eq(page,true)
assert(not m:attacking(),"server auto must not act as held attack button")
-- Opening an overlay or using manual attack must NEVER flip the auto toggle.
eq(m:pressed(41,l.shop.x,l.shop.y,w,h,14400,10),"shop_open")
eq(m.auto,true)
eq(m:pressed(42,l.clan.x,l.clan.y,w,h,14400,10),"clan_open")
eq(m.auto,true)
eq(m:pressed(43,l.tribe.x,l.tribe.y,w,h,14400,10),"tribe_open")
eq(m.auto,true)
eq(m:pressed(44,l.chat.x,l.chat.y,w,h,14400,10),"chat_open")
eq(m.auto,true)
eq(m:pressed(45,l.pause.x,l.pause.y,w,h,14400,10),"pause")
eq(m.auto,true)
eq(m:pressed(46,l.fire.x,l.fire.y,w,h,14400,10),"attack")
assert(not m:attacking() and m.auto==true)
eq(m:moved(46,l.fire.x+120,l.fire.y,w,h),"aim")
assert(m:attacking() and m.auto==true,
  "manual firing may coexist with AUTO without toggling it")
eq(m:moved(46,l.fire.x+30,l.fire.y,w,h),"aim")
assert(not m:attacking() and m.auto==true)
eq(m:released(46),"attack")
eq(m.auto,true)
m:stopForOverlay();eq(m.auto,true)
-- The map and rankings must also preserve active auto-gather.
-- Only explicitly pressing AUTO may switch it off.
a,page=m:pressed(47,l.auto.x,l.auto.y,w,h,14400,10)
eq(a,"server_auto");eq(page,false)
assert(l.ping.x>l.minimap.x+l.minimap.w and l.mark.x>l.minimap.x+l.minimap.w,
  "PING and MAPA must stay visible at the right of the minimap")
eq(m:pressed(48,l.ping.x,l.ping.y,w,h,14400,10),"ping_here")
eq(m:pressed(49,l.mark.x,l.mark.y,w,h,14400,10),"map_open")
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
eq(m:pressed(51,l.shop.x,l.shop.y,w,h,14400,10),"shop_open")
eq(m:pressed(52,l.clan.x,l.clan.y,w,h,14400,10),"clan_open")
eq(m:pressed(55,l.tribe.x,l.tribe.y,w,h,14400,10),"tribe_open")
-- Movement ring and attack ring must each follow their own finger-down point.
local mx,my=w*.20,h*.65
eq(m:pressed(53,mx,my,w,h,14400,10),"move")
assert(m.moveOrigin.x==mx and m.moveOrigin.y==my)
eq(m:pressed(54,w*.80,h*.63,w,h,14400,10),"attack")
assert(m.fireOrigin.x==w*.80 and m.fireOrigin.y==h*.63)
eq(m:released(53),"move")
assert(m.fireOrigin and m:aiming(),"releasing movement must not stop independent aiming")
eq(m:released(54),"attack")
local before=m:layout(w,h)
m:configure(1.55,.55)
local adjusted=m:layout(w,h)
assert(before~=adjusted and adjusted.move.r>before.move.r,
  "resizing HUD must rebuild geometry and enlarge controls")
assert(m.uiOpacity==.55)
m:configure(100,-2)
assert(m.uiScale==1.55 and m.uiOpacity==.5,"settings must clamp")
m:setDirectionLock(true)
m:reset()
assert(not m:aimLocked and m.lockedDir==nil)
assert(not m:attacking() and m.moveId==nil)
print("MOO IO ANDROID TOUCH STABLE PASS")
