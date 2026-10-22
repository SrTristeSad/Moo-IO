-- SPDX-License-Identifier: AGPL-3.0-only
-- Moo IO: personal play rooms are separate from dedicated server providers.
-- Gameplay authority remains in the existing Node process; no bots or fake world.
local Network=require("src.net.mooio_network")
local Home={}
Home.__index=Home

-- Stone, soil and grass: block-game-inspired original interface. No copied textures.
local C={
  bg={0.15,0.19,0.18}, panel={0.23,0.255,0.25},
  raised={0.32,0.345,0.33}, border={0.095,0.12,0.11},
  green={0.43,0.72,0.26}, greenDark={0.10,0.19,0.095},
  white={0.96,0.955,0.89}, muted={0.79,0.81,0.76},
  amber={1.0,0.80,0.39}, red={0.99,0.52,0.43}
}
local fonts={}
local function f(n)
  if not fonts[n] then fonts[n]=love.graphics.newFont(n) end
  love.graphics.setFont(fonts[n])
end
local function panel(x,y,w,h,color,r)
  -- Dark stepped border and top-left light edge give the UI a carved-block feel.
  color=color or C.panel
  love.graphics.setColor(0.055,0.068,0.062,0.9)
  love.graphics.rectangle("fill",x+5,y+6,w,h,0,0)
  love.graphics.setColor(C.border)
  love.graphics.rectangle("fill",x-2,y-2,w+4,h+4,0,0)
  love.graphics.setColor(color)
  love.graphics.rectangle("fill",x,y,w,h,0,0)
  love.graphics.setColor(1,1,1,0.11)
  love.graphics.rectangle("fill",x+2,y+2,w-4,3)
  love.graphics.rectangle("fill",x+2,y+2,3,h-4)
  love.graphics.setColor(0,0,0,0.25)
  love.graphics.rectangle("fill",x+2,y+h-5,w-4,4)
  love.graphics.rectangle("fill",x+w-5,y+2,4,h-4)
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
  back={1041,93,171,45},
  homePlay={95,278,400,68},homeServers={95,362,400,68},
  homeSettings={95,446,400,68},
  nickname={155,236,462,52},modeLan={155,312,223,46},
  modeVpn={393,312,224,46},vpnIP={155,368,462,46},
  createLan={155,386,462,60},createVpn={155,429,462,60},
  roomCopy={155,419,462,55},roomEnter={155,485,226,55},
  roomStop={392,485,225,55},
  joinIP={704,287,421,51},joinCode={704,359,421,51},
  join={704,430,421,54},joinRetry={704,506,421,49},
  serverLite={159,274,433,58},serverFirebase={661,274,433,58},
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
  local bg=primary and (hover and {0.55,0.82,0.34} or C.green)
     or (hover and {0.39,0.43,0.40} or C.raised)
  panel(b[1],b[2],b[3],b[4],bg,0)
  if primary then
    love.graphics.setColor(0.71,0.92,0.50,0.38)
    love.graphics.rectangle("fill",b[1]+5,b[2]+4,b[3]-10,4)
  end
  printText(text,b[1]+10,b[2]+math.floor((b[4]-21)/2)-1,19,
    primary and C.greenDark or C.white,b[3]-20,"center")
end
local function field(id,value,placeholder,focused)
  local b=boxes[id]
  panel(b[1],b[2],b[3],b[4],{0.17,0.21,0.19},0)
  if focused then
    love.graphics.setColor(C.green)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line",b[1]+1,b[2]+1,b[3]-2,b[4]-2)
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
    if self.error and inside(x,y,boxes.joinRetry) then self.focus=nil;return "retry" end
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
  -- Procedural block pattern replaces placeholder gradient circles.
  for iy=0,18 do
    for ix=0,32 do
      local x,y=ix*40,iy*40
      local v=(ix*13+iy*7)%6
      local g=0.18+v*0.008
      love.graphics.setColor(g,g+0.025,g+0.006,0.33)
      love.graphics.rectangle("fill",x+1,y+1,39,39)
      love.graphics.setColor(0.07,0.09,0.075,0.12)
      love.graphics.rectangle("fill",x+1,y+36,39,3)
    end
  end
  panel(30,34,1220,657,{0.21,0.24,0.22},0)
  love.graphics.setColor(0.31,0.48,0.23)
  love.graphics.rectangle("fill",36,40,1208,13)
  love.graphics.setColor(0.49,0.70,0.31)
  love.graphics.rectangle("fill",36,40,1208,5)
  -- Pixel foliage remains decorative, never a game sprite.
  local trees={{1130,120,1},{1220,191,0.65},{1060,455,0.7}}
  for _,t in ipairs(trees) do
    love.graphics.setColor(0.30,0.20,0.13,0.55)
    love.graphics.rectangle("fill",t[1]+15*t[3],t[2]+32*t[3],20*t[3],72*t[3])
    love.graphics.setColor(0.24,0.43,0.21,0.62)
    love.graphics.rectangle("fill",t[1],t[2],62*t[3],56*t[3])
    love.graphics.setColor(0.42,0.66,0.28,0.51)
    love.graphics.rectangle("fill",t[1]+10*t[3],t[2]+9*t[3],43*t[3],27*t[3])
  end
end
function Home:draw(state,detail)
  self.connectionState=state or self.connectionState
  love.graphics.push("all")
  local w,h=love.graphics.getDimensions()
  local z=math.min(w/1280,h/720)
  love.graphics.translate((w-1280*z)/2,(h-720*z)/2)
  love.graphics.scale(z)
  love.graphics.clear(C.bg)
  decorate()
  -- Fixed header: the back button lives at the upper right, never over logo.
  love.graphics.setColor(0.09,0.12,0.095)
  love.graphics.rectangle("fill",58,72,325,83)
  love.graphics.setColor(0.20,0.29,0.19)
  love.graphics.rectangle("fill",63,77,315,73)
  printText("MOO",88,78,44,C.white)
  printText("IO",222,78,44,C.green)
  printText("MULTIPLAYER",91,127,13,C.muted)
  if self.screen=="home" then
    printText("ESCOLHA COMO JOGAR",96,213,29,C.white)
    button("homePlay","JOGAR",true)
    button("homeServers","SERVIDORES",false)
    button("homeSettings","CONFIGURACOES",false)
    panel(583,202,575,340,C.panel,0)
    printText("SEU MUNDO, SUAS REGRAS",608,255,25,C.white)
    printText("Crie uma sala particular.",612,325,20,C.green)
    printText("Entre sozinho ou chame amigos.",612,363,18,C.muted)
    printText("Sem configurar um terminal.",612,406,17,C.muted)
  else
    button("back","< VOLTAR",false)
    if self.screen=="play" then
      printText("JOGAR",132,158,31,C.white)
      panel(130,194,505,402,C.panel,0)
      panel(672,194,477,402,C.panel,0)
      printText("01  CRIAR MINHA SALA",155,204,19,C.green)
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
        printText("Privado: somente amigos com convite.",155,516,15,C.muted)
      end
      printText("02  ENTRAR EM OUTRA SALA",704,214,19,C.green)
      printText("IP, porta ou convite completo",704,256,15,C.muted)
      field("joinIP",self.invite,"192.168.1.5:8080",self.focus=="invite")
      printText("Codigo de acesso (separado ou no convite)",704,340,14,C.muted)
      field("joinCode",self.joinCode,"Codigo da sala",self.focus=="joinCode")
      button("join","ENTRAR NA SALA",true)
      if self.error then
        button("joinRetry","TENTAR NOVAMENTE",false)
      else
        printText("Entre pelo IP da rede local ou VPN privada.",706,517,15,C.muted)
      end
    elseif self.screen=="server" then
      printText("SERVIDORES",140,165,31,C.white)
      printText("Servidores dedicados e descoberta de partidas.",145,220,16,C.muted)
      panel(130,239,491,265,self.provider=="lite" and C.raised or C.panel,0)
      panel(633,239,492,265,self.provider=="firebase" and C.raised or C.panel,0)
      button("serverLite","SERVIDOR V2 LITE",self.provider=="lite")
      button("serverFirebase","FIREBASE",self.provider=="firebase")
      if self.provider=="lite" then
        printText("Servidor dedicado comunitario.",158,355,18,C.muted)
        printText("A integracao com o protocolo V2 Lite",158,389,16,C.muted)
        printText("ainda depende da API compativel.",158,413,16,C.amber)
        printText("Contas, amigos e lista de salas.",661,355,18,C.muted)
      else
        printText("Servidor dedicado comunitario.",158,355,18,C.muted)
        printText("Identidade, amigos e catalogo de salas.",661,355,17,C.muted)
        printText("Exige configurar um projeto Firebase.",661,390,16,C.amber)
        printText("Nao hospeda o motor do jogo.",661,414,16,C.muted)
      end
      button("serverToPlay","ENTRAR COM IP NO JOGAR",false)
    else
      printText("CONFIGURACOES",336,190,31,C.white)
      button("grid","GRADE DO MAPA     "..(self.showGrid and "LIGADA" or "DESLIGADA"),false)
      button("fullscreen","TELA CHEIA       "..(self.fullscreen and "LIGADA" or "DESLIGADA"),false)
      printText("WASD: mover  |  Mouse: mirar  |  Enter: chat",360,469,16,C.muted)
      printText("F2 na partida: copiar convite e chamar amigos.",360,503,16,C.muted)
    end
  end
  panel(83,614,1111,57,{0.13,0.17,0.15},0)
  local message=self.status~="" and self.status or
    (state=="joining" and "Entrando na partida..." or
     state=="keyed_transport" and "Servidor conectado. Carregando mundo..." or
     state=="failed" and tostring(detail) or
     "Escolha Jogar para criar sua sala ou entrar pelo IP.")
  if #message>135 then message=message:sub(1,132).."..." end
  love.graphics.setColor(self.error and C.red or C.green)
  love.graphics.rectangle("fill",92,625,5,35)
  printText(self.error and "ATENCAO" or "STATUS",111,627,13,
    self.error and C.red or C.green)
  printText(message,212,631,16,self.error and {1,0.85,0.77} or C.white,950)
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
  panel(337,166,606,388,C.panel,0)
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
