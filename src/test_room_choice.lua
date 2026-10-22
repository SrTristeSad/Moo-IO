-- Real main.lua navigation contract, with server launching stubbed out.
-- A click on Jogar must never create a server nor connect to one.
return function(perform,home,hosted,getClient)
  assert(home.screen=="home" and hosted.state=="idle")
  local starts=0
  hosted.start=function(self,mode)
    starts=starts+1
    self.state="starting"
    return true
  end
  hosted.update=function() end
  assert(home:click(110,298)=="play_tab")
  perform("play_tab")
  assert(home.screen=="play","Jogar should open the choices screen")
  assert(starts==0 and not home.starting and not home.hosting,
    "Jogar created a room automatically")
  assert(getClient()==nil,"Jogar entered a server without approval")
  assert(home:click(174,409)=="create",
    "Create room must be a separate explicit button")
  perform("create")
  assert(starts==1 and home.starting and not home.hosting,
    "Create room must start only after user selection")
  assert(getClient()==nil,"Creating a room must not automatically enter it")
  hosted.state="ready"
  hosted.hostIP="192.168.1.20"
  hosted.address="192.168.1.20:8080"
  hosted.code="test-code"
  love.update(0.016)
  assert(home.hosting and not home.starting,
    "Room should be ready for the user to choose JOGAR AGORA")
  assert(getClient()==nil,"Ready room auto-entered against user selection")
  home.screen="home"
  perform("play_tab")
  assert(starts==1 and getClient()==nil,
    "Returning to Jogar auto-connected to a hosted room")
  assert(home:click(180,505)=="play_local",
    "JOGAR AGORA must remain a separate explicit button")
  print("MOO IO ROOM CHOICE PASS: manual hosting and joining, no autojoin")
end
