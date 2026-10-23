-- In-game store and Tribe/Alliance overlays from the ORIGINAL browser UI.
-- Sources: client/src/index.js generateStoreList/showAllianceMenu and
-- client/public/html/play.html #storeButton/#allianceButton.
-- Every mutation is a packet sent to Node; UI never grants items or memberships.
local Store=require("src.game.store_catalog")
local Assets=require("src.game.reference_assets")
local P={}
P.__index=P
local fonts={}
local function font(sz)
  if not love or not love.graphics then return nil end
  if not fonts[sz] then fonts[sz]=love.graphics.newFont(sz) end
  love.graphics.setFont(fonts[sz])
  return fonts[sz]
end
local function rect(x,y,w,h,r,g,b,a)
  love.graphics.setColor(r,g,b,a or 1)
  love.graphics.rectangle("fill",x,y,w,h,5,5)
end
local function text(str,x,y,size,r,g,b)
  font(size)
  love.graphics.setColor(r or 1,g or 1,b or 1)
  love.graphics.print(tostring(str),x,y)
end
local function center(str,x,y,w,size,r,g,b)
  font(size)
  love.graphics.setColor(r or 1,g or 1,b or 1)
  love.graphics.printf(tostring(str),x,y,w,"center")
end
local function inside(x,y,left,top,w,h)
  return x>=left and x<left+w and y>=top and y<top+h
end
local function trimName(s)
  if type(s)~="string" then return "" end
  return s:match("^%s*(.-)%s*$") or ""
end
local function nameAllowed(s)
  s=trimName(s)
  return #s>=1 and #s<=7 and s:match("^[ -~]+$")~=nil
    and s:lower()~="solo"
end
P.nameAllowed=nameAllowed
function P.new()
  return setmetatable({
    opened=nil,tab=0,scroll=0,tribeName="",editing=false,
    message="",hoverItem=nil
  },P)
end
function P:close()
  self.opened=nil;self.editing=false;self.hoverItem=nil
end
function P:reset()
  self:close();self.message="";self.scroll=0
end
function P:toggle(panel)
  if self.opened==panel then self:close()
  else
    self.opened=panel;self.scroll=0;self.editing=false
    self.message="";self.hoverItem=nil
  end
end
function P:isOpen()
  return self.opened~=nil
end
function P:position(w,h)
  local pw=460
  local ph=math.min(h-104,420)
  return math.floor((w-pw)/2),math.floor((h-ph)/2),pw,ph
end
function P:buttons(w)
  -- Positioned near the original #storeButton right:330,
  -- #allianceButton right:270 (CSS gameButton top 20).
  return w-395,w-328,22,58
end
-- Rows must fit fully inside the scissor region; a fifth store row used to be half hidden.
function P:visibleRows(h)
  local ph=math.min((h or 720)-104,420)
  if self.opened=="tribe" then return math.max(1,math.floor((ph-171)/48)) end
  return math.max(1,math.floor((ph-178)/52))
end
function P:listCount(world)
  if self.opened=="store" then return #self:storeEntries() end
  if self.opened=="tribe" then
    return #(world.tribe and world.tribeMembers or world.teams)
  end
  return 0
end
function P:scrollLimit(world,h)
  return math.max(0,self:listCount(world)-self:visibleRows(h))
end
function P:scrollBy(amount,world,h)
  if not self.opened or type(amount)~="number" then return false end
  if not h and love and love.graphics then
    local _,height=love.graphics.getDimensions()
    h=height
  end
  local nextScroll=math.max(0,math.min(self:scrollLimit(world,h),
    self.scroll+amount))
  if nextScroll~=self.scroll then self.hoverItem=nil end
  self.scroll=nextScroll
  return true
end
function P:storeEntries()
  return Store.list(self.tab==1)
end
-- The browser's storeDisplay rows call showItemInfo() on mouseover
-- and hide it on mouseout. Hover only targets ACTUALLY VISIBLE rows;
-- inactive or clipped entries must not display a stale tooltip.
-- This is visual-only: no Node packet, item ownership or points change.
function P:hover(x,y,w,h)
  if self.opened~="store" then
    self.hoverItem=nil
    return nil
  end
  if type(x)~="number" or type(y)~="number" or
     type(w)~="number" or type(h)~="number" then
    self.hoverItem=nil
    return nil
  end
  local px,py,pw=self:position(w,h)
  local list=self:storeEntries()
  local limit=math.max(0,#list-self:visibleRows(h))
  local first=math.max(0,math.min(self.scroll,limit))
  local top=py+107
  local index=nil
  if x>=px+17 and x<px+pw-17 and y>=top then
    local row=math.floor((y-top)/52)
    if row>=0 and row<math.min(self:visibleRows(h),#list-first) and
      y<top+row*52+50 then
      index=first+row+1
    end
  end
  self.hoverItem=index and list[index] or nil
  return self.hoverItem
end
function P:storeAction(world,entry)
  if not entry then return nil end
  local accessory=self.tab==1
  local owned=(accessory and world.store.accessories or world.store.hats)[entry.id]
  local selected=(accessory and world.store.accessoryIndex
    or world.store.hatIndex)==entry.id
  if owned then
    return {packet="c",args={0,selected and 0 or entry.id,accessory and 1 or 0}}
  end
  if (world.resources.points or 0)>=entry.price then
    return {packet="c",args={1,entry.id,accessory and 1 or 0}}
  end
  return nil
end
function P:storeButtonLabel(world,item)
  local accessory=self.tab==1
  local owned=(accessory and world.store.accessories or world.store.hats)[item.id]
  local active=(accessory and world.store.accessoryIndex or world.store.hatIndex)==item.id
  if owned then return active and "Unequip" or "Equip" end
  return (world.resources.points or 0)<item.price and "No gold" or "Buy"
end
function P:clanJoinAvailable(world,team)
  if world.tribe then return false end
  if not team or type(team.sid)~="string" then return false end
  local p=world:localPlayer()
  if team.clan and (not p or p.clan~=team.sid) then return false end
  return true
end
function P:click(world,x,y,w,h)
  if type(x)~="number" or type(y)~="number" then return nil end
  local storeX,tribeX,top,size=self:buttons(w)
  if inside(x,y,storeX,top,size,size) then
    self:toggle("store");return {consumed=true}
  end
  if inside(x,y,tribeX,top,size,size) then
    self:toggle("tribe");return {consumed=true}
  end
  -- Join request notifications are independent of the open window.
  if world.tribeOwner and #world.joinRequests>0 then
    local request=world.joinRequests[1]
    local acceptX,denyX=w-330,w-388
    if inside(x,y,acceptX,94,52,37) then
      return {packet="P",args={request.sid,true},consumed=true,
        consumeRequest=true}
    end
    if inside(x,y,denyX,94,52,37) then
      return {packet="P",args={request.sid,false},consumed=true,
        consumeRequest=true}
    end
  end
  if not self.opened then return nil end
  local px,py,pw,ph=self:position(w,h)
  self.scroll=math.min(self.scroll,self:scrollLimit(world,h))
  if not inside(x,y,px,py,pw,ph) then
    self:close()
    return {consumed=true}
  end
  if inside(x,y,px+pw-43,py+11,32,32) then
    self:close();return {consumed=true}
  end
  if self.opened=="store" then
    if inside(x,y,px+20,py+55,201,41) then
      self.tab=0;self.scroll=0;self.hoverItem=nil
      return {consumed=true}
    end
    if inside(x,y,px+239,py+55,201,41) then
      self.tab=1;self.scroll=0;self.hoverItem=nil
      return {consumed=true}
    end
    local list=self:storeEntries()
    local rows=self:visibleRows(h)
    if inside(x,y,px+310,py+ph-72,55,29) then
      self:scrollBy(-rows,world,h)
      return {consumed=true}
    end
    if inside(x,y,px+374,py+ph-72,62,29) then
      self:scrollBy(rows,world,h)
      return {consumed=true}
    end
    local topY=py+107
    for i=1,math.min(rows,#list-self.scroll) do
      local row=topY+(i-1)*52
      if inside(x,y,px+17,row,pw-34,50) then
        local entry=list[self.scroll+i]
        self.hoverItem=entry
        if inside(x,y,px+328,row+7,105,36) then
          local order=self:storeAction(world,entry)
          if order then order.consumed=true;return order end
          self.message="Not enough gold."
        end
        return {consumed=true}
      end
    end
  else
    if world.tribe then
      if inside(x,y,px+28,py+ph-69,pw-56,46) then
        self.message="Waiting for Node confirmation..."
        return {packet="N",args={},consumed=true}
      end
      if world.tribeOwner then
        for i=1,math.min(self:visibleRows(h),#world.tribeMembers-self.scroll) do
          local member=world.tribeMembers[self.scroll+i]
          local row=py+99+(i-1)*48
          if member and member.sid~=world.sid and
            inside(x,y,px+344,row+4,82,34) then
            return {packet="Q",args={member.sid},consumed=true}
          end
        end
      end
    else
      if inside(x,y,px+28,py+ph-68,244,44) then
        self.editing=true;return {consumed=true}
      end
      if inside(x,y,px+284,py+ph-68,145,44) then
        local name=trimName(self.tribeName)
        if nameAllowed(name) then
          self.message="Waiting for Node confirmation..."
          self.editing=false
          return {packet="L",args={name},consumed=true}
        end
        self.message="Tribe name: 1-7 ASCII characters."
        return {consumed=true}
      end
      for i=1,math.min(self:visibleRows(h),#world.teams-self.scroll) do
        local team=world.teams[self.scroll+i]
        if team and self:clanJoinAvailable(world,team) and
          inside(x,y,px+345,py+99+(i-1)*48,78,35) then
          self.message="Join requested: "..team.sid
          return {packet="b",args={team.sid},consumed=true}
        end
      end
    end
  end
  return {consumed=true}
end
function P:wheelmoved(_,dy,world,h)
  if type(dy)~="number" then return false end
  return self:scrollBy(-math.floor(dy),world,h)
end
function P:textinput(s)
  if self.opened~="tribe" or not self.editing or type(s)~="string" then return false end
  for i=1,#s do
    local b=s:byte(i)
    if b>=32 and b<=126 and #self.tribeName<7 then
      self.tribeName=self.tribeName..string.char(b)
    end
  end
  return true
end
function P:keypressed(key,world,h)
  if not self:isOpen() then return false end
  if key=="escape" then self:close();return true end
  if self.opened=="tribe" and self.editing and key=="backspace" then
    self.tribeName=self.tribeName:sub(1,-2);return true
  end
  if key=="up" then return self:scrollBy(-1,world,h) end
  if key=="down" then return self:scrollBy(1,world,h) end
  if key=="pageup" then return self:scrollBy(-self:visibleRows(h),world,h) end
  if key=="pagedown" then return self:scrollBy(self:visibleRows(h),world,h) end
  return true
end
local function button(label,x,y,w,h,active,enabled)
  local tint=active and {0.51,0.85,0.31} or {0.28,0.29,0.29}
  if not enabled then tint={0.26,0.26,0.26} end
  rect(x,y,w,h,tint[1],tint[2],tint[3],0.95)
  center(label,x,y+math.floor((h-16)/2),w,16,
    enabled and 1 or 0.6,enabled and 1 or 0.6,enabled and 1 or 0.6)
end
local function preview(entry,accessory,x,y)
  local filename=accessory and ("access_"..entry.id..".png") or
    ("hat_"..entry.id..(entry.topSprite and "_p" or "")..".png")
  return Assets.draw(accessory and "accessories" or "hats",
    filename,x+24,y+24,43,43)
end
function P:draw(world)
  local w,h=love.graphics.getDimensions()
  local storeX,tribeX,top,size=self:buttons(w)
  button("Shop",storeX,top,size,size,self.opened=="store",true)
  button("Tribe",tribeX,top,size,size,self.opened=="tribe",true)
  if world.tribeOwner and #world.joinRequests>0 then
    local first=world.joinRequests[1]
    rect(w-440,88,190,49,0,0,0,0.64)
    text(first.name:sub(1,16).." wants to join",w-433,96,12)
    button("No",w-388,95,52,36,false,true)
    button("Yes",w-330,95,52,36,true,true)
  end
  if not self.opened then return end
  local px,py,pw,ph=self:position(w,h)
  self.scroll=math.min(self.scroll,self:scrollLimit(world,h))
  rect(0,0,w,h,0,0,0,0.28)
  rect(px,py,pw,ph,0.10,0.12,0.12,0.90)
  center(self.opened=="store" and "STORE" or "TRIBES",px+20,py+17,pw-40,24)
  button("X",px+pw-43,py+11,32,32,false,true)
  love.graphics.setScissor(px+15,py+98,pw-30,math.max(1,ph-174))
  if self.opened=="store" then
    -- Shop from exact server-side shared/config/store.js order and prices.
    love.graphics.setScissor()
    button("Hats",px+20,py+55,201,41,self.tab==0,true)
    button("Accessories",px+239,py+55,201,41,self.tab==1,true)
    love.graphics.setScissor(px+15,py+102,pw-30,math.max(1,ph-175))
    local items=self:storeEntries()
    local y=py+107
    for i=1,math.min(self:visibleRows(h),#items-self.scroll) do
      local entry=items[i+self.scroll]
      local ry=y+(i-1)*52
      rect(px+17,ry,pw-34,50,0,0,0,0.19)
      preview(entry,self.tab==1,px+21,ry+1)
      local title=entry.name
      if #title>21 then title=title:sub(1,19)..".." end
      text(title,px+77,ry+4,16)
      local owned=(self.tab==1 and world.store.accessories or world.store.hats)[entry.id]
      if not owned then
        text(tostring(entry.price).." gold",px+77,ry+26,12,0.8,0.8,0.8)
      else
        text("Owned",px+77,ry+26,12,0.65,0.9,0.58)
      end
      local label=self:storeButtonLabel(world,entry)
      button(label,px+328,ry+7,105,36,
        label=="Equip" or label=="Unequip",label~="No gold")
    end
  else
    local members=world.tribe and world.tribeMembers or world.teams
    local y=py+99
    if not members[1] then
      center(world.tribe and "No members yet" or "No Tribes Yet",
        px+20,y+28,pw-40,18,0.8,0.8,0.8)
    end
    for i=1,math.min(self:visibleRows(h),#members-self.scroll) do
      local entry=members[i+self.scroll]
      local yy=y+(i-1)*48
      rect(px+19,yy,pw-38,44,0,0,0,0.20)
      local label=world.tribe and entry.name or entry.sid
      text(tostring(label):sub(1,21),px+35,yy+12,18)
      if world.tribe then
        if world.tribeOwner and entry.sid~=world.sid then
          button("Kick",px+344,yy+4,82,34,false,true)
        end
      elseif self:clanJoinAvailable(world,entry) then
        button("Join",px+345,yy+4,78,35,true,true)
      end
    end
  end
  love.graphics.setScissor()
  if self.opened=="tribe" then
    if world.tribe then
      text("Tribe: "..tostring(world.tribe),px+25,py+55,17)
      button(world.tribeOwner and "Delete Tribe" or "Leave Tribe",
        px+28,py+ph-69,pw-56,46,false,true)
    else
      rect(px+28,py+ph-68,244,44,0,0,0,0.33)
      text(self.tribeName..(self.editing and "|" or ""),px+40,py+ph-58,18)
      button("Create",px+284,py+ph-68,145,44,true,true)
    end
  else
    local total=#self:storeEntries()
    local first=total>0 and self.scroll+1 or 0
    local last=math.min(total,self.scroll+self:visibleRows(h))
    text("Items "..first.."-"..last.." / "..total,
      px+24,py+ph-62,14,0.75,0.77,0.75)
    button("Prev",px+310,py+ph-72,55,29,false,self.scroll>0)
    button("Next",px+374,py+ph-72,62,29,false,
      self.scroll<self:scrollLimit(world,h))
    if self.hoverItem and self.hoverItem.desc then
      font(12);love.graphics.setColor(0.81,0.86,0.80)
      love.graphics.printf(self.hoverItem.desc,px+24,py+ph-39,pw-42)
    end
  end
  if self.message~="" then
    text(self.message:sub(1,60),px+25,py+ph-17,11,0.95,0.88,0.63)
  end
end
return P
