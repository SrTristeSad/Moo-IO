-- Moo-Quest is a Lua client for the UNMODIFIED al007ex/moomoo-clone server.
-- Real native gameplay rendering is gated by actual server C/D/a/H/I packets.
-- Never generate local entities or claim spawn before the Node server confirms it.
local Original=require("src.net.original_client")
local World=require("src.game.world_state")
local View=require("src.game.reference_view")
local Menu=require("src.game.reference_menu")
local Auth=require("src.net.local_auth")
local Config=require("src.game.config")
local Hud=require("src.game.reference_hud")
local Panels=require("src.game.reference_panels")
local Clans=require("src.game.account_clans")
local Death=require("src.game.reference_death")
local Notices=require("src.game.reference_notices")
local Profile=require("src.game.reference_profile")
local Upgrades=require("src.game.reference_upgrades")
local Assets=require("src.game.reference_assets")
local Camera=require("src.camera")
local Input=require("src.input")
local Pack=require("src.protocol.msgpack")
local client=nil
local integration=nil
local uiSmokeMode=os.getenv("MOOQUEST_UI_E2E")
local uiSmoke=uiSmokeMode~=nil and #uiSmokeMode>0
local uiAuthStarted=false
local uiSmokeTime=0
local uiSmokeClicked=false
local uiSmokeDrawn=false
local world=World.new()
local camera=nil
local menuCamera=nil
local menu=Menu.new()
local panels=Panels.new()
local profile=Profile.new()
local clans=Clans.new()
local death=Death.new()
local phase="menu"
local diagnostic=nil
local reconnectSeconds=0
local latestEvent="Nenhum io-init recebido."
local startupError=nil
local input=Input.new()
local movementClock=0
local lastMove=false
local lastAim=nil
local playerX,playerY=nil,nil
local serverPackets=0
local died=false
local heartbeatClock=0
local frameDelta=0
local chatOpen=false
local chatDraft=""
local mouseAttack=false
local spaceAttack=false
local lockDir=false
local angle
local function currentAttackDir()
  local w,h=love.graphics.getDimensions()
  local mx,my=love.mouse.getPosition()
  return angle(my-h/2,mx-w/2)
end
local function shortenChat(text)
  -- JavaScript chatBox.value.slice(0,30): keep up to 30 UTF-8 characters.
  local count=0
  for i=1,#text do
    local b=text:byte(i)
    if b<128 or b>=192 then
      count=count+1
      if count>30 then return text:sub(1,i-1) end
    end
  end
  return text
end
local function backspaceUtf8(text)
  local pos=#text
  while pos>1 do
    local b=text:byte(pos)
    if b<128 or b>=192 then break end
    pos=pos-1
  end
  return text:sub(1,pos-1)
end

function love.load()
  love.graphics.setDefaultFilter("linear","linear")
  camera=Camera.new()
  menuCamera=Camera.new()
  menuCamera:follow(Config.mapScale/2,Config.mapScale/2)
  local integrationMode=os.getenv("MOOQUEST_INTEGRATION")
  if integrationMode and #integrationMode>0 then
    integration=require("src.test_integration").new(integrationMode)
    return
  end
  if os.getenv("MOOQUEST_TESTS")=="1" then
    diagnostic=require("src.test_runner").run()
    -- Automated Windows batch tests must fail with an OS error code, not
    -- only print failing assertions inside an otherwise successful LÖVE run.
    if os.getenv("MOOQUEST_TESTS_EXIT")=="1" then
      love.event.quit(diagnostic.failed>0 and 1 or 0)
    end
    return
  end
  -- Moo IO modification: join the host selected by the invitation launcher.
  local ok,result=pcall(Original.new,{
    host=os.getenv("MOO_IO_HOST") or "127.0.0.1",
    port=tonumber(os.getenv("MOO_IO_PORT")) or 8080,
    server="LC",autoSpawn=false,
    inviteCode=os.getenv("MOO_IO_ROOM_CODE")
  })
  if not ok then
    startupError="Falha ao inicializar cliente de rede: "..tostring(result)
    return
  end
  client=result
  local connected,err=client:connect()
  if not connected then startupError=err end
end

angle=function(y,x)
  if math.atan2 then return math.atan2(y,x) end
  if x>0 then return math.atan(y/x) end
  if x<0 then return math.atan(y/x)+(y>=0 and math.pi or -math.pi) end
  if y>0 then return math.pi/2 end
  if y<0 then return -math.pi/2 end
  return 0
end

function love.update(dt)
  frameDelta=dt
  if integration then integration:update(dt);return end
  if diagnostic or not client then return end
  if uiSmoke then
    uiSmokeTime=uiSmokeTime+dt
    if uiSmokeTime>22 then
      print("UI E2E FAIL: timeout; phase="..tostring(phase)..
        " state="..tostring(client.state).." status="..tostring(client.status))
      love.event.quit(1)
      uiSmoke=false
      return
    end
  end
  client:update()
  for _,evt in ipairs(client:drain()) do
    if evt.kind=="io-init" then
      local h=evt.data
      latestEvent=string.format("io-init REAL: keyed=%d, pinned=%s, sealMode=%d",
        h.mode,tostring(h.pinned),h.sealMode)
    elseif evt.kind=="game_packet" then
      local packet=evt.data
      world:apply(packet.name,packet.args)
      serverPackets=serverPackets+1
      if packet.name=="C" then
        profile:close()
        panels:reset()
        clans:close()
        death:reset()
        phase="playing"
        menu.status=""
        latestEvent="SPAWN CONFIRMADO pelo Node original. SID "..tostring(client.sid)
        movementClock=0
        lastMove=false
        lastAim=nil
        -- The reference client's addPlayer(isYou) snaps the camera on spawn.
        -- Reset smoothing when respawning or entering a new match.
        if camera then camera.hasTarget=false end
        lockDir=false
        mouseAttack=false
        spaceAttack=false
        died=false
      elseif packet.name=="a" and client.sid then
        -- The original server transmits [sid,x,y,dir*100] per visible player.
        local positions=packet.args[1]
        if type(positions)=="table" then
          for i=1,#positions-3,4 do
            if positions[i]==client.sid then
              playerX,playerY=positions[i+1],positions[i+2]
              break
            end
          end
        end
      elseif packet.name=="P" then
        -- No stale profile selection after death; stop the real Node's
        -- watchStats stream instead of just concealing the local overlay.
        if profile:isOpen() then
          profile:close()
          client:send("V",{-1})
        end
        -- Match killPlayer() in the browser: hide the HUD, show "YOU DIED"
        -- over the live world, then reveal the usual Play screen after 3s.
        panels:reset()
        clans:close()
        chatOpen=false;chatDraft=""
        input.keys={};lastMove=false
        mouseAttack=false;spaceAttack=false;lockDir=false
        died=true
        phase="death"
        death:start()
        menu.status=""
        latestEvent="YOU DIED: morte confirmada pelo Node."
      elseif packet.name=="B" then
        latestEvent="Servidor recusou partida: "..tostring(packet.args[1])
      end
    end
  end
  world:update(dt)
  if phase=="death" and death:update(dt) then
    phase="menu"
    menu.status=""
  end
  if phase=="menu" then menu.world:update(dt) end
  -- Use the actual menu click handler, not Original:spawn(), so CI verifies
  -- the user's Play button and the real Node connection together.
  if uiSmoke and phase=="menu" and client.state=="keyed_transport" then
    local authRequired=uiSmokeMode=="account" or uiSmokeMode=="register"
    if authRequired and not uiAuthStarted then
      uiAuthStarted=true
      local loginX=uiSmokeMode=="account" and 870 or 1045
      love.mousepressed(loginX,460,1)
      if not menu.authMode then
        print("UI E2E FAIL: account form did not open")
        love.event.quit(1);uiSmoke=false;return
      end
      love.textinput("ci-ui-"..uiSmokeMode.."@localhost.invalid")
      love.mousepressed(880,493,1)
      if menu.authStep~="code" then
        print("UI E2E FAIL: account email form: "..tostring(menu.authMessage))
        love.event.quit(1);uiSmoke=false;return
      end
      love.textinput("123456")
      love.mousepressed(880,493,1)
      if not menu.accountEmail or not client.authToken then
        print("UI E2E FAIL: account verification: "..tostring(menu.authMessage))
        love.event.quit(1);uiSmoke=false;return
      end
      print("UI E2E: account form submitted through actual UI; rejoining as account")
      return
    end
    if not uiSmokeClicked and
      (not authRequired or uiAuthStarted and menu.accountEmail) then
      uiSmokeClicked=true
      print("UI E2E: clicking actual Play button")
      love.mousepressed(410,488,1)
      if client.state~="joining" then
        print("UI E2E FAIL: Play click did not send M; state="..
          tostring(client.state).." menu status="..tostring(menu.status))
        love.event.quit(1);uiSmoke=false;return
      end
    end
  end
  local localPlayer=world:localPlayer()
  if localPlayer and localPlayer.x and localPlayer.y and camera then
    camera:followReference(localPlayer.visualX or localPlayer.x,
      localPlayer.visualY or localPlayer.y,dt)
  end
  if client.state=="spawn_confirmed" and not died then
    if panels:isOpen() or clans:isOpen() then input.keys={} end
    heartbeatClock=heartbeatClock+dt
    if heartbeatClock>=15 then
      heartbeatClock=0
      client:send("0",{})
    end
    input:update(dt)
    movementClock=movementClock+dt
    if movementClock>=0.07 then
      movementClock=0
      local dx,dy=input.dx,input.dy
      local move=(dx~=0 or dy~=0) and angle(dy,dx) or false
      if move~=lastMove then
        client:send("9",{move==false and Pack.null or move})
        lastMove=move
      end
      local aim=View.localAim(lockDir,currentAttackDir(),lastAim)
      if not lastAim or math.abs(aim-lastAim)>0.02 then
        client:send("D",{aim})
        lastAim=aim
      end
    end
  end
  if client.state=="failed" or client.state=="closed" then
    phase="menu"
    reconnectSeconds=reconnectSeconds+dt
    -- Retry only on explicit R to avoid connection-throttling.
  end
end

local function line(y,text,color)
  if color then love.graphics.setColor(color) else love.graphics.setColor(0.88,0.93,0.89) end
  love.graphics.print(text,36,y)
end

function love.draw()
  love.graphics.clear(0.075,0.11,0.10)
  if integration then
    love.graphics.print("Real Node integration: "..integration.mode,30,30)
    love.graphics.print("State: "..tostring(integration.client.state),30,60)
    integration:draw()
    return
  end
  if diagnostic then
    line(28,"MOO-QUEST | TESTES DO CLIENTE LUA")
    line(66,string.format("Aprovados: %d   Falhas: %d",diagnostic.passed,diagnostic.failed))
    for i,r in ipairs(diagnostic.rows) do
      line(92+i*27,(r.pass and "OK   " or "ERRO ")..r.path,
        r.pass and {0.45,0.86,0.56} or {1,0.55,0.5})
      if not r.pass then
        love.graphics.setColor(1,0.75,0.64)
        love.graphics.printf(tostring(r.error):gsub("%s+"," "):sub(1,125),
          395,92+i*27,850)
      end
    end
    line(585,"Relatorio: "..tostring(diagnostic.reportPath or diagnostic.reportError or "nao gravado"))
    line(626,"ESC: sair")
    return
  end
  local w,h=love.graphics.getDimensions()
  local p=world:localPlayer()
  if phase=="death" then
    -- The original browser keeps the world underneath #diedText
    -- instead of instantly replacing it with the game entry card.
    View.draw(world,camera,frameDelta,{showGrid=menu.grid})
    death:draw(w,h)
    Notices.draw(world,w,h)
    return
  end
  if phase=="menu" then
    View.draw(menu.world,menuCamera,frameDelta,{showGrid=menu.grid})
    local state=client and client.state
    -- A transport failure must take precedence over the last menu hint.
    local status
    if state=="blocked" or state=="failed" or state=="closed" then
      status=client.error or client.status or startupError
    else
      status=menu.status~="" and menu.status or
        (client and (client.error or client.status)) or startupError
    end
    menu:draw(state,status)
    clans:draw(false)
    Notices.draw(world,w,h)
    return
  end
  if client and client.state=="spawn_confirmed" and not died
    and p and p.x and p.y then
    -- Match browser renderPlayers(): the local avatar aims at the cursor
    -- immediately, while the Node remains authoritative for D/F combat.
    View.draw(world,camera,frameDelta,
      {showGrid=menu.grid,
       localAim=View.localAim(lockDir,currentAttackDir(),lastAim)})
    Hud.draw(world,chatOpen,chatDraft,
      chatOpen or panels:isOpen() or clans:isOpen() or profile:isOpen())
    panels:draw(world)
    clans:draw(true)
    Notices.draw(world,w,h)
    profile:draw(world)
    if uiSmoke and uiSmokeClicked and not uiSmokeDrawn then
      uiSmokeDrawn=true
      print("UI E2E PASS: Play click -> original C/D -> graphical View + HUD rendered")
      love.event.quit(0)
    end
    -- When a reference PNG is absent, report the missing local source.
    -- Never substitute a generated image or fabricated gameplay entity.
    local absent,total=Assets.missingSummary(3)
    if total>0 then
      love.graphics.setColor(0,0,0,0.78)
      love.graphics.rectangle("fill",12,12,620,47+18*#absent,4,4)
      love.graphics.setColor(1,0.82,0.62)
      love.graphics.print("Arquivos PNG ausentes ("..total.."):",20,19)
      for i,file in ipairs(absent) do
        love.graphics.print(file,20,20+i*18)
      end
      love.graphics.print("Execute PREPARAR-SERVIDOR.bat",20,23+(#absent+1)*18)
    end
    return
  end
  love.graphics.setColor(0.12,0.18,0.15)
  love.graphics.rectangle("fill",18,18,w-36,h-36,10,10)
  love.graphics.setColor(0.81,0.91,0.80)
  love.graphics.print("MOO-QUEST | CLIENTE LUA / LOVE 2D",36,36,0,1.6)
  love.graphics.setColor(0.28,0.40,0.33)
  love.graphics.rectangle("fill",36,82,w-72,2)
  line(107,"Servidor: motor Node original do al007ex/moomoo-clone (config local adicional)")
  line(144,"Endereco: http://127.0.0.1:8080  |  Jogo: LC  |  Transporte: WebSocket original")
  if startupError then
    love.graphics.setColor(1,0.65,0.46)
    love.graphics.printf(tostring(startupError),36,197,w-72)
  elseif client then
    love.graphics.setColor(0.88,0.90,0.72)
    love.graphics.printf(client.status or "Conectando...",36,197,w-72)
    if client.build then line(257,"Build do servidor: "..tostring(client.build)) end
  end
  line(310,latestEvent)
  line(341,"Pacotes autenticados recebidos do Node: "..tostring(serverPackets))
  if playerX and playerY then
    line(372,("Posicao AUTORITATIVA no servidor: X %d   Y %d"):format(playerX,playerY))
  end
  love.graphics.setColor(1,0.78,0.54)
  if client and client.sid then
    love.graphics.printf("Conexao e spawn confirmados pelo Node. "..
      "Aguardando os primeiros pacotes de posicao e entidades para desenhar a partida. "..
      "O porte visual continua em validacao com o cliente original.",
      36,410,w-72)
  else
    love.graphics.printf("O cliente solicita um ticket guest na API ORIGINAL "..
      "(/api/join), abre o WebSocket e tenta um spawn autenticado. "..
      "A partida ainda NAO foi confirmada: a janela aberta nao prova jogabilidade.",
      36,410,w-72)
  end
  love.graphics.setColor(0.67,0.77,0.71)
  love.graphics.printf("R: tentar novamente/renascer   |   WASD: movimento apos spawn   |   ESC: sair\n"..
    "Motor Node.js original; sem servidor Lua, proxy ou modificacoes nas regras de jogo.",
    36,h-115,w-72)
end

local menuAction
local function requestPlay()
  if not client then
    menu.status=startupError or "Cliente de rede indisponivel."
    return false
  end
  if phase=="death" or
    (client.state~="keyed_transport" and
    not (died and client.state=="spawn_confirmed")) then
    menu.status=client.state=="joining"
      and "Play enviado; aguardando confirmacao C do servidor..."
      or "Aguardando conexao com Node. Estado: "..tostring(client.state)
    return false
  end
  local ok,why=client:spawn({name=menu.name,skin=menu.skin})
  if not ok then
    menu.status="Falha ao entrar: "..tostring(why)
    return false
  end
  died=false
  menu.status="Entrando na partida; aguardando confirmacao do Node..."
  return true
end
local function accountAction(action)
  if action=="auth_request" then
    local flow,err=Auth.requestCode(menu.authEmail)
    if not flow then
      menu.authMessage=err;return
    end
    menu.authFlow=flow.flow
    menu.authStep="code"
    menu.authCode=""
    menu.authFocus="code"
    menu.authMessage="Este servidor local aceita QUALQUER codigo de 6 digitos. Nao ha envio de email."
    return
  elseif action=="auth_verify" then
    local account,err=Auth.verifyCode(menu.authFlow,menu.authCode)
    if not account then menu.authMessage=err;return end
    if not client then menu.authMessage="Cliente Node indisponivel";return end
    client.authToken=account.token
    clans:reset()
    menu.accountEmail=menu.authEmail
    menu.authMode=nil
    menu.authFlow=nil
    menu.authCode=""
    menu.authMessage=""
    menu.status="Conta local conectada. Reabrindo sessao de jogo..."
    -- The original API issues account-bound join tickets. The old guest
    -- WebSocket cannot be retroactively converted to a registered session.
    world=World.new()
    local ok,why=client:connect()
    if not ok then menu.status="Falha ao conectar conta: "..tostring(why) end
    return
  elseif action=="auth_logout" then
    if not client then return end
    client.authToken=nil
    clans:reset()
    menu.accountEmail=nil
    menu.status="Conta local desconectada. Reabrindo como convidado..."
    world=World.new()
    local ok,why=client:connect()
    if not ok then menu.status="Falha na conexao guest: "..tostring(why) end
  end
end
menuAction=function(action)
  if action=="play" then return requestPlay() end
  if action=="play_unavailable" then
    menu.status="Jogo indisponivel; confira o status do servidor e os Detalhes."
    return false
  end
  if action=="auth_request" or action=="auth_verify" or
    action=="auth_logout" then
    accountAction(action)
    return true
  end
  if action=="clan_open" then
    clans:toggle(client and client.authToken)
    return true
  end
  if action=="auth_open" or action=="auth_back" then
    menu.status=""
  end
  return false
end

-- The profile is read-only: both opening and closing use Node V packets.
-- A local modal NEVER gives the client authority to create account stats.
local function closeProfile()
  if not profile:isOpen() then return end
  profile:close()
  if client and client.state=="spawn_confirmed" then
    client:send("V",{-1})
  end
end
local function openProfile(sid)
  if type(sid)~="number" or sid<0 or sid%1~=0
    or not client or client.state~="spawn_confirmed" then return false end
  local ok,err=client:send("V",{sid})
  if not ok then
    latestEvent="Perfil indisponivel: "..tostring(err)
    return false
  end
  profile:open(sid)
  panels:close()
  clans:close()
  chatOpen=false;chatDraft=""
  input.keys={};lastMove=false
  mouseAttack=false;spaceAttack=false
  client:send("e",{})
  client:send("F",{0,Pack.null})
  return true
end

function love.keypressed(key)
  if phase=="death" then return end
  if profile:isOpen() then
    if key=="escape" or key=="p" then closeProfile() end
    return
  end
  if clans:isOpen() then
    clans:keypressed(key)
    return
  end
  if key=="escape" and phase=="playing" and panels:isOpen() then
    panels:keypressed(key,world)
    return
  end
  if key=="escape" then
    if phase=="menu" and menu.authMode then
      menuAction(menu:keypressed(key));return
    end
    if chatOpen then chatOpen=false;chatDraft="";return end
    love.event.quit();return
  end
  if diagnostic then return end
  if phase=="menu" then
    if key=="r" and died and not menu:isEditingText() and client
      and client.state=="spawn_confirmed" then
      requestPlay()
      return
    end
    if key=="r" and not menu:isEditingText() and client and
      (client.state=="failed" or client.state=="closed"
        or client.state=="blocked") then
      world=World.new()
      local ok,why=client:connect()
      if not ok then menu.status=tostring(why) end
      return
    end
    -- Input must see the live WebSocket state even before the next draw.
    menu.connectionState=client and client.state or "failed"
    local action=menu:keypressed(key)
    menuAction(action)
    return
  end
  if chatOpen then
    if key=="return" or key=="kpenter" then
      local value=shortenChat(chatDraft)
      if #value>0 and client then client:send("6",{value}) end
      chatDraft="";chatOpen=false
    elseif key=="backspace" then
      chatDraft=backspaceUtf8(chatDraft)
    end
    return
  end
  -- The original browser closes or traps focus in the Store/Tribe
  -- overlay. Enter must NEVER create a chat box behind an open modal.
  if panels:isOpen() then
    panels:keypressed(key,world)
    return
  end
  if (key=="return" or key=="kpenter") and client
    and client.state=="spawn_confirmed" and not died then
    chatOpen=true;chatDraft=""
    input.keys={}
    lastMove=false
    -- A player can open chat while holding mouse/Space. Stop the ongoing
    -- attack on the real Node server before giving keyboard focus to chat,
    -- exactly as store/tribe and window focus loss already do.
    mouseAttack=false;spaceAttack=false
    client:send("e",{})
    client:send("F",{0,Pack.null})
    return
  end
  input:keypressed(key)
  -- Mirror the reference client's default gameplay bindings.
  if client and client.state=="spawn_confirmed" and not died then
    if key=="p" and world.sid then
      openProfile(world.sid)
      return
    end
    if key=="e" then client:send("K",{1});return end
    if key=="x" then
      local ok=client:send("K",{0})
      if ok then lockDir=not lockDir end
      return
    end
    if key=="r" then client:send("S",{1});return end
    if key=="c" then
      local p=world:localPlayer()
      if p and p.x and p.y then world.mapMarker={x=p.x,y=p.y} end
      return
    end
    if key=="q" and world.inventory.items[1]~=nil then
      client:send("z",{world.inventory.items[1],false});return
    end
    if key:match("^[1-9]$") then
      local index,isWeapon=Hud.slotForKey(world,key)
      if index~=nil then client:send("z",{index,isWeapon}) end
      return
    end
    if key=="space" and not spaceAttack then
      spaceAttack=true
      if not mouseAttack then client:send("F",{1,currentAttackDir()}) end
      return
    end
  end
  if key=="r" and client then
    if died and client.state=="spawn_confirmed" then
      local ok,reason=client:send("M",{
        Pack.map({name=client.name,moofoll=false,skin=0,anon=false})
      })
      if ok then latestEvent="Renascimento solicitado ao servidor Node original..."
      else latestEvent="Falha no renascimento: "..tostring(reason) end
      return
    end
    if client.state=="spawn_confirmed" then return end
    if client.state~="closed" and client.state~="failed" then return end
    reconnectSeconds=0
    startupError=nil
    playerX,playerY=nil,nil
    serverPackets=0
    lastMove=false
    lastAim=nil
    lockDir=false
    mouseAttack=false
    spaceAttack=false
    died=false
    heartbeatClock=0
    world=World.new()
    if camera then camera.hasTarget=false end
    local ok,err=client:connect()
    if not ok then startupError=err end
  end
end
function love.textinput(text)
  if phase=="death" then return end
  if clans:isOpen() then clans:textinput(text);return end
  if phase=="menu" then menu:textinput(text);return end
  if panels:isOpen() then panels:textinput(text);return end
  if chatOpen and type(text)=="string" then
    chatDraft=shortenChat(chatDraft..text)
  end
end
function love.keyreleased(key)
  if phase=="death" then return end
  if not diagnostic then input:keyreleased(key) end
  if key=="space" and spaceAttack then
    spaceAttack=false
    if not mouseAttack and client and client.state=="spawn_confirmed" then
      client:send("F",{0,Pack.null})
    end
  end
end
function love.focus(focused)
  if not focused and client and client.state=="spawn_confirmed" then
    client:send("e",{})
    client:send("F",{0,Pack.null})
    mouseAttack=false;spaceAttack=false
    input.keys={}
    lastMove=false
  end
end
function love.mousepressed(x,y,button)
  if diagnostic or phase=="death" then return end
  if phase=="menu" then
    if button==1 then
      local width,height=love.graphics.getDimensions()
      if clans:isOpen() and clans:click(x,y,width,height,false,client and client.authToken) then return end
      menu.connectionState=client and client.state or "failed"
      local action=menu:click(x,y,width,height)
      menuAction(action)
    end
    return
  end
  if not client or client.state~="spawn_confirmed" or died then return end
  if button==1 then
    local w,h=love.graphics.getDimensions()
    if profile:isOpen() then
      local consumed,closed=profile:click(x,y,w,h)
      if closed then client:send("V",{-1}) end
      if consumed then return end
    end
    if clans:click(x,y,w,h,true,client and client.authToken) then
      if clans:isOpen() and panels:isOpen() then panels:close() end
      -- Keep the permanent Clan window exclusive with Shop and Tribe,
      -- matching how the original client hides competing overlays.
      -- The account overlay must not cause attacks or movement while typing.
      input.keys={};lastMove=false
      chatOpen=false;chatDraft=""
      mouseAttack=false;spaceAttack=false
      client:send("e",{})
      client:send("F",{0,Pack.null})
      return
    end
    local action=panels:click(world,x,y,w,h)
    if action then
      if action.packet then
        local ok,err=client:send(action.packet,action.args or {})
        if not ok then
          panels.message=tostring(err)
        elseif action.consumeRequest then
          -- This consumes only the displayed notification after a
          -- successful send, never a server-owned team or membership.
          table.remove(world.joinRequests,1)
        end
      else
        -- Reference toggleStoreMenu/toggleAllianceMenu close chat and
        -- stop gathering while the menu takes keyboard/mouse focus.
        chatOpen=false;chatDraft=""
        if panels:isOpen() then
          input.keys={}
          lastMove=false
          mouseAttack=false;spaceAttack=false
          client:send("e",{})
          client:send("F",{0,Pack.null})
        end
      end
      return
    end
    if panels:isOpen() then return end
    if chatOpen then return end
    local profileSid=Hud.leaderboardHitTest(world,w,x,y)
    if profileSid~=nil then
      openProfile(profileSid)
      return
    end
    if Hud.mapHitTest(w,h,x,y) then
      client:send("S",{1})
      return
    end
    local upgradeIndex=Upgrades.hitTest(world,w,x,y)
    if upgradeIndex~=nil then
      client:send("H",{upgradeIndex})
      return
    end
    local itemIndex,isWeapon=Hud.hitTest(world,w,h,x,y)
    if itemIndex~=nil then
      client:send("z",{itemIndex,isWeapon})
      return
    end
    if not mouseAttack then
      mouseAttack=true
      if not spaceAttack then client:send("F",{1,currentAttackDir()}) end
    end
  end
end
-- Browser storeDisplay uses mouseover/mouseout for live item details.
-- Only presentation changes; no purchase, equip or Node packet on hover.
function love.mousemoved(x,y)
  if phase=="playing" and panels:isOpen() and love.graphics then
    local w,h=love.graphics.getDimensions()
    panels:hover(x,y,w,h)
  end
end
function love.wheelmoved(dx,dy)
  if clans:isOpen() then clans:wheelmoved(dx,dy);return end
  if phase=="playing" then panels:wheelmoved(dx,dy,world) end
end
function love.mousereleased(_,_,button)
  if diagnostic or not client or client.state~="spawn_confirmed" then return end
  if button==1 and mouseAttack then
    mouseAttack=false
    if not spaceAttack then client:send("F",{0,Pack.null}) end
  end
end
function love.quit()
  if client then client:close() end
end

function love.resize(w,h)
  if camera then camera:resize(w,h) end
  if menuCamera then menuCamera:resize(w,h) end
end
