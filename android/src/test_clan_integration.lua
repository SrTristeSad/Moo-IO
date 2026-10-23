-- Exercise the real permanent-clan Lua controls against running local Node.
-- Called only by MOOQUEST_INTEGRATION=persistent_clan.
return function(self)
  local panel=self.clans
  local w,h=1280,720
  if not self.stage then
    panel:open(self.client.authToken)
    if panel.accountName=="" then
      local x,y=panel:geometry(w,h)
      panel:click(x+63,y+200,w,h,false)
      panel:textinput("UI"..self.suffix)
      panel:click(x+420,y+200,w,h,false)
    end
    if panel.accountName~="UI"..self.suffix then
      return self:stop(false,
        "Node did not register a permanent name: "..tostring(panel.message))
    end
    panel:selectTab("create")
    local x,y=panel:geometry(w,h)
    panel:click(x+52,y+195,w,h,false)
    panel:textinput("K"..self.suffix:sub(1,3))
    panel:click(x+423,y+195,w,h,false)
    if not panel:clan() then
      return self:stop(false,
        "Node did not confirm permanent clan: "..tostring(panel.message))
    end
    self.stage="owned"
    print("E2E CLAN: authentic account name and permanent clan confirmed")
  elseif self.stage=="owned" then
    if not panel:selectTab("manage") then
      return self:stop(false,"Manage tab not available")
    end
    local x,y,_,height=panel:geometry(w,h)
    panel:click(x+390,y+height-96,w,h,false)
    if not panel.confirmDisband or not panel:clan() then
      return self:stop(false,"Disband requires two clicks")
    end
    panel:click(x+390,y+height-96,w,h,false)
    if panel:clan() then
      return self:stop(false,
        "Node did not confirm clan disband: "..tostring(panel.message))
    end
    return self:stop(true,
      "native account Clan UI claimed name, created and disbanded permanent clan")
  end
end
