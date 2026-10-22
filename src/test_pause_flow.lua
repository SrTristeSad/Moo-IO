-- End-to-end input routing through the actual main.lua callbacks.
-- No real server is created. Destroying a hosted map requires a click on YES.
return function(pause,hosted,home,setPhase,getPhase,getClient,setClient,
    setOwner,getOwner,homeAction)
  assert(not pause:isOpen())
  home.screen="home"
  love.draw() -- The title screen renders the reference world behind menus.
  local sends,closes,stops=0,0,0
  local function client()
    return {
      state="spawn_confirmed",
      send=function() sends=sends+1;return true end,
      close=function() closes=closes+1 end
    }
  end
  setClient(client())
  setPhase()
  setOwner(false)
  love.keypressed("escape")
  assert(pause:isOpen() and pause.page=="root","ESC must open in-game options")
  assert(getClient()~=nil and getPhase()=="playing",
    "ESC must not disconnect the current guest")
  assert(sends>=2,"Opening pause must stop movement/attack")
  love.draw() -- Paused menu renders on top of the world, without crashing.
  love.mousepressed(620,347,1)
  assert(pause.page=="settings","Settings button must be clickable")
  local grid=home.showGrid
  love.mousepressed(620,275,1)
  assert(home.showGrid~=grid,"Grid toggle must work inside the match")
  love.keypressed("escape")
  assert(pause.page=="root","ESC from settings must go back")
  love.keypressed("escape")
  assert(not pause:isOpen() and getClient()~=nil,
    "ESC from pause must resume, not close network")
  love.keypressed("escape")
  love.mousepressed(620,410,1)
  assert(not pause:isOpen() and getClient()==nil and getPhase()=="menu",
    "Guest exits only their own client")
  assert(stops==0 and closes==1,"Guest must not destroy host server")
  hosted.state="ready"
  hosted.stop=function(self)
    stops=stops+1
    self.state="idle"
  end
  home.hosting=true
  homeAction("stop") -- Exit from main menu while owning a room.
  assert(pause.page=="confirm" and stops==0,
    "Owner's main menu stop must require confirmation")
  love.mousepressed(753,430,1) -- Cancel, retain server.
  assert(stops==0 and hosted.state=="ready" and pause.page=="root",
    "Cancel must leave the private server alive")
  pause:close()
  setClient(client())
  setOwner(true)
  setPhase()
  love.keypressed("escape")
  assert(getOwner() and pause.owner and pause.page=="root",
    "Host ESC must open the owner's pause controls")
  love.mousepressed(620,409,1)
  assert(pause.page=="confirm" and stops==0,
    "Host leaving needs confirmation, must not stop automatically")
  love.keypressed("escape")
  assert(pause.page=="root" and stops==0,
    "ESC cancels host confirmation")
  love.mousepressed(620,409,1)
  love.mousepressed(521,429,1) -- Confirm owned server termination.
  assert(stops==1 and hosted.state=="idle" and getClient()==nil,
    "Only confirmation can terminate the host's room")
  assert(getPhase()=="menu","Confirmation should show the title menu")
  hosted.state="ready"
  setClient(client())
  setPhase()
  setOwner(true)
  assert(love.quit()==true,"Window X must be intercepted while hosting")
  assert(stops==1 and pause.page=="confirm" and pause.confirmQuit,
    "Window close must ask before disconnecting friends")
  love.mousepressed(750,430,1)
  assert(stops==1 and hosted.state=="ready","Cancel window close must retain room")
  pause:close()
  hosted.state="idle"
  setClient(nil)
  print("MOO IO PAUSE PASS: ESC options, live menu, guest exit, host confirmation")
end
