-- Port of the ORIGINAL JavaScript client opening screen.
-- Layout/fields based on client/public/html/play.html and css/main.css.
-- Unlike the former auto-spawn, the player chooses Play before sending M.
local World=require("src.game.world_state")
local C=require("src.game.config")
local Shapes=require("src.game.reference_primitives")
local Menu={}
Menu.__index=Menu

local colors={"#bf8f54","#cbb091","#896c4b","#fadadc","#ececec",
  "#c37373","#4c4c4c","#ecaff7","#738cc3","#8bc373"}
local function rect(x,y,w,h,r,g,b,a,radius)
  love.graphics.setColor(r,g,b,a or 1)
  love.graphics.rectangle("fill",x,y,w,h,radius or 5,radius or 5)
end
local function font(s)
  Menu.fonts=Menu.fonts or {}
  if not Menu.fonts[s] then Menu.fonts[s]=love.graphics.newFont(s) end
  love.graphics.setFont(Menu.fonts[s])
end
local function text(str,x,y,s,color)
  font(s or 18)
  local h=love.graphics.getFont():getHeight()
  local rgb=color or {0.18,0.18,0.18}
  love.graphics.setColor(rgb[1],rgb[2],rgb[3],rgb[4] or 1)
  love.graphics.print(tostring(str),x,y)
  return h
end
local function center(str,x,y,w,s,color)
  font(s or 18)
  local rgb=color or {0.18,0.18,0.18}
  love.graphics.setColor(rgb[1],rgb[2],rgb[3],rgb[4] or 1)
  love.graphics.printf(tostring(str),x,y,w,"center")
end
local function hot(x,y,px,py,w,h)
  -- x/y = pointer, px/py = element origin (same order as Menu:click).
  return x>=px and y>=py and x<px+w and y<py+h
end
local function menuView()
  local world=World.new()
  local mid=C.mapScale/2
  local trees={
    {0,mid,mid+200,4},{1,mid,mid-480,4},{2,mid+300,mid+450,4},
    {3,mid-950,mid-130,3},{4,mid-750,mid-400,4},
    {5,mid-700,mid+400,3},{6,mid+800,mid-200,4}
  }
  for _,e in ipairs(trees) do
    world.objects[e[1]]={sid=e[1],x=e[2],y=e[3],
      dir=0,scale=C.treeScales[e[4]],type=0}
  end
  local bushes={
    {7,mid-260,mid+340},{8,mid+760,mid+310},
    {9,mid-800,mid+100}
  }
  for _,e in ipairs(bushes) do
    world.objects[e[1]]={sid=e[1],x=e[2],y=e[3],
      dir=0,scale=C.bushScales[#C.bushScales],type=1}
  end
  -- The two windmills are the original prepareMenuBackground() entries
  -- using items.list[4].scale and items.list[10] as sprite data.
  world.objects[10]={sid=10,x=mid-800,y=mid+300,
    dir=0,scale=50,type=4,id=10}
  world.objects[11]={sid=11,x=mid+650,y=mid-390,
    dir=0,scale=50,type=4,id=10}
  world.objects[12]={sid=12,x=mid-400,y=mid-450,
    dir=0,scale=C.rockScales[3],type=2}
  return world
end
function Menu.new()
  return setmetatable({name="Jogador",skin=0,tab="Game",
    nameFocus=false,grid=true,world=menuView(),
    startPending=false,status="",authMode=nil,authStep="email",
    authEmail="",authCode="",authFocus="email",authFlow=nil,
    authMessage="",accountEmail=nil,
    connectionState="connecting",showTechnical=false,
    technicalMessage=""},Menu)
end
function Menu:geometry(w,h)
  local scale=math.min(w/1280,h/720)
  return scale,(w-1280*scale)/2,(h-720*scale)/2
end
function Menu:mapInput(sx,sy,w,h)
  local scale,offX,offY=self:geometry(w,h)
  return (sx-offX)/scale,(sy-offY)/scale
end
function Menu:click(sx,sy,w,h)
  local x,y=self:mapInput(sx,sy,w,h)
  -- Clicking another control unfocuses the player name, including when
  -- opening Login/Register (which otherwise return before the reset below).
  if self.authMode or not hot(x,y,393,326,370,42) then
    self.nameFocus=false
  end
  -- Dedicated compact "details" control; long filesystem paths never
  -- overlap the login/register buttons on the original right card.
  if hot(x,y,1066,307,117,30) then
    self.showTechnical=not self.showTechnical
    return "details"
  end
  if self.showTechnical and hot(x,y,833,64,367,136) then
    self.showTechnical=false
    return "details"
  end
  if self.authMode then
    if hot(x,y,839,472,161,40) then
      return self.authStep=="email" and "auth_request" or "auth_verify"
    end
    if hot(x,y,1011,472,172,40) then
      self.authMode=nil;self.authStep="email";self.authFocus=nil
      self.authMessage=""
      return "auth_back"
    end
    if hot(x,y,839,423,344,41) then
      self.authFocus=self.authStep
      return "auth_focus"
    end
    return nil
  end
  if self.accountEmail then
    if hot(x,y,839,472,161,40) then return "clan_open" end
    if hot(x,y,1011,472,172,40) then return "auth_logout" end
  else
    if hot(x,y,839,444,161,42) then
      self.authMode="login";self.authStep="email";self.authFocus="email"
      self.authMessage="";return "auth_open"
    end
    if hot(x,y,1011,444,172,42) then
      self.authMode="register";self.authStep="email";self.authFocus="email"
      self.authMessage="";return "auth_open"
    end
  end
  if hot(x,y,385,219,134,43) then self.tab="Game";return "tab" end
  if hot(x,y,519,219,133,43) then self.tab="Info";return "tab" end
  if hot(x,y,652,219,131,43) then self.tab="Settings";return "tab" end
  if self.tab=="Game" then
    if hot(x,y,393,326,370,42) then
      self.nameFocus=true
      return "focus"
    end
    if hot(x,y,396,469,112,48) then
      self.nameFocus=false
      return self:canPlay() and "play" or "play_unavailable"
    end
    for i=0,9 do
      local col,row=i%5,math.floor(i/5)
      if hot(x,y,529+col*45,403+row*45,34,34) then
        self.skin=i
        self.nameFocus=false
        return "skin"
      end
    end
  elseif self.tab=="Settings" then
    if hot(x,y,403,306,359,48) then
      self.grid=not self.grid
      return "grid"
    end
  end
  self.nameFocus=false
  return nil
end
-- Name and account inputs are editable text fields. Menu hotkeys must not
-- reconnect or respawn when the user is typing into either one.
function Menu:isEditingText()
  return self.nameFocus or self.authMode~=nil
end
function Menu:canPlay()
  return self.connectionState=="keyed_transport"
    or self.connectionState=="spawn_confirmed"
end
function Menu:connectionInfo(connectionState,details)
  local state=connectionState or "connecting"
  self.connectionState=state
  self.technicalMessage=tostring(details or "")
  if state=="keyed_transport" or state=="spawn_confirmed" then
    return "Conectado","Pronto para jogar.", "ready"
  elseif state=="joining" then
    return "Entrando","Aguardando confirmacao da partida...", "working"
  elseif state=="blocked" then
    if self.technicalMessage:find("build",1,true)
      or self.technicalMessage:find("MOOQUEST_BUILD_FILE",1,true) then
      return "Bloqueado","Build do protocolo ausente. Reinicie pelo INICIAR-WINDOWS.bat.", "error"
    end
    return "Bloqueado","Handshake recusado. Veja os detalhes tecnicos.", "error"
  elseif state=="failed" then
    return "Falha","Nao foi possivel conectar. Confira o servidor.", "error"
  elseif state=="closed" then
    return "Desconectado","Conexao encerrada. Pressione R para tentar novamente.", "error"
  end
  return "Conectando","Preparando a conexao com o servidor...", "working"
end
function Menu:keypressed(key)
  if self.authMode then
    if key=="escape" then
      self.authMode=nil;self.authMessage=""
      return "auth_back"
    elseif key=="backspace" then
      local field=self.authStep=="code" and "authCode" or "authEmail"
      local txt=self[field]
      local pos=#txt
      while pos>1 and txt:byte(pos)>=128 and txt:byte(pos)<192 do
        pos=pos-1
      end
      self[field]=txt:sub(1,pos-1)
    elseif key=="return" or key=="kpenter" then
      return self.authStep=="email" and "auth_request" or "auth_verify"
    end
    return nil
  end
  if key=="backspace" and self.nameFocus then
    local pos=#self.name
    while pos>1 and self.name:byte(pos)>=128 and self.name:byte(pos)<192 do
      pos=pos-1
    end
    self.name=self.name:sub(1,pos-1)
  elseif (key=="return" or key=="kpenter") and self.tab=="Game" then
    self.nameFocus=false
    return self:canPlay() and "play" or "play_unavailable"
  end
end
function Menu:textinput(chars)
  if type(chars)~="string" then return end
  if self.authMode then
    if self.authStep=="email" then
      local clean=chars:gsub("[%c%s]","")
      self.authEmail=(self.authEmail..clean):sub(1,120)
    else
      self.authCode=(self.authCode..chars:gsub("[^0-9]","")):sub(1,6)
    end
    return
  end
  if not self.nameFocus then return end
  local name=self.name..chars
  local count=0
  for i=1,#name do
    local byte=name:byte(i)
    if byte<128 or byte>=192 then
      count=count+1
      if count>15 then name=name:sub(1,i-1);break end
    end
  end
  self.name=name
end
function Menu:draw(connectionState,status)
  -- All labels are bounded within the original 396px right card.
  -- Store actual transport state for button hit-testing and keyboard Play.
  local connectionLabel,connectionNote,connectionType=
    self:connectionInfo(connectionState,status)
  local w,h=love.graphics.getDimensions()
  local scale,offX,offY=self:geometry(w,h)
  local previous=love.graphics.getFont()
  love.graphics.push("all")
  love.graphics.translate(offX,offY)
  love.graphics.scale(scale)
  rect(0,0,1280,720,0,0,0,0.5,0)
  center("MOOMOO.io",0,72,1280,64,{1,1,1})
  -- Three-column game menu is copied from the HTML/CSS layout, not
  -- a fabricated HUD displayed during gameplay.
  rect(68,205,285,335,1,1,1,0.97,9)
  rect(370,205,429,335,1,1,1,0.97,9)
  rect(816,205,396,335,1,1,1,0.97,9)
  text("TOP PLAYERS",86,228,18)
  text("Leaderboard disponível",87,282,14,{0.4,0.4,0.4})
  text("quando receber dados",87,304,14,{0.4,0.4,0.4})
  text("da partida.",87,326,14,{0.4,0.4,0.4})
  -- These tabs correspond to the original Game / Info / Settings HTML tabs.
  local tabs={{"Game",385,134},{"Info",519,133},{"Settings",652,131}}
  for _,entry in ipairs(tabs) do
    local selected=self.tab==entry[1]
    rect(entry[2],219,entry[3],43,selected and 1 or 0.95,
      selected and 1 or 0.95,selected and 1 or 0.95,1,1)
    if selected then rect(entry[2],258,entry[3],4,0.49,0.9,0.35,1,0) end
    center(entry[1],entry[2],230,entry[3],16)
  end
  if self.tab=="Game" then
    text("ENTER GAME",397,278,19)
    rect(393,326,370,42,0.94,0.94,0.94,1,5)
    text(self.name..(self.nameFocus and "|" or ""),407,336,19)
    rect(393,382,370,141,0.96,0.96,0.96,1,8)
    rect(397,391,112,72,1,1,1,1,6)
    -- Character preview uses the original Canvas body + arms primitives.
    local color=colors[self.skin+1]
    love.graphics.push()
    love.graphics.translate(453,423)
    love.graphics.rotate(-math.pi/4)
    Shapes.circle(20*math.cos(math.pi/4),20*math.sin(math.pi/4),7,color,"#525252",2)
    Shapes.circle(20*math.cos(-math.pi/4),20*math.sin(-math.pi/4),7,color,"#525252",2)
    Shapes.circle(0,0,21,color,"#525252",2)
    love.graphics.pop()
    local enabled=self:canPlay()
    local waiting=self.connectionState=="joining"
    rect(396,469,112,48,enabled and 0.49 or 0.80,
      enabled and 0.90 or 0.80,enabled and 0.35 or 0.80,1,6)
    center(enabled and "Play" or (waiting and "Entrando..." or "Indisponivel"),
      396,enabled and 482 or 487,112,enabled and 23 or 15,
      enabled and {0.1,0.22,0.11} or {0.4,0.4,0.4})
    if not enabled and not waiting then
      center("Aguardando servidor",396,521,112,11,{0.4,0.4,0.4})
    end
    text("SKIN COLOR",530,383,14)
    for i=0,9 do
      local col,row=i%5,math.floor(i/5)
      local x,y=529+col*45,403+row*45
      if i==self.skin then
        rect(x-3,y-3,40,40,0.19,0.19,0.19,1,7)
      end
      Shapes.color(colors[i+1])
      love.graphics.circle("fill",x+17,y+17,14)
    end
  elseif self.tab=="Info" then
    text("WELCOME",395,286,20)
    text("Build your village, gather resources,",395,324,16)
    text("and defend against other players.",395,348,16)
    text("CONTROLS",395,390,19)
    text("WASD  Move       Mouse  Aim",395,427,16)
    text("Click / Space  Gather and attack",395,453,15)
    text("Q  Food       E  Auto attack",395,479,15)
  else
    text("GAME SETTINGS",395,281,20)
    rect(403,306,359,48,0.95,0.95,0.95,1,5)
    text("Show Grid",416,318,17)
    text(self.grid and "ON" or "OFF",692,318,17)
  end
  -- Server panel: short operational status above a separately aligned
  -- account section. Technical errors never print over clickable buttons.
  text("LOCAL SERVER",839,229,19)
  love.graphics.setColor(0.87,0.87,0.87,1)
  love.graphics.rectangle("fill",839,263,344,1)
  text("LC  -  127.0.0.1:8080",839,274,16,{0.27,0.28,0.29})
  local statusColors={
    ready={0.16,0.47,0.24},
    working={0.61,0.40,0.11},
    error={0.69,0.24,0.22}
  }
  local ink=statusColors[connectionType] or statusColors.working
  local tint={
    ready={0.87,0.95,0.88}, working={0.97,0.93,0.84},
    error={0.98,0.89,0.88}
  }
  local bg=tint[connectionType] or tint.working
  rect(839,307,148,30,bg[1],bg[2],bg[3],1,6)
  center(connectionLabel,839,314,148,14,ink)
  rect(1066,307,117,30,0.93,0.93,0.93,1,6)
  center(self.showTechnical and "Fechar" or "Detalhes",1066,315,117,13,
    {0.32,0.32,0.32})
  font(13)
  love.graphics.setColor(0.36,0.37,0.38)
  love.graphics.printf(connectionNote,839,349,344,"left")
  love.graphics.setColor(0.86,0.86,0.86,1)
  love.graphics.rectangle("fill",839,387,344,1)

  -- Account section always starts at the same vertical position, regardless
  -- of how long the Node error/path is. Login and registration remain visible.
  if self.authMode then
    text(self.authMode=="register" and "CADASTRAR  (LOCAL)" or
      "ENTRAR  (LOCAL)",839,396,17,{0.19,0.20,0.21})
    rect(839,423,344,41,0.94,0.94,0.94,1,5)
    if self.authStep=="email" then
      local value=self.authEmail
      if #value>31 then value="..."..value:sub(-28) end
      text((value~="" and value or "Email")..
        (self.authFocus=="email" and "|" or ""),850,432,15,
        value~="" and {0.17,0.17,0.17} or {0.59,0.59,0.59})
    else
      text("Codigo: "..self.authCode.."|",850,432,15)
    end
    rect(839,472,161,40,0.49,0.90,0.35,1,5)
    center(self.authStep=="email" and "Continuar" or "Confirmar",
      839,482,161,15,{0.12,0.23,0.12})
    rect(1011,472,172,40,0.88,0.88,0.88,1,5)
    center("Cancelar",1011,482,172,15,{0.25,0.25,0.25})
    local helper=self.authMessage~="" and self.authMessage or
      "Teste local: qualquer codigo de 6 digitos e aceito."
    font(11);love.graphics.setColor(0.44,0.36,0.34)
    love.graphics.printf(helper,839,516,344,"left")
  elseif self.accountEmail then
    text("CONTA LOCAL CONECTADA",839,401,16,{0.16,0.47,0.24})
    local email=self.accountEmail
    if #email>38 then email=email:sub(1,35).."..." end
    text(email,839,435,14,{0.31,0.31,0.31})
    rect(839,472,161,40,0.49,0.90,0.35,1,5)
    center("Meu cla",839,482,161,15,{0.12,0.23,0.12})
    rect(1011,472,172,40,0.92,0.92,0.92,1,5)
    center("Sair da conta",1011,482,172,15)
  else
    text("CONTA LOCAL",839,402,17,{0.22,0.22,0.22})
    rect(839,444,161,42,0.49,0.90,0.35,1,6)
    center("Entrar",839,456,161,16,{0.12,0.25,0.11})
    rect(1011,444,172,42,0.88,0.88,0.88,1,6)
    center("Cadastrar",1011,456,172,16,{0.25,0.25,0.25})
    font(12);love.graphics.setColor(0.42,0.42,0.42)
    love.graphics.printf("Ou jogue como convidado usando Play. Contas apenas para testes locais.",
      839,498,344,"left")
  end
  -- Optional technical details display above the cards instead of covering
  -- account fields or drowning the right panel in filesystem paths.
  if self.showTechnical then
    rect(833,64,367,136,0.12,0.14,0.17,0.97,8)
    text("DETALHES DA CONEXAO",851,77,16,{1,1,1})
    font(12);love.graphics.setColor(0.87,0.89,0.92)
    local detail=self.technicalMessage
    if detail=="" then detail="Sem erros tecnicos; aguardando servidor." end
    if #detail>300 then detail=detail:sub(1,297).."..." end
    love.graphics.printf(detail,851,103,332,"left")
    text("Clique em Detalhes para fechar.",851,176,11,{0.75,0.8,0.85})
  end
  center("WASD - Movement       Click / Space - Gather / Attack",
    0,635,1280,18,{1,1,1})
  love.graphics.pop()
  love.graphics.setFont(previous)
end
return Menu
