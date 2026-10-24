-- Moo-Quest is a Lua client for the UNMODIFIED al007ex/moomoo-clone server.
-- Real native gameplay rendering is gated by actual server C/D/a/H/I packets.
-- Never generate local entities or claim spawn before the Node server confirms it.
local Original=require("src.net.original_client")
local World=require("src.game.world_state")
local View=require("src.game.reference_view")
local Menu=require("src.game.reference_menu")
local Home=require("src.game.mooio_home")
local Pause=require("src.game.mooio_pause")
local Host=require("src.net.mooio_host")
local Auth=require("src.net.local_auth")
local Config=require("src.game.config")
local Hud=require("src.game.reference_hud")
local Panels=require("src.game.reference_panels")
local Clans=require("src.game.account_clans")
local Death=require("src.game.reference_death")
local Notices=require("src.game.reference_notices")
local Profile=require("src.game.reference_profile")
local Upgrades=require("src.game.reference_upgrades")
local Abilities=require("src.mobile.ability_actions")
local Assets=require("src.game.reference_assets")
local Camera=require("src.camera")
local Input=require("src.input")
local Pack=require("src.protocol.msgpack")
local Mobile=require("src.mobile.controls")
local isAndroid=love.system and love.system.getOS and love.system.getOS()=="Android" or os.getenv("MOO_IO_FORCE_ANDROID_E2E")=="1"
local mobile=isAndroid and Mobile.new() or nil
local mobileAttackSent=false
local mobileAimSentAt=-math.huge
local mobileForwardMouse=false
local mobileInteractLeft=0
local mobileBuilding=0
local mobileWeapon=0
local client=nil
local integration=nil
local uiSmokeMode=os.getenv("MOO_IO_E2E") or os.getenv("MOOQUEST_UI_E2E")
local uiSmoke=uiSmokeMode~=nil and #uiSmokeMode>0
local uiAuthStarted=false
local uiSmokeTime=0
local uiSmokeClicked=false
local uiSmokeDrawn=false
local world=World.new()
local camera=nil
local menuCamera=nil
local menuPreview=nil
local previewW,previewH=0,0
local previewAge=2
local menu=Menu.new()
local home=Home.new()
local hosted=Host.new()
local function saveHudSettings()
  if mobile then mobile:configure(home.hudScale,home.hudOpacity,
    home.moveScale,home.fireScale,home.deadzone) end
  if love.filesystem then
    love.filesystem.write("mooio-hud-v1.cfg",
      string.format("%.2f %.2f %.2f %.2f %.2f",
        home.hudScale,home.hudOpacity,home.moveScale,home.fireScale,home.deadzone))
  end
end
local function loadHudSettings()
  if love.filesystem then
    local content=love.filesystem.read("mooio-hud-v1.cfg")
    if type(content)=="string" then
      local values={}
      for number in content:gmatch("%d+%.?%d*") do
        values[#values+1]=tonumber(number)
      end
      if #values>=2 then
        home.hudScale=math.max(.85,math.min(1.55,values[1]))
        home.hudOpacity=math.max(.50,math.min(1,values[2]))
      end
      if #values>=5 then
        home.moveScale=math.max(.75,math.min(1.50,values[3]))
        home.fireScale=math.max(.75,math.min(1.50,values[4]))
        home.deadzone=math.max(.05,math.min(.30,values[5]))
      end
    end
  end
  if mobile then mobile:configure(home.hudScale,home.hudOpacity,
    home.moveScale,home.fireScale,home.deadzone) end
end
local pause=Pause.new()
local sessionIsHost=false
local allowQuit=false
local joinRequested=false
local connectRoom
local homeAction
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
local mobileAbilitySentAt=nil
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
  if mobile then return mobile:aimAngle() end
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
  loadHudSettings()
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
  if os.getenv("MOO_IO_ROOM_CHOICE_TEST")=="1" then
    local ok,err=pcall(function()
      require("src.test_room_choice")(homeAction,home,hosted,
        function() return client end)
    end)
    if not ok then print("MOO IO ROOM CHOICE FAIL: "..tostring(err)) end
    allowQuit=true -- mocked owner must not block an automated test exit
    love.event.quit(ok and 0 or 1)
    return
  end
  if os.getenv("MOO_IO_MENU_TEST")=="1" then
    local ok,err=pcall(function() require("src.test_mooio_menu")() end)
    if not ok then print("MOO IO MENU FAIL: "..tostring(err)) end
    love.event.quit(ok and 0 or 1)
    return
  end
  if os.getenv("MOO_IO_PAUSE_TEST")=="1" then
    local ok,err=pcall(function()
      require("src.test_pause_flow")(pause,hosted,home,
        function() phase="playing" end,
        function() return phase end,
        function() return client end,
        function(value) client=value end,
        function(value) sessionIsHost=value end,
        function() return sessionIsHost end,
        homeAction)
    end)
    if not ok then print("MOO IO PAUSE FAIL: "..tostring(err)) end
    allowQuit=true -- test already verified the window-close confirmation
    love.event.quit(ok and 0 or 1)
    return
  end
  if os.getenv("MOO_IO_HUD_TEST")=="1" then
    local ok,err=pcall(function() require("src.test_missing_asset_ui")() end)
    if not ok then print("MOO IO HUD FAIL: "..tostring(err)) end
    love.event.quit(ok and 0 or 1)
    return
  end
  if os.getenv("MOO_IO_SPRITE_TEST")=="1" then
    local ok,err=pcall(function() require("src.test_sprite_render")() end)
    if not ok then print("MOO IO SPRITES FAIL: "..tostring(err)) end
    love.event.quit(ok and 0 or 1)
    return
  end
  -- Normal opening: stay on Moo IO home; no network or terminal is opened.
  -- CI may inject an invitation to prove that the native Play flow reaches C.
  if os.getenv("MOO_IO_E2E")=="1" then
    local remoteHost=os.getenv("MOO_IO_HOST") or "127.0.0.1"
    local remotePort=tonumber(os.getenv("MOO_IO_PORT")) or 8080
    local inviteCode=os.getenv("MOO_IO_ROOM_CODE")
    local ok,result=pcall(Original.new,{host=remoteHost,port=remotePort,
      server="LC",autoSpawn=false,inviteCode=inviteCode})
    if not ok then error("Moo IO test init: "..tostring(result)) end
    client=result
    joinRequested=true
    home.screen="play"
    local connected,err=client:connect()
    if not connected then error("Moo IO test connect: "..tostring(err)) end
  end
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
  -- Network ticks keep full dt; interpolation stays stable after a slow frame.
  frameDelta=math.min(dt,0.05)
  if integration then integration:update(dt);return end
  if diagnostic then return end
  -- The menu backdrop reuses the original top-down world preview even
  -- before connecting to a Node server.
  if phase=="menu" then
    menu.world:update(dt)
    previewAge=previewAge+dt
  end
  hosted:update(dt)
  if home.starting or hosted.state=="failed" then home.serverLog=hosted.lastLog end
  if home.starting and hosted.state=="starting"
    and hosted.progress~="" and home.status~=hosted.progress then
    home:setStatus(hosted.progress)
  end
  if home.starting and hosted.state=="ready" then
    home.starting=false;home.hosting=true
    home.hostAddress=hosted.address;home.hostCode=hosted.code
    home:setStatus("Sala criada. Convide amigos pelo menu ESC.")
  elseif home.starting and hosted.state=="failed" then
    home.starting=false;home.hosting=false
    home:setStatus(hosted.error or "Nao foi possivel iniciar o servidor.",true)
  end
  if not client then return end
  if joinRequested and client.state=="keyed_transport" then
    joinRequested=false
    local ok,err=client:spawn({name=home.nickname,skin=menu.skin})
    if ok then
      uiSmokeClicked=true
      home:setStatus("Entrando no mundo; aguardando o servidor...")
    else home:setStatus("Falha ao entrar: "..tostring(err),true) end
  end
  if (client.state=="failed" or client.state=="blocked" or client.state=="closed")
    and not home.error then
    joinRequested=false
    home:setStatus(client.error or client.status or "Conexao encerrada.",true)
  end
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
        home:setStatus("Partida iniciada.")
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
        if mobile then mobile:reset();mobileAttackSent=false;mobileInteractLeft=0 end
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
  -- Use the actual menu click handler, not Original:spawn(), so CI verifies
  -- the user's Play button and the real Node connection together.
  -- The Moo IO E2E uses the same automatic spawn path as normal players.
  -- No simulated menu click or fake C packet is allowed.
  local localPlayer=world:localPlayer()
  if localPlayer and localPlayer.x and localPlayer.y and camera then
    camera:followReference(localPlayer.visualX or localPlayer.x,
      localPlayer.visualY or localPlayer.y,dt)
  end
  -- The multiplayer server must still receive keepalive packets while
  -- ESC options are open. Only player movement and attacks are suspended.
  if client.state=="spawn_confirmed" and not died then
    heartbeatClock=heartbeatClock+dt
    if heartbeatClock>=15 then
      heartbeatClock=0
      client:send("0",{})
    end
  end
  if mobile and mobile.rankOpen and client.state=="spawn_confirmed" and not died then
    mobile.rankRefresh=mobile.rankRefresh-dt
    if mobile.rankRefresh<=0 then
      client:send("Y",{mobile.rankingCategory})
      mobile.rankRefresh=3
    end
  end
  if client.state=="spawn_confirmed" and not died and not pause:isOpen() then
    if panels:isOpen() or clans:isOpen() then input.keys={} end
    input:update(dt)
    if mobile then
      input.dx,input.dy=mobile:movement()
      if mobileInteractLeft>0 then
        mobileInteractLeft=mobileInteractLeft-dt
        if mobileInteractLeft<=0 and not mobile:attacking() then
          client:send("F",{0,Pack.null})
          mobileAttackSent=false
        end
      end
    end
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
      -- Node K(0) prevents rotation while locked. Do not flood it with
      -- direction packets, and keep our rendered facing fixed as well.
      if not lockDir and (not lastAim or math.abs(aim-lastAim)>0.02) then
        local ok=client:send("D",{aim})
        if ok then lastAim=aim end
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
    line(28,"MOO IO | TESTES DO CLIENTE LUA")
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
    -- The background is the original MooMoo world scene, not a static
    -- fake screenshot or a generated entity pretending to be online.
    -- Reuse a cached view of the familiar top-down game world on the title
    -- screen. Rendering all procedural foliage every frame slowed the menu,
    -- particularly on software-rendered or lower-end Windows machines.
    -- Rebuild once per second or immediately on resize/grid changes.
    if not menuPreview or previewW~=w or previewH~=h or previewAge>=(mobile and 4 or 1) then
      if menuPreview and (previewW~=w or previewH~=h) then
        menuPreview:release()
        menuPreview=nil
      end
      if not menuPreview then
        local factor=mobile and .60 or 1
        menuPreview=love.graphics.newCanvas(math.max(1,math.floor(w*factor)),
          math.max(1,math.floor(h*factor)))
        previewW,previewH=w,h
      end
      love.graphics.push("all")
      love.graphics.setCanvas(menuPreview)
      love.graphics.clear(0,0,0,0)
      love.graphics.scale(menuPreview:getWidth()/w,menuPreview:getHeight()/h)
      View.draw(menu.world,menuCamera,frameDelta,{showGrid=menu.grid})
      love.graphics.pop()
      previewAge=0
    end
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(menuPreview,0,0,0,w/menuPreview:getWidth(),h/menuPreview:getHeight())
    local state=client and client.state or "idle"
    home:draw(state,client and (client.error or client.status) or "",true)
    if home.roomOverlay then home:drawRoomOverlay() end
    if pause:isOpen() then pause:draw(home.showGrid,home.fullscreen,home:roomInvite(),home.hudScale,home.hudOpacity) end
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
    panels:draw(world,not mobile)
    if mobile and not pause:isOpen() and not panels:isOpen()
      and not clans:isOpen() and not profile:isOpen() then
      if chatOpen then
        mobile:drawChat(chatDraft)
      else
        mobile:draw(world,Config.mapScale)
      end
    end
    -- Permanent clans are accessible via the dedicated Android CLAN icon.
    clans:draw(false)
    Notices.draw(world,w,h)
    profile:draw(world)
    -- Invite controls are in ESC > CONFIGURACOES, not on the HUD.
    if uiSmoke and uiSmokeClicked and not uiSmokeDrawn then
      uiSmokeDrawn=true
      print("MOO IO E2E PASS: convite -> handshake -> C/D -> mundo e HUD renderizados")
      love.event.quit(0)
    end
    if pause:isOpen() then
      pause:draw(home.showGrid,home.fullscreen,home:roomInvite(),home.hudScale,home.hudOpacity)
      return
    end
    -- Only show missing PNG diagnostics on explicit developer opt-in.
    if os.getenv("MOO_IO_DEBUG_ASSETS")=="1" then
      local absent,total=Assets.missingSummary(3)
      if total>0 then
        love.graphics.push("all")
        love.graphics.setColor(0,0,0,0.88)
        love.graphics.rectangle("fill",16,58,590,34+19*#absent,5,5)
        love.graphics.setColor(1,0.83,0.63)
        love.graphics.print("PNG ausentes: "..total,24,64)
        for i,file in ipairs(absent) do
          love.graphics.print(file,24,64+i*19)
        end
        love.graphics.pop()
      end
    end
    return
  end
  -- Awaiting first authoritative world state (no fake player/entities).
  love.graphics.setColor(0.06,0.11,0.12)
  love.graphics.rectangle("fill",0,0,w,h)
  love.graphics.setColor(0.90,0.95,0.91)
  love.graphics.printf("MOO IO",0,h/2-72,w,"center")
  love.graphics.setColor(0.56,0.78,0.62)
  love.graphics.printf("Carregando mundo e jogadores...",0,h/2-20,w,"center")
  love.graphics.setColor(0.68,0.75,0.73)
  love.graphics.printf(client and client.status or "Aguardando servidor...",40,h/2+26,w-80,"center")
  if pause:isOpen() then pause:draw(home.showGrid,home.fullscreen,home:roomInvite(),home.hudScale,home.hudOpacity) end
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

-- Native menu actions. Only one authoritative Node session exists at a time.
connectRoom=function(ip,port,inviteCode)
  if client then client:close();client=nil end
  world=World.new()
  local ok,connection=pcall(Original.new,{
    host=ip,port=port,server="LC",inviteCode=inviteCode,autoSpawn=false
  })
  if not ok then
    home:setStatus("Cliente de rede: "..tostring(connection),true)
    return false
  end
  client=connection
  sessionIsHost=hosted.state=="ready"
    and ip==hosted.hostIP and inviteCode==hosted.code
  menu.name=home.nickname
  joinRequested=true
  home.screen="play"
  home:setStatus("Conectando a "..ip..":"..port.."...")
  local connected,err=client:connect()
  if not connected then
    joinRequested=false
    home:setStatus("Falha de conexao: "..tostring(err),true)
  end
  return connected
end

homeAction=function(action)
  if action=="play_tab" then
    -- Navigating to JOGAR cannot launch a server or join a room.
    -- Both operations require their own explicit button.
    home.screen="play"
    if hosted.state=="ready" then
      home:setStatus("Sala pronta. Clique JOGAR AGORA se quiser entrar.")
    elseif hosted.state=="starting" then
      home:setStatus("Preparando a sala que voce escolheu criar...")
    else
      home:setStatus("Escolha CRIAR MINHA SALA ou ENTRAR EM OUTRA SALA.")
    end
  elseif action=="server_to_play" then
    home.screen="play"
    home:setStatus("Entre usando IP, porta e codigo fornecidos pelo anfitriao.")
  elseif action=="provider_lite" then
    home:setStatus("V2 Lite: requer um servidor dedicado e compatibilidade de protocolo.")
  elseif action=="provider_firebase" then
    home:setStatus("Firebase: login e busca de salas dependem da configuracao do projeto.")
  elseif action=="back" then
    home:setStatus("")
  elseif action=="create" then
    -- The only path that can create a private server is an explicit click.
    if home.screen~="play" or home.starting or home.hosting then return end
    if client then client:close();client=nil end
    home:setStatus("Iniciando servidor local sem terminal...")
    local ok,err=hosted:start(home.serverMode,home.vpnIP,
      home.botsEnabled and home.botCount or 0)
    if ok then
      home.starting=true;home.hosting=false
      home.hostCode="";home.hostAddress=""
    else
      home.starting=false
      home:setStatus(tostring(err),true)
    end
  elseif action=="mode_lan" or action=="mode_vpn" then
    home:setStatus(home.serverMode=="vpn"
      and "Abra sua VPN com os amigos e informe o IP virtual deste computador."
      or "Modo LAN: amigos conectados ao mesmo roteador.")
  elseif action=="join" then
    local target,why=Home.parseInvite(home.invite,home.joinCode)
    if not target then home:setStatus(why,true);return end
    connectRoom(target.host,target.port,target.code)
  elseif action=="play_local" then
    if hosted.state=="ready" then
      connectRoom(hosted.hostIP,hosted.port,hosted.code)
    else home:setStatus("A sala ainda nao esta pronta.",true) end
  elseif action=="stop" then
    if isAndroid then
      -- Stop Node's isolated Android service NOW, even if the game stays open.
      if client then client:close();client=nil end
      local stopped,stopError=hosted:stop()
      if not stopped then
        home:setStatus(stopError or "Nao foi possivel encerrar a hospedagem.",true)
        return
      end
      home.hosting=false;home.starting=false
      home.hostAddress="";home.hostCode=""
      home:setStatus("Sala encerrada. Servidor desligado; memoria liberada.")
      return
    end
    -- Even from the main menu, the owner must confirm disconnecting
    -- everybody before the host process can be stopped.
    if hosted.state=="ready" or hosted.state=="starting" then
      pause:confirm(true,false)
    end
  elseif action=="retry" then
    if hosted.state=="ready" and (home.invite=="" or home.invite==home:roomInvite()) then
      connectRoom(hosted.hostIP,hosted.port,hosted.code)
    else
      local target,why=Home.parseInvite(home.invite,home.joinCode)
      if target then connectRoom(target.host,target.port,target.code)
      else home:setStatus(why,true) end
    end
  elseif action=="copy" then
    local link=home:roomInvite()
    if link~="" then
      love.system.setClipboardText(link)
      home:setStatus("Convite copiado para a area de transferencia.")
    end
  elseif action=="grid" then
    menu.grid=home.showGrid
    previewAge=2
    home:setStatus(home.showGrid and "Grade ativada." or "Grade desativada.")
  elseif action=="fullscreen" then
    local ok,err=love.window.setFullscreen(home.fullscreen)
    if not ok then home:setStatus(tostring(err),true) end
  elseif action=="hud_changed" then
    saveHudSettings()
    home:setStatus("HUD atualizado. Tamanho e opacidade salvos no aparelho.")
  end
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
  if mobile then mobile:stopForOverlay();mobileAttackSent=false end
  panels:close()
  clans:close()
  chatOpen=false;chatDraft=""
  input.keys={};lastMove=false
  mouseAttack=false;spaceAttack=false
  client:send("e",{})
  client:send("F",{0,Pack.null})
  return true
end

-- One gate for leaving a live match or terminating an owned room.
-- Choosing cancel/ESC from the confirmation never touches host:stop().
local function stopGameplay(owned)
  pause:close()
  if client then client:close();client=nil end
  joinRequested=false
  sessionIsHost=false
  home.roomOverlay=false
  if owned then
    hosted:stop()
    home.hosting=false;home.starting=false
    home.hostAddress="";home.hostCode=""
  end
  input.keys={};lastMove=false
  mouseAttack=false;spaceAttack=false
  if mobile then mobile:reset();mobileAttackSent=false;mobileInteractLeft=0 end
  chatOpen=false;chatDraft=""
  panels:reset();clans:close();profile:close()
  phase="menu";died=false
  home.screen="play"
  home:setStatus(owned and "Sala encerrada. Servidor desligado; participantes desconectados."
    or "Voce saiu da partida. A sala do anfitriao continua online.")
end
local function stopPlayerControls()
  -- Opening pause/options suspends held pointers, not server auto-attack.
  if mobile then mobile:stopForOverlay();mobileAttackSent=false;mobileInteractLeft=0 end
  input.keys={}
  lastMove=false
  mouseAttack=false;spaceAttack=false
  chatOpen=false;chatDraft=""
  if client and client.state=="spawn_confirmed" then
    -- Stop server-authoritative movement as well as gathering/attacking.
    -- Otherwise the last key direction may keep moving the avatar on ESC.
    client:send("9",{Pack.null})
    client:send("e",{})
    client:send("F",{0,Pack.null})
  end
end
local function pauseAction(action)
  if action=="toggle_grid" then
    home.showGrid=not home.showGrid
    menu.grid=home.showGrid
    previewAge=2
  elseif action=="toggle_fullscreen" then
    home.fullscreen=not home.fullscreen
    local ok,err=love.window.setFullscreen(home.fullscreen)
    if not ok then home.fullscreen=not home.fullscreen;home:setStatus(tostring(err),true) end
  elseif action=="hud_smaller" or action=="hud_bigger"
    or action=="opacity_less" or action=="opacity_more" then
    if action=="hud_smaller" then home.hudScale=math.max(.85,home.hudScale-.10)
    elseif action=="hud_bigger" then home.hudScale=math.min(1.55,home.hudScale+.10)
    elseif action=="opacity_less" then home.hudOpacity=math.max(.50,home.hudOpacity-.10)
    elseif action=="opacity_more" then home.hudOpacity=math.min(1,home.hudOpacity+.10) end
    home.hudScale=math.floor(home.hudScale*100+.5)/100
    home.hudOpacity=math.floor(home.hudOpacity*100+.5)/100
    saveHudSettings()
  elseif action=="copy_invite" then
    local invite=home:roomInvite()
    if pause.owner and hosted.state=="ready" and invite~="" then
      love.system.setClipboardText(invite)
      home:setStatus("Convite copiado para enviar aos amigos.")
    end
  elseif action=="leave_guest" then
    stopGameplay(false)
  elseif action=="leave_owner" or action=="quit_owner" then
    stopGameplay(true)
    if action=="quit_owner" then
      allowQuit=true
      love.event.quit()
    end
  end
end
function love.keypressed(key)
  if pause:isOpen() then
    pauseAction(pause:keypressed(key))
    return
  end
  if home.roomOverlay then
    if key=="escape" then home.roomOverlay=false end
    return
  end

  -- Android Back/Escape while typing must close chat, NOT pause the game.
  if phase=="playing" and chatOpen and key=="escape" then
    chatOpen=false;chatDraft=""
    if mobile and love.keyboard then love.keyboard.setTextInput(false) end
    return
  end
  if phase=="playing" and key=="escape" then
    stopPlayerControls()
    panels:close();clans:close()
    if profile:isOpen() then closeProfile() end
    home.roomOverlay=false
    pause:open(sessionIsHost)
    return
  end
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
  if diagnostic then return end
  if phase=="menu" then
    homeAction(home:keypressed(key))
    return
  end
  if chatOpen then
    if key=="return" or key=="kpenter" then
      local value=shortenChat(chatDraft)
      if #value>0 and client then client:send("6",{value}) end
      chatDraft="";chatOpen=false
      if mobile and love.keyboard then love.keyboard.setTextInput(false) end
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
    if mobile then
      mobile:stopForOverlay();mobileAttackSent=false
      if love.keyboard and love.keyboard.setTextInput then
        local w,h=love.graphics.getDimensions()
        love.keyboard.setTextInput(true,math.floor(w*.22),math.floor(h*.27),
          math.floor(w*.53),math.floor(h*.10))
      end
    end
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
    if key=="e" then
      local ok=client:send("K",{1})
      if ok and mobile then mobile.auto=not mobile.auto end
      return
    end
    if key=="x" then
      -- Lock exactly the last authoritative facing, even if the last
      -- short Android aim movement has not reached the normal network tick.
      if not lockDir then
        local dir=currentAttackDir()
        local sent=client:send("D",{dir})
        if not sent then return end
        lastAim=dir
      end
      local ok=client:send("K",{0})
      if ok then
        lockDir=not lockDir
        if mobile then mobile:setDirectionLock(lockDir) end
        if not lockDir then
          local dir=currentAttackDir()
          local updated=client:send("D",{dir})
          if updated then lastAim=dir end
        end
      end
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
  if phase=="menu" then home:textinput(text);return end
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
    if mobile then mobile:stopForOverlay();mobileAttackSent=false end
    client:send("e",{})
    client:send("F",{0,Pack.null})
    mouseAttack=false;spaceAttack=false
    input.keys={}
    lastMove=false
  end
end
function love.mousepressed(x,y,button)
  if isAndroid and not mobileForwardMouse then return end
  if pause:isOpen() then
    if button==1 then pauseAction(pause:click(x,y)) end
    return
  end
  if home.roomOverlay then
    if button==1 and home:overlayClick(x,y)=="copy" then
      local link=home:roomInvite()
      if link~="" then love.system.setClipboardText(link) end
      home:setStatus("Convite copiado para enviar aos amigos.")
    end
    return
  end
  if diagnostic or phase=="death" then return end
  if phase=="menu" then
    if button==1 then homeAction(home:click(x,y)) end
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
    if clans:click(x,y,w,h,false,client and client.authToken) then
      if mobile then mobile:stopForOverlay();mobileAttackSent=false end
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
          if mobile then mobile:stopForOverlay();mobileAttackSent=false end
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
  if pause:isOpen() then return end
  if phase=="playing" and panels:isOpen() and love.graphics then
    local w,h=love.graphics.getDimensions()
    panels:hover(x,y,w,h)
  end
end
function love.wheelmoved(dx,dy)
  if pause:isOpen() then return end
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
local function mobileStop()
  if client and client.state=="spawn_confirmed" then
    client:send("9",{Pack.null})
    client:send("e",{})
    client:send("F",{0,Pack.null})
  end
  mobileAttackSent=false
  mobileInteractLeft=0
  lastMove=false
end
local function mobileSelect(kind,slot)
  if not client or client.state~="spawn_confirmed" then return end
  local inv=world and world.inventory
  local entries=inv and inv[kind]
  if not entries or #entries==0 then return end
  slot=math.floor(slot)
  if slot<1 or slot>#entries then return end
  local id=entries[slot]
  if type(id)=="number" then
    local ok,err=client:send("z",{id,kind=="weapons"})
    if not ok then latestEvent="Equipamento nao enviado: "..tostring(err) end
  end
end
local function mobileAction(action,payload)
  if action=="top_toggle" then return end
  if action=="pause" then love.keypressed("escape");return end
  if action=="shop_open" or action=="clan_open" or action=="tribe_open" then
    mobileStop()
    if client and client.state=="spawn_confirmed" then
      chatOpen=false;chatDraft="";input.keys={}
      if action=="shop_open" then
        clans:close();panels:toggle("store")
      elseif action=="tribe_open" then
        clans:close();panels:toggle("tribe")
      else
        panels:close();clans:toggle(client.authToken)
      end
    end
    return
  end
  if action=="map_open" or action=="chat_open" or action=="rank_open" then
    mobileStop()
    -- Never toggle K here: auto-gather is a persistent SERVER mode.
    -- F(0) above only releases the manual attack state.
    if action=="rank_open" and client and client.state=="spawn_confirmed" then
      client:send("Y",{payload or mobile.rankingCategory})
      mobile.rankRefresh=3
    elseif action=="chat_open" then
      chatOpen=true;chatDraft=""
      input.keys={}
      local w,h=love.graphics.getDimensions()
      if love.keyboard and love.keyboard.setTextInput then
        love.keyboard.setTextInput(true,math.floor(w*.22),math.floor(h*.27),
          math.floor(w*.53),math.floor(h*.10))
      end
    end
    return
  end
  if not client or client.state~="spawn_confirmed" then return end
  if action=="rank_category" then
    mobile.rankRefresh=3
    client:send("Y",{payload})
  elseif action=="ping_here" then
    client:send("S",{1}) -- Same real team ping as keyboard R on Windows
  elseif action=="lock_aim" then
    -- Use the EXACT existing MooMoo.io K(0) lock toggle (Windows X).
    -- This freezes direction only, not movement, attack or AUTO.
    if not lockDir then
      local dir=currentAttackDir()
      local sent,sendErr=client:send("D",{dir})
      if not sent then
        latestEvent="Nao foi possivel fixar a mira: "..tostring(sendErr)
        return
      end
      lastAim=dir
    end
    local ok,err=client:send("K",{0})
    if ok then
      lockDir=not lockDir
      mobile:setDirectionLock(lockDir)
      if not lockDir then
        local dir=currentAttackDir()
        local updated=client:send("D",{dir})
        if updated then lastAim=dir end
      end
    else
      latestEvent="Trava de mira indisponivel: "..tostring(err)
    end
  elseif action=="server_auto" then
    local ok,err=client:send("K",{1}) -- Same toggle as E on Windows
    if not ok then
      mobile.auto=not mobile.auto
      latestEvent="Ataque automatico indisponivel: "..tostring(err)
    end
  elseif action=="skill" or action=="slot" then
    -- The bottom row is a set of real ACTIONS, not a paginated inventory.
    -- A touch selects weapons; food and structures execute using the
    -- authoritative Node z/F protocol. Do not change the AUTO K toggle.
    local now=love.timer.getTime()
    if not mobileAbilitySentAt or now-mobileAbilitySentAt>=.17 then
      mobileAbilitySentAt=now
      local ok,why=Abilities.activate(world,payload,currentAttackDir(),
        function(packet,args) return client:send(packet,args) end,
        Pack.null,mobile:attacking())
      if ok then
        mobile:abilityFeedback(payload,now)
      else
        latestEvent="Habilidade nao executada: "..tostring(why)
      end
    end
  elseif action=="attack" then
    local active=mobile:attacking()
    if active~=mobileAttackSent then
      local ok=client:send("F",{active and 1 or 0,
        active and currentAttackDir() or Pack.null})
      if ok then mobileAttackSent=active end
    end
  elseif action=="ping" and payload then
    local ok,err=client:send("U",{payload.x,payload.y})
    if ok then world.mapMarker={x=payload.x,y=payload.y}
    else latestEvent="Marcacao indisponivel: "..tostring(err) end
  end
end
local function mobileMouse(x,y)
  mobileForwardMouse=true
  love.mousepressed(x,y,1)
  mobileForwardMouse=false
  if phase=="playing" then love.mousereleased(x,y,1) end
  if isAndroid and love.keyboard and love.keyboard.setTextInput then
    love.keyboard.setTextInput(phase=="menu" and home.focus~=nil)
  end
end
function love.touchpressed(id,x,y)
  if not mobile then return end
  if chatOpen and phase=="playing" and not pause:isOpen() then
    local w,h=love.graphics.getDimensions()
    local l=mobile:layout(w,h)
    if x>=l.chatSend.x and x<=l.chatSend.x+l.chatSend.w
      and y>=l.chatSend.y and y<=l.chatSend.y+l.chatSend.h then
      love.keypressed("return")
    elseif x>=l.chatCancel.x and x<=l.chatCancel.x+l.chatCancel.w
      and y>=l.chatCancel.y and y<=l.chatCancel.y+l.chatCancel.h then
      love.keypressed("escape")
    elseif love.keyboard and love.keyboard.setTextInput then
      love.keyboard.setTextInput(true,math.floor(w*.22),math.floor(h*.27),
        math.floor(w*.53),math.floor(h*.10))
    end
    return
  end
  if phase~="playing" or pause:isOpen() or home.roomOverlay
    or panels:isOpen() or clans:isOpen() or profile:isOpen() then
    mobileMouse(x,y)
    return
  end
  local w,h=love.graphics.getDimensions()
  if not (mobile.mapOpen or mobile.rankOpen)
    and Upgrades.hitTest(world,w,x,y) then
    mobileMouse(x,y)
    return
  end
  local action,payload=mobile:pressed(id,x,y,w,h,Config.mapScale,require("src.mobile.slots").total(world))
  if action then mobileAction(action,payload) end
end
function love.touchmoved(id,x,y)
  if not mobile or phase~="playing" or pause:isOpen() then return end
  local w,h=love.graphics.getDimensions()
  local action,attackChanged=mobile:moved(id,x,y,w,h)
  -- The same thumb has TWO zones: short drag = aim only, outer drag =
  -- aim + manual attack. DIRECTION must update even during aim-only.
  -- On a threshold transition, send the latest D before F(1)/F(0)
  -- instead of waiting for the usual 70-ms player update.
  if action=="aim" and not chatOpen and client
    and client.state=="spawn_confirmed" then
    local now=love.timer.getTime()
    if not lockDir and (attackChanged or now-mobileAimSentAt>=.04) then
      local dir=currentAttackDir()
      if not lastAim or math.abs(dir-lastAim)>.02 then
        local ok=client:send("D",{dir})
        if ok then lastAim=dir end
      end
      mobileAimSentAt=now
    end
    if attackChanged then
      -- Only crossing the attack threshold sends F: simply aiming NEVER
      -- fires, and moving inward stops fire without disabling server AUTO.
      mobileAction("attack")
    end
  end
end
function love.touchreleased(id)
  if not mobile then return end
  local action,payload=mobile:released(id)
  if action then mobileAction(action,payload) end
end
function love.quit()
  if not allowQuit and (hosted.state=="ready" or hosted.state=="starting") then
    -- The window close button must not silently terminate an owner's map.
    stopPlayerControls()
    home.roomOverlay=false
    pause:confirm(true,true)
    return true -- cancel OS close; show confirmation in existing window
  end
  if client then client:close() end
  if hosted then hosted:stop() end
end

function love.resize(w,h)
  previewAge=2
  if camera then camera:resize(w,h) end
  if menuCamera then menuCamera:resize(w,h) end
end
