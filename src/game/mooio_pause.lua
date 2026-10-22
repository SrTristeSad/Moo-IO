-- Original Moo IO pause/options UI. It is an overlay, not a replacement
-- scene. The authoritative world keeps rendering and receiving packets.
local Pause={}
Pause.__index=Pause
local W,H=1280,720
local F={}
local function font(n)
  if not F[n] then F[n]=love.graphics.newFont(n) end
  return F[n]
end
local rects={
  resume={410,246,460,58},
  settings={410,316,460,58},
  leave={410,448,460,58},
  rootInvite={410,379,460,58},
  grid={410,246,460,58},
  fullscreen={410,316,460,58},
  back={410,386,460,58},
  copyInvite={410,359,460,58},
  inviteBack={410,431,460,52},
  confirm={410,404,216,56},
  cancel={644,404,226,56}
}
local function coords(x,y)
  local w,h=love.graphics.getDimensions()
  local z=math.min(w/W,h/H)
  return (x-(w-W*z)/2)/z,(y-(h-H*z)/2)/z
end
local function hit(x,y,r)
  return x>=r[1] and x<r[1]+r[3] and y>=r[2] and y<r[2]+r[4]
end
local function label(text,x,y,w,h,size,color)
  love.graphics.setFont(font(size))
  if color then
    love.graphics.setColor(color[1],color[2],color[3],color[4] or 1)
  else
    love.graphics.setColor(1,1,1,1)
  end
  love.graphics.printf(text,x,y+(h-size)/2-3,w,"center")
end
local function button(text,kind,selected)
  local r=rects[kind]
  local mx,my=coords(love.mouse.getPosition())
  local active=hit(mx,my,r)
  local fill=selected and {0.41,0.71,0.25}
    or (active and {0.36,0.43,0.37} or {0.22,0.27,0.24})
  love.graphics.setColor(0.025,0.055,0.037,0.93)
  love.graphics.rectangle("fill",r[1]+4,r[2]+6,r[3],r[4],2,2)
  love.graphics.setColor(0.04,0.075,0.05,1)
  love.graphics.rectangle("fill",r[1]-2,r[2]-2,r[3]+4,r[4]+4,2,2)
  love.graphics.setColor(fill)
  love.graphics.rectangle("fill",r[1],r[2],r[3],r[4],2,2)
  love.graphics.setColor(1,1,1,0.16)
  love.graphics.rectangle("fill",r[1]+3,r[2]+3,r[3]-6,3)
  label(text,r[1],r[2],r[3],r[4],19,
    selected and {0.08,0.15,0.07} or {0.97,0.98,0.93})
end
function Pause.new()
  return setmetatable({page=nil,owner=false,confirmQuit=false},Pause)
end
function Pause:isOpen()return self.page~=nil end
function Pause:open(owner)
  self.owner=owner==true
  self.page="root"
  self.confirmQuit=false
end
function Pause:close()
  self.page=nil
  self.confirmQuit=false
end
function Pause:confirm(owner,quit)
  self.owner=owner==true
  self.confirmQuit=quit==true
  self.page="confirm"
end
function Pause:keypressed(key)
  if not self.page then return nil end
  if key=="escape" then
    if self.page=="invite" then
      self.page="root"
      return "back"
    elseif self.page=="confirm" or self.page=="settings" then
      self.page="root"
      self.confirmQuit=false
    else
      self:close()
      return "resume"
    end
    return "back"
  end
  return nil
end
function Pause:click(screenX,screenY)
  if not self.page then return nil end
  local x,y=coords(screenX,screenY)
  local function which(key)return hit(x,y,rects[key])end
  if self.page=="root" then
    if which("resume") then self:close();return "resume" end
    if which("settings") then self.page="settings";return "settings" end
    if which("rootInvite") and self.owner then
      self.page="invite"
      return "show_invite"
    end
    if which("leave") then
      if self.owner then self.page="confirm";return "confirm" end
      self:close();return "leave_guest"
    end
  elseif self.page=="settings" then
    if which("grid") then return "toggle_grid" end
    if which("fullscreen") then return "toggle_fullscreen" end
    if which("back") then self.page="root";return "back" end
  elseif self.page=="invite" then
    if which("copyInvite") then return "copy_invite" end
    if which("inviteBack") then self.page="root";return "back" end
  elseif self.page=="confirm" then
    if which("confirm") then
      local quit=self.confirmQuit
      self:close()
      return quit and "quit_owner" or "leave_owner"
    end
    if which("cancel") then self.page="root";self.confirmQuit=false;return "cancel" end
  end
  return nil
end
function Pause:draw(grid,fullscreen,inviteText)
  if not self.page then return end
  local w,h=love.graphics.getDimensions()
  love.graphics.push("all")
  love.graphics.origin()
  -- Retain the ACTUAL rendered game world visible behind the modal.
  love.graphics.setColor(0.03,0.07,0.045,0.66)
  love.graphics.rectangle("fill",0,0,w,h)
  local z=math.min(w/W,h/H)
  love.graphics.translate((w-W*z)/2,(h-H*z)/2)
  love.graphics.scale(z)
  love.graphics.setColor(0.055,0.09,0.067,0.92)
  love.graphics.rectangle("fill",360,114,560,465,5,5)
  love.graphics.setColor(0.36,0.64,0.25,1)
  love.graphics.rectangle("fill",360,114,560,7)
  love.graphics.setColor(1,1,1,0.12)
  love.graphics.rectangle("line",365,121,550,451,3,3)
  if self.page=="root" then
    label("JOGO PAUSADO",395,146,490,58,32)
    label(self.owner and "Sua sala privada continua online."
      or "O servidor continua em funcionamento.",405,205,470,31,15,
      {0.77,0.82,0.75})
    button("VOLTAR AO JOGO","resume",true)
    button("CONFIGURACOES","settings")
    if self.owner and inviteText and inviteText~="" then
      button("CONVIDAR AMIGOS","rootInvite")
    else
      button("CONVIDAR AMIGOS - SO ANFITRIAO","rootInvite")
    end
    button(self.owner and "SAIR E ENCERRAR SALA" or "SAIR DA PARTIDA","leave")
  elseif self.page=="settings" then
    label("CONFIGURACOES",395,146,490,58,31)
    label("Alteracoes aplicadas na partida.",405,205,470,31,15,
      {0.77,0.82,0.75})
    button("GRADE DO MAPA: "..(grid and "LIGADA" or "DESLIGADA"),"grid")
    button("TELA CHEIA: "..(fullscreen and "LIGADA" or "DESLIGADA"),"fullscreen")
    button("VOLTAR","back")
  elseif self.page=="invite" then
    label("CONVIDAR AMIGOS",395,146,490,58,31)
    label("Envie este convite para seus amigos.",405,217,470,31,16,
      {0.82,0.88,0.79})
    local code=tostring(inviteText or "")
    love.graphics.setColor(0.12,0.19,0.14,0.97)
    love.graphics.rectangle("fill",389,284,502,57,4,4)
    label(code~="" and code or "Convite indisponivel",399,292,482,38,
      code:len()>40 and 14 or 17)
    button("COPIAR CONVITE","copyInvite",true)
    button("VOLTAR","inviteBack")
  else
    label("ENCERRAR SUA SALA?",393,146,494,58,30)
    label("Isso desconecta todos os jogadores do mapa.",395,240,490,32,17,
      {1,0.82,0.73})
    label("Voce tem certeza?",395,290,490,36,22)
    button("SIM, ENCERRAR","confirm")
    button("CANCELAR","cancel",true)
  end
  label("ESC: voltar  |  Multiplayer: o mundo nao e pausado",
    376,508,528,35,14,{0.79,0.85,0.77})
  love.graphics.pop()
end
return Pause
