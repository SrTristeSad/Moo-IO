-- Navigation and room bot option contract (no actual Node process).
return function(perform,home,hosted,getClient)
  assert(home.screen=="home" and hosted.state=="idle")
  local starts,lastCount=0,-1
  hosted.start=function(self,mode,ip,bots)
    starts=starts+1
    lastCount=bots
    self.state="starting"
    return true
  end
  hosted.update=function() end
  assert(home:click(110,298)=="play_tab")
  perform("play_tab")
  assert(home.screen=="play" and starts==0 and not home.hosting)
  assert(not home.botsEnabled,"Bots must be off by default")
  assert(home:click(172,439)=="bots_toggle")
  assert(home.botsEnabled and home.botCount==2)
  assert(home:click(550,491)=="bots_count")
  assert(home.botCount==3)
  assert(home:click(210,491)=="bots_count")
  assert(home.botCount==2)
  assert(home:click(180,553)=="create")
  perform("create")
  assert(starts==1 and lastCount==2 and home.starting,
    "Only the explicit Create button may launch two server bots")
  assert(getClient()==nil,"Room creation cannot auto-join")
  hosted.state="ready"
  hosted.hostIP="192.168.1.20"
  hosted.address="192.168.1.20:8080"
  hosted.code="test-code"
  love.update(0.016)
  assert(home.hosting and not home.starting)
  assert(getClient()==nil,"Ready room cannot auto-enter")
  home.screen="home"
  perform("play_tab")
  assert(starts==1 and getClient()==nil,"Jogar may not start another room")
  assert(home:click(180,505)=="play_local")
  print("MOO IO ROOM CHOICE PASS: explicit hosting, bot count, no autojoin")
end
