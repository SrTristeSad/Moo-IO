-- SPDX-License-Identifier: AGPL-3.0-only
-- Headless UI smoke test; no connection to backend, no bots.
return function()
  local Home=require("src.game.mooio_home")
  love.window.setMode(1280,720,{resizable=false})
  local home=Home.new()
  assert(home.screen=="home")
  local Paths=require("src.net.mooio_paths")
  local realRoot,pathError=Paths.find(love.filesystem)
  assert(realRoot,pathError or "Diretorio do Moo IO nao encontrado")
  local source=love.filesystem.getSource()
  assert(realRoot==source or realRoot==love.filesystem.getSourceBaseDirectory(),
    "Scripts encontrados em pasta inesperada")
  assert(Paths.script(realRoot):find("scripts/start%-server%.ps1")~=nil)
  assert(home:click(110,298)=="play_tab","Jogar must open personal room")
  assert(home.screen=="play")
  assert(not home.starting and not home.hosting,"JOGAR only displays room options")
  assert(not home.botsEnabled,"Bots cannot turn on automatically")
  assert(home:click(174,443)=="bots_toggle")
  assert(home.botsEnabled and home.botCount==2)
  assert(home:click(552,488)=="bots_count")
  assert(home.botCount==3)
  assert(home:click(199,493)=="bots_count")
  assert(home.botCount==2)
  assert(home:click(174,553)=="create","LAN room must have a create action")
  assert(home:click(169,330)=="mode_lan")
  assert(home:click(412,330)=="mode_vpn")
  assert(home.serverMode=="vpn")
  assert(home:click(172,548)=="create","VPN room must remain accessible in Jogar")
  home.hosting=true;home.hostAddress="192.168.1.7:8080";home.hostCode="abcd1234567890"
  assert(home:roomInvite()=="192.168.1.7:8080/abcd1234567890")
  assert(home:click(175,440)=="copy","host must have invitation sharing")
  assert(home:click(180,505)=="play_local","host must be able to play")
  assert(home:click(409,505)=="stop","host must be able to close the room")
  home.hosting=false
  assert(home:click(716,306)=="focus")
  home:textinput("100.80.12.34:8080")
  assert(home.invite=="100.80.12.34:8080")
  assert(home:click(715,385)=="focus")
  home:textinput("some-secret-code")
  assert(home:click(721,452)=="join","IP join button must work")
  local full,err=Home.parseInvite(home.invite,home.joinCode)
  assert(full and full.host=="100.80.12.34" and full.port==8080 and full.code=="some-secret-code", "invite="..tostring(home.invite).." code="..tostring(home.joinCode).." result="..tostring(full and full.host).." reason="..tostring(err))
  local direct=assert(Home.parseInvite("192.168.0.12:8080/abcdefgh"))
  assert(direct.host=="192.168.0.12")
  assert(Home.parseInvite("8.8.8.8:8080/abcdefgh")==nil,"public IP not authorized")
  home.roomOverlay=true
  assert(home:overlayClick(600,412)=="copy","Invite overlay must copy")
  assert(home:overlayClick(902,191)=="close_overlay","overlay must close")
  assert(home:click(1121,110)=="back")
  assert(home:click(110,386)=="server_tab")
  assert(home:click(745,309)=="provider_firebase")
  assert(home.provider=="firebase")
  assert(home:click(212,300)=="provider_lite")
  assert(home.provider=="lite")
  assert(home:click(460,548)=="server_to_play")
  assert(home.screen=="play")
  assert(home:click(1121,110)=="back")
  assert(home:click(140,460)=="settings_tab")
  assert(home:click(453,253)=="grid")
  assert(home.showGrid==false)
  assert(home:click(445,325)=="fullscreen")
  local oldScale=home.hudScale
assert(home:click(830,418)=="hud_changed" and home.hudScale>oldScale)
assert(home:click(379,418)=="hud_changed" and home.hudScale==oldScale)
local oldOpacity=home.hudOpacity
assert(home:click(384,489)=="hud_changed" and home.hudOpacity<oldOpacity)
assert(home:click(821,489)=="hud_changed" and home.hudOpacity==oldOpacity)
assert(home:click(619,560)=="hud_changed" and home.hudScale==1.20)
assert(home:click(450,600)==nil,
    "Invitations belong on the ESC pause root, not in Settings")
  assert(home:keypressed("f2")==nil,
    "F2 is no longer a shortcut to copy invitation")
  -- Render each page to an offscreen canvas to catch graphical/layout crashes.
  local canvas=love.graphics.newCanvas(1280,720)
  love.graphics.setCanvas(canvas)
  for _,page in ipairs({"home","play","server","settings"}) do
    home.screen=page
    home:draw("idle","")
  end
  home.screen="play"
  home.roomOverlay=true
  home:draw("idle","")
  home:drawRoomOverlay()
  home.roomOverlay=false
  love.graphics.setCanvas()
  canvas:release()
  print("MOO IO MENU PASS: sala/IP/convite em configuracoes, sem F2 nem Clan")
end
