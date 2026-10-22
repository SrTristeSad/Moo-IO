-- SPDX-License-Identifier: AGPL-3.0-only
-- Moo IO: personal play rooms are separate from dedicated server providers.
-- Gameplay authority remains in the existing Node process; no bots or fake world.
local Network=require("src.net.mooio_network")
local Home={}
Home.__index=Home

local C={
  bg={0.052,0.083,0.095}, panel={0.088,0.139,0.151},
  raised={0.119,0.185,0.196}, border={0.20,0.29,0.30},
  green={0.42,0.88,0.57}, greenDark={0.052,0.14,0.11},
  white={0.94,0.97,0.97}, muted={0.65,0.75,0.76},
  amber={1.0,0.77,0.46}, red={1.0,0.53,0.49}
}
local fonts={}
local function f(n)
  if not fonts[n] then fonts[n]=love.graphics.newFont(n) end
  love.graphics.setFont(fonts[n])
end
local function panel(x,y,w,h,color,r)
  love.graphics.setColor(color or C.panel)
  love.graphics.rectangle("fill",x,y,w,h,r or 15,r or 15)
end
local function printText(t,x,y,size,color,w,align)
  f(size or 17); love.graphics.setColor(color or C.white)
  if w then love.graphics.printf(tostring(t),x,y,w,align or "left")
  else love.graphics.print(tostring(t),x,y) end
end
local function inside(x,y,b)
  return x>=b[1] and y>=b[2] and x<b[1]+b[3] and y<b[2]+b[4]
end
local boxes={
  back={55,56,156,44},
  homePlay={95,278,400,68},homeServers={95,362,400,68},
  homeSettings={95,446,400,68},
  nickname={155,236,462,52},modeLan={155,312,223,46},
  modeVpn={393,312,224,46},vpnIP={155,368,462,46},
  createLan={155,386,462,60},createVpn={155,429,462,60},
  roomCopy={155,419,462,55},roomEnter={155,485,226,55},
  roomStop={392,485,225,55},
  joinIP={704,287,421,51},joinCode={704,359,421,51},
  join={704,430,421,54},joinRetry={704,506,421,49},
  serverLite={145,258,459,218},serverFirebase={637,258,459,218},
  serverToPlay={381,526,518,54},
  grid={355,280,570,57},fullscreen={355,364,570,57},
  overlayCopy={478,395,322,55},overlayClose={880,177,55,43}
}
local function button(id,text,primary)
  local b=boxes[id]
  local mx,my=love.mouse.getPosition()
  local w,h=love.graphics.getDimensions()
  local z=math.min(w/1280,h/720)
  mx=(mx-(w-1280*z)/2)/z;my=(my-(h-720*z)/2)/z
  local hover=inside(mx,my,b)
  local bg=primary and (hover and {0.51,0.96,0.65} or C.green)
     or (hover and {0.16,0.245,0.25} or C.raised)
  panel(b[1],b[2],b[3],b[4],bg,12)
  printText(text,b[1]+10,b[2]+math.floor((b[4]-21)/2),19,
     primary and C.greenDark or C.white,b[3]-20,"center")
end
local function field(id,value,placeholder,focused)
  local b=boxes[id]
  panel(b[1],b[2],b[3],b[4],C.raised,10)
  if focused then
    love.graphics.setColor(C.green)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line",b[1]+1,b[2]+1,b[3]-2,b[4]-2,10,10)
  end
  local show=value~="" and value or placeholder
  if #show>51 then show="..."..show:sub(-48) end
  printText(show..(focused and "|" or ""),b[1]+14,b[2]+15,17,
    value=="" and C.muted or C.white,b[3]-28)
end
function Home.parseInvite(value,code)
  if type(value)=="string" and type(code)=="string" and #code>0
    and not value:find("/",1,true) then
    local host=value:match("^%s*(.-)%s*$")
    if host and not host:find(":",1,true) then host=host..":8080" end
    return Network.invite(host.."/"..code)
  end
  return Network.invite(value)
end
function Home.new()
  return setmetatable({
    screen="home",nickname="Jogador",invite="",joinCode="",vpnIP="",
    serverMode="lan",provider="lite",focus=nil,
    status="",error=false,hosting=false,starting=false,
    hostAddress="",hostCode="",connectionState="idle",serverLog="",
    showGrid=true,fullscreen=false,sessionTitle="",
    roomOverlay=false,autoJoin=false
  },Home)
end
function Home:scale(x,y)
  local w,h=love.graphics.getDimensions()
  local z=math.min(w/1280,h/720)
  return (x-(w-1280*z)/2)/z,(y-(h-720*z)/2)/z
end
function Home:roomInvite()
  if self.hostAddress=="" or self.hostCode=="" then return "" end
  return self.hostAddress.."/"..self.hostCode
end
function Home:setStatus(t,err)
  self.status=tostring(t or "")
  self.error=err==true
end
function Home:click(sx,sy)
  local x,y=self:scale(sx,sy)
  if self.screen~="home" and inside(x,y,boxes.back) then
    self.screen="home";self.focus=nil;return "back"
  end
  if self.screen=="home" then
    if inside(x,y,boxes.homePlay) then
      self.screen="play";self.focus=nil;return "play_tab"
    elseif inside(x,y,boxes.homeServers) then
      self.screen="server";self.focus=nil;return "server_tab"
    elseif inside(x,y,boxes.homeSettings) then
      self.screen="settings";self.focus=nil;return "settings_tab"
    end
  elseif self.screen=="play" then
    if inside(x,y,boxes.nickname) then self.focus="nickname";return "focus" end
    if inside(x,y,boxes.joinIP) then self.focus="invite";return "focus" end
    if inside(x,y,boxes.joinCode) then self.focus="joinCode";return "focus" end
    if not self.hosting and not self.starting then
      if inside(x,y,boxes.modeLan) then self.serverMode="lan";self.focus=nil;return "mode_lan" end
      if inside(x,y,boxes.modeVpn) then self.serverMode="vpn";self.focus=nil;return "mode_vpn" end
      if self.serverMode=="vpn" and inside(x,y,boxes.vpnIP) then
        self.focus="vpnIP";return "focus"
      end
      if inside(x,y,boxes[self.serverMode=="vpn" and "createVpn" or "createLan"]) then
        self.focus=nil;return "create"
      end
    elseif self.hosting then
      if inside(x,y,boxes.roomCopy) then self.focus=nil;return "copy" end
      if inside(x,y,boxes.roomEnter) then self.focus=nil;return "play_local" end
      if inside(x,y,boxes.roomStop) then self.focus=nil;return "stop" end
    end
    if inside(x,y,boxes.join) then self.focus=nil;return "join" end
    if inside(x,y,boxes.joinRetry) then self.focus=nil;return "retry" end
    self.focus=nil
  elseif self.screen=="server" then
    if inside(x,y,boxes.serverLite) then self.provider="lite";return "provider_lite" end
    if inside(x,y,boxes.serverFirebase) then self.provider="firebase";return "provider_firebase" end
    if inside(x,y,boxes.serverToPlay) then self.screen="play";return "server_to_play" end
  elseif self.screen=="settings" then
    if inside(x,y,boxes.grid) then self.showGrid=not self.showGrid;return "grid" end
    if inside(x,y,boxes.fullscreen) then self.fullscreen=not self.fullscreen;return "fullscreen" end
  end
  return nil
end
local function removeLast(s)
  local i=#s
  while i>1 and s:byte(i)>=128 and s:byte(i)<192 do i=i-1 end
  return s:sub(1,i-1)
end
function Home:keypressed(key)
  if key=="escape" then self.screen="home";self.focus=nil;return "back" end
  if self.focus then
    if key=="backspace" then self[self.focus]=removeLast(self[self.focus]) end
    if key=="v" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then
      self:textinput(love.system.getClipboardText())
    end
    if key=="return" or key=="kpenter" then
      local from=self.focus
      self.focus=nil
      if from=="invite" then return "join" end
    end
    return nil
  end
  if self.screen=="home" then
    if key=="1" then self.screen="play";return "play_tab" end
    if key=="2" then self.screen="server";return "server_tab" end
    if key=="3" then self.screen="settings";return "settings_tab" end
  end
  if self.screen=="play" and key=="f2" then return "copy" end
  return nil
end
function Home:textinput(chars)
  if not self.focus or type(chars)~="string" then return end
  if self.focus=="nickname" then
    chars=chars:gsub("[%c]","")
    self.nickname=(self.nickname..chars):sub(1,15)
  elseif self.focus=="invite" then
    chars=chars:gsub("[%c%s]","")
    self.invite=(self.invite..chars):sub(1,128)
  elseif self.focus=="joinCode" then
    chars=chars:gsub("[^%w%-]","")
    self.joinCode=(self.joinCode..chars):sub(1,64)
  elseif self.focus=="vpnIP" then
    chars=chars:gsub("[^%d%.]","")
    self.vpnIP=(self.vpnIP..chars):sub(1,15)
  end
end
local function decorate()
  love.graphics.setColor(0.075,0.14,0.145)
  love.graphics.circle("fill",1200,15,235)
  love.graphics.setColor(0.067,0.117,0.125)
  love.graphics.circle("fill",1230,700,350)
  panel(32,32,1216,656,{0.067,0.108,0.115},24)
end
function Home:draw(state,detail)
  self.connectionState=state or self.connectionState
  love.graphics.push("all")
  local w,h=love.graphics.getDimensions(),love.graphics.getHeight()
  local z=math.min(w/1280,h/720)
  love.graphics.translate((w-1280*z)/2,(h-720*z)/2)
  love.graphics.scale(z)
  love.graphics.clear(C.bg)
  decorate()
  printText("MOO",84,66,47,C.white)
  printText("IO",221,68,44,C.green)
  printText("JOGUE COM SEUS AMIGOS",86,122,13,C.muted)
  if self.screen=="home" then
    printText("Sua aventura comeca aqui.",94,215,29,C.white)
    button("homePlay","JOGAR",true)
    button("homeServers","SERVIDORES",false)
    button("homeSettings","CONFIGURACOES",false)
    panel(583,202,575,340,C.panel,19)
    printText("JOGAR DO SEU JEITO",626,255,26,C.white)
    printText("Uma sala particular so sua.",628,325,20,C.green)
    printText("Jogue sozinho ou convide amigos.",628,361,18,C.muted)
    printText("Servidor interno, sem terminal.",628,403,17,C.muted)
  else
    button("back","< VOLTAR",false)
    if self.screen=="play" then
      printText("Jogar",135,152,34,C.white)
      printText("Sua sala particular",145,208,21,C.green)
      panel(130,194,505,402,C.panel,17)
      panel(672,194,477,402,C.panel,17)
      printText("MINHA SALA",155,207,19,C.green)
      field("nickname",self.nickname,"Seu apelido",self.focus=="nickname")
      if self.hosting then
        printText("Sala criada - amigos podem entrar.",155,316,17,C.green)
        panel(155,351,462,51,C.raised,9)
        local invite=self:roomInvite()
        printText(invite,170,365,16,C.white,432,"center")
        button("roomCopy","COPIAR CONVITE",false)
        button("roomEnter","JOGAR AGORA",true)
        button("roomStop","ENCERRAR",false)
      elseif self.starting then
        printText("Preparando sua sala...",155,331,18,C.green)
        printText("O jogo inicia o servidor automaticamente.",155,383,16,C.muted)
        printText("Ninguem precisa abrir um terminal.",155,417,16,C.muted)
        printText("Sem bots nesta versao.",155,482,15,C.muted)
      else
        button("modeLan",self.serverMode=="lan" and "LAN ATIVA" or "LAN",self.serverMode=="lan")
        button("modeVpn",self.serverMode=="vpn" and "VPN ATIVA" or "VPN",self.serverMode=="vpn")
        if self.serverMode=="vpn" then
          field("vpnIP",self.vpnIP,"IP deste PC na VPN",self.focus=="vpnIP")
          button("createVpn","CRIAR MINHA SALA",true)
        else
          button("createLan","CRIAR MINHA SALA",true)
        end
        printText("Bots: recurso previsto, ainda nao incluido.",155,513,14,C.muted)
      end
      printText("ENTRAR POR IP OU CONVITE",704,222,19,C.green)
      printText("IP, porta ou convite completo",704,256,15,C.muted)
      field("joinIP",self.invite,"192.168.1.5:8080",self.focus=="invite")
      printText("Codigo de acesso (separado ou no convite)",704,340,14,C.muted)
      field("joinCode",self.joinCode,"Codigo da sala",self.focus=="joinCode")
      button("join","ENTRAR NA SALA",true)
      button("joinRetry","TENTAR NOVAMENTE",false)
    elseif self.screen=="server" then
      printText("Servidores",140,169,34,C.white)
      printText("Servidores dedicados e descoberta de partidas.",145,220,16,C.muted)
      panel(130,239,491,265,self.provider=="lite" and C.raised or C.panel,17)
      panel(633,239,492,265,self.provider=="firebase" and C.raised or C.panel,17)
      button("serverLite","SERVIDOR V2 LITE",self.provider=="lite")
      button("serverFirebase","FIREBASE",self.provider=="firebase")
      if self.provider=="lite" then
        printText("V2 Lite",158,311,24,C.white)
        printText("Servidor dedicado comunitario.",158,355,18,C.muted)
        printText("A integracao com o protocolo V2 Lite",158,389,16,C.muted)
        printText("ainda depende da API compativel.",158,413,16,C.amber)
        printText("Firebase",661,311,24,C.white)
        printText("Contas, amigos e lista de salas.",661,355,18,C.muted)
      else
        printText("V2 Lite",158,311,24,C.white)
        printText("Servidor dedicado comunitario.",158,355,18,C.muted)
        printText("Firebase",661,311,24,C.white)
        printText("Identidade, amigos e catalogo de salas.",661,355,17,C.muted)
        printText("Exige configurar um projeto Firebase.",661,390,16,C.amber)
        printText("Nao hospeda o motor do jogo.",661,414,16,C.muted)
      end
      button("serverToPlay","ENTRAR COM IP NO JOGAR",false)
    else
      printText("Configuracoes",336,197,32,C.white)
      button("grid","GRADE DO MAPA     "..(self.showGrid and "LIGADA" or "DESLIGADA"),false)
      button("fullscreen","TELA CHEIA       "..(self.fullscreen and "LIGADA" or "DESLIGADA"),false)
      printText("WASD: mover  |  Mouse: mirar  |  Enter: chat",360,469,16,C.muted)
      printText("F2 na partida: copiar convite e chamar amigos.",360,503,16,C.muted)
    end
  end
  panel(84,620,1110,50,C.panel,10)
  local message=self.status~="" and self.status or
    (state=="joining" and "Entrando na partida..." or
     state=="keyed_transport" and "Servidor conectado. Carregando mundo..." or
     state=="failed" and tostring(detail) or
     "Escolha Jogar para criar sua sala ou entrar pelo IP.")
  if #message>135 then message=message:sub(1,132).."..." end
  printText(message,105,636,15,self.error and C.red or C.muted,1070)
  love.graphics.pop()
end
function Home:drawRoomOverlay()
  if not self.roomOverlay then return end
  local w,h=love.graphics.getDimensions()
  love.graphics.push("all")
  love.graphics.setColor(0,0,0,0.72)
  love.graphics.rectangle("fill",0,0,w,h)
  local z=math.min(w/1280,h/720)
  love.graphics.translate((w-1280*z)/2,(h-720*z)/2)
  love.graphics.scale(z)
  panel(337,166,606,388,C.panel,20)
  printText("CONVIDAR AMIGOS",383,214,27,C.white)
  printText("Compartilhe o codigo desta sala privada.",386,275,17,C.muted)
  panel(388,318,503,54,C.raised,11)
  printText(self:roomInvite(),400,334,17,C.white,478,"center")
  panel(478,395,322,55,C.green,12)
  printText("COPIAR CONVITE",478,409,20,C.greenDark,322,"center")
  panel(880,177,55,43,C.raised,10)
  printText("X",897,185,21,C.white)
  printText("F2 ou ESC para fechar",386,505,15,C.muted)
  love.graphics.pop()
end
function Home:overlayClick(sx,sy)
  if not self.roomOverlay then return nil end
  local x,y=self:scale(sx,sy)
  if inside(x,y,boxes.overlayCopy) then return "copy" end
  if inside(x,y,boxes.overlayClose) or not inside(x,y,{337,166,606,388}) then
    self.roomOverlay=false;return "close_overlay"
  end
  return "overlay"
end
return Home
