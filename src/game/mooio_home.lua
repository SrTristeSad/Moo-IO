-- SPDX-License-Identifier: AGPL-3.0-only
-- Moo IO native home menu. No terminal, external HTML or original-client menu.
local Home={}
Home.__index=Home
local Network=require("src.net.mooio_network")

local palette={
  base={0.055,0.095,0.10}, panel={0.10,0.16,0.17},
  panel2={0.14,0.22,0.22}, accent={0.37,0.81,0.50},
  fg={0.94,0.97,0.94}, subdued={0.65,0.74,0.72},
  error={1.00,0.63,0.58}
}
local fonts={}
local function font(size)
  if not fonts[size] then fonts[size]=love.graphics.newFont(size) end
  love.graphics.setFont(fonts[size])
end
local function rectangle(x,y,w,h,color,radius)
  love.graphics.setColor(color)
  love.graphics.rectangle("fill",x,y,w,h,radius or 10,radius or 10)
end
local function label(s,x,y,size,color,width,align)
  font(size)
  love.graphics.setColor(color or palette.fg)
  if width then love.graphics.printf(tostring(s),x,y,width,align or "left")
  else love.graphics.print(tostring(s),x,y) end
end
local function within(px,py,x,y,w,h)
  return px>=x and py>=y and px<x+w and py<y+h
end
local function button(text,x,y,w,h,primary)
  local mx,my=love.mouse.getPosition()
  local dw,dh=love.graphics.getDimensions()
  local scale=math.min(dw/1280,dh/720)
  mx=(mx-(dw-1280*scale)/2)/scale
  my=(my-(dh-720*scale)/2)/scale
  local hovered=within(mx,my,x,y,w,h)
  local color=primary and (hovered and {0.46,0.92,0.57} or palette.accent)
    or (hovered and {0.20,0.30,0.30} or palette.panel2)
  rectangle(x,y,w,h,color,12)
  label(text,x,y+math.floor((h-20)/2)-1,20,primary and palette.base or palette.fg,w,"center")
end
local function input(value,placeholder,x,y,w,h,active)
  rectangle(x,y,w,h,active and {0.16,0.30,0.28} or palette.panel2,9)
  if active then
    love.graphics.setColor(palette.accent)
    love.graphics.rectangle("line",x+1,y+1,w-2,h-2,9,9)
  end
  local content=(value~="" and value or placeholder)
  if #content>60 then content="..."..content:sub(-57) end
  label(content..(active and "|" or ""),x+14,y+math.floor((h-18)/2),18,
    value~="" and palette.fg or palette.subdued,w-26,"left")
end
local function copy(value)
  if value and value~="" then love.system.setClipboardText(value) return true end
  return false
end
function Home.parseInvite(value)
  return Network.invite(value)
end

function Home.new()
  return setmetatable({
    screen="home",nickname="Jogador",invite="",vpnIP="",serverMode="lan",focus=nil,
    status="",error=false,hosting=false,starting=false,
    hostAddress="",hostCode="",connectionState="idle",serverLog="",
    showGrid=true,fullscreen=false,sessionTitle=""
  },Home)
end
function Home:scale(x,y)
  local w,h=love.graphics.getDimensions()
  local scale=math.min(w/1280,h/720)
  return (x-(w-1280*scale)/2)/scale,(y-(h-720*scale)/2)/scale
end
function Home:roomInvite()
  if self.hostAddress=="" or self.hostCode=="" then return "" end
  return self.hostAddress.."/"..self.hostCode
end
function Home:setStatus(message,isError)
  self.status=tostring(message or "")
  self.error=isError==true
end
function Home:click(sx,sy)
  local x,y=self:scale(sx,sy)
  if within(x,y,64,56,115,44) and self.screen~="home" then
    self.screen="home";self.focus=nil;return "back"
  end
  if self.screen=="home" then
    if within(x,y,84,279,348,66) then self.screen="play";return "play_tab" end
    if within(x,y,84,359,348,66) then self.screen="server";return "server_tab" end
    if within(x,y,84,439,348,66) then self.screen="settings";return "settings_tab" end
  elseif self.screen=="play" then
    if within(x,y,550,230,627,53) then self.focus="nickname";return "focus" end
    if within(x,y,550,353,627,53) then self.focus="invite";return "focus" end
    self.focus=nil
    if within(x,y,550,430,300,58) then return "join" end
    if within(x,y,866,430,310,58) then self.screen="server";return "server_tab" end
    if within(x,y,550,503,627,54) then return "retry" end
  elseif self.screen=="server" then
    self.focus=nil
    if not self.hosting and not self.starting then
      if within(x,y,550,238,302,52) then self.serverMode="lan";return "mode_lan" end
      if within(x,y,868,238,309,52) then self.serverMode="vpn";return "mode_vpn" end
      if self.serverMode=="vpn" and within(x,y,550,326,627,49) then self.focus="vpnIP";return "focus" end
      if within(x,y,550,self.serverMode=="vpn" and 401 or 332,627,58) then return "create" end
    elseif self.hosting then
      if within(x,y,550,412,627,58) then return "copy" end
      if within(x,y,550,486,300,58) then return "play_local" end
      if within(x,y,866,486,311,58) then return "stop" end
    end
  elseif self.screen=="settings" then
    if within(x,y,550,242,627,58) then
      self.showGrid=not self.showGrid;return "grid"
    end
    if within(x,y,550,322,627,58) then
      self.fullscreen=not self.fullscreen;return "fullscreen"
    end
  end
  return nil
end
local function backspace(s)
  local n=#s
  while n>1 and s:byte(n)>=128 and s:byte(n)<192 do n=n-1 end
  return s:sub(1,n-1)
end
function Home:keypressed(key)
  if key=="escape" then
    self.screen="home";self.focus=nil;return "back"
  end
  if self.focus then
    if key=="backspace" then self[self.focus]=backspace(self[self.focus]);return nil end
    if key=="v" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then
      local pasted=love.system.getClipboardText()
      self:textinput(pasted)
      return nil
    end
    if key=="return" or key=="kpenter" then
      self.focus=nil
      if self.screen=="play" then return "join" end
    end
    return nil
  end
  if self.screen=="home" then
    if key=="1" then self.screen="play";return "play_tab" end
    if key=="2" then self.screen="server";return "server_tab" end
    if key=="3" then self.screen="settings";return "settings_tab" end
  end
  return nil
end
function Home:textinput(s)
  if not self.focus or type(s)~="string" then return end
  if self.focus=="nickname" then
    s=s:gsub("[%c]","")
    self.nickname=(self.nickname..s):sub(1,15)
  elseif self.focus=="invite" then
    s=s:gsub("[%c%s]","")
    self.invite=(self.invite..s):sub(1,128)
  elseif self.focus=="vpnIP" then
    s=s:gsub("[^%d%.]","")
    self.vpnIP=(self.vpnIP..s):sub(1,15)
  end
end
function Home:draw(connectionState,connectionDetail)
  self.connectionState=connectionState or self.connectionState
  love.graphics.push("all")
  local w,h=love.graphics.getDimensions()
  local scale=math.min(w/1280,h/720)
  love.graphics.translate((w-1280*scale)/2,(h-720*scale)/2)
  love.graphics.scale(scale)
  rectangle(0,0,1280,720,palette.base,0)
  -- Original compact branding, with simple vector landscape decoration.
  love.graphics.setColor(0.10,0.18,0.18)
  love.graphics.circle("fill",1120,90,270)
  love.graphics.setColor(0.08,0.14,0.14)
  love.graphics.circle("fill",1210,650,380)
  love.graphics.setColor(0.17,0.29,0.25)
  love.graphics.polygon("fill",0,680,420,535,780,720)
  love.graphics.polygon("fill",600,720,1080,510,1280,595,1280,720)
  label("MOO",69,55,49,palette.fg)
  label("IO",205,60,43,palette.accent)
  label("MULTIPLAYER COMUNITARIO",72,119,14,palette.subdued)
  if self.screen=="home" then
    label("Seu mundo. Seus amigos.",84,210,31,palette.fg)
    button("JOGAR",84,279,348,66,true)
    button("SERVIDOR",84,359,348,66,false)
    button("CONFIGURACOES",84,439,348,66,false)
    rectangle(563,192,610,360,{0.10,0.17,0.17,0.85},20)
    label("CRIAR OU ENTRAR EM SALAS",598,240,28,palette.fg)
    label("Um jogador hospeda a partida e convida",598,303,19,palette.subdued)
    label("os amigos pela LAN ou VPN privada.",598,337,19,palette.subdued)
    label("Servidor Node.js + cliente Lua/LÖVE",598,432,17,palette.accent)
  else
    button("< VOLTAR",64,56,115,44,false)
    local heading=self.screen=="play" and "JOGAR" or
      self.screen=="server" and "SERVIDOR" or "CONFIGURACOES"
    label(heading,535,121,32,palette.fg)
    rectangle(520,193,686,415,{0.08,0.14,0.15,0.96},20)
    if self.screen=="play" then
      label("Seu nome",550,203,17,palette.subdued)
      input(self.nickname,"Jogador",550,230,627,53,self.focus=="nickname")
      label("Cole o convite recebido de um amigo",550,320,17,palette.subdued)
      input(self.invite,"100.80.12.34:8080/codigo",550,353,627,53,self.focus=="invite")
      button("ENTRAR NA PARTIDA",550,430,300,58,true)
      button("CRIAR SALA",866,430,310,58,false)
      button("TENTAR NOVAMENTE",550,503,627,54,false)
    elseif self.screen=="server" then
      label("Hospede um mundo no seu computador",550,207,20,palette.fg)
      if not self.hosting and not self.starting then
        button(self.serverMode=="lan" and "LAN SELECIONADA" or "REDE LOCAL",
          550,238,302,52,self.serverMode=="lan")
        button(self.serverMode=="vpn" and "VPN SELECIONADA" or "VPN PRIVADA",
          868,238,309,52,self.serverMode=="vpn")
        if self.serverMode=="vpn" then
          label("IP mostrado na sua VPN (Tailscale, ZeroTier, Radmin)",550,300,15,palette.subdued)
          input(self.vpnIP,"100.80.12.34",550,326,627,49,self.focus=="vpnIP")
          button("CRIAR SALA NA VPN",550,401,627,58,true)
          label("Os dois PCs devem estar na mesma VPN privada.",550,484,15,palette.subdued)
        else
          button("CRIAR SALA LAN",550,332,627,58,true)
          label("Amigos conectados ao mesmo roteador.",550,426,17,palette.subdued)
          label("Para jogar longe, selecione VPN PRIVADA.",550,463,15,palette.accent)
        end
        if self.serverLog~="" then
          label("LOG DO SERVIDOR",550,536,12,palette.accent)
          label(self.serverLog:sub(-110),550,553,11,palette.subdued,627,"left")
        end
      elseif self.starting and not self.hosting then
        label("Preparando o servidor e instalando dependencias...",550,291,19,palette.accent)
        label("O andamento aparece aqui. Nao feche o jogo.",550,332,18,palette.subdued)
        if self.serverLog~="" then
          label("LOG DE INICIALIZACAO",550,393,14,palette.accent)
          label(self.serverLog,550,421,12,palette.subdued,620,"left")
        end
      else
        label(self.serverMode=="vpn" and "SALA ATIVA NA VPN" or "SALA ATIVA NA LAN",550,260,18,palette.accent)
        rectangle(550,307,627,80,palette.panel2,10)
        label(self:roomInvite(),565,329,19,palette.fg,597,"center")
        button("COPIAR CONVITE",550,412,627,58,false)
        button("JOGAR AGORA",550,486,300,58,true)
        button("ENCERRAR SALA",866,486,311,58,false)
      end
    else
      label("Preferencias de jogo",550,207,19,palette.fg)
      button("GRADE DO MAPA     "..(self.showGrid and "LIGADA" or "DESLIGADA"),
        550,242,627,58,false)
      button("TELA CHEIA       "..(self.fullscreen and "LIGADA" or "DESLIGADA"),
        550,322,627,58,false)
      label("Movimento: WASD     Ataque: clique ou Espaco",550,415,17,palette.subdued)
      label("Chat: Enter       Voltar ao menu: Esc",550,454,17,palette.subdued)
    end
  end
  rectangle(70,634,1140,58,{0.10,0.16,0.16,0.96},12)
  local state=connectionState or ""
  local notice=self.status~="" and self.status or
    (state=="joining" and "Entrando na partida..." or
     state=="keyed_transport" and "Conectado. Entrando no mundo..." or
     state=="failed" and tostring(connectionDetail) or
     "Pronto para criar uma sala ou entrar com um convite.")
  local color=self.error and palette.error or palette.subdued
  label(notice,90,652,15,color,1090,"left")
  love.graphics.pop()
end
return Home
