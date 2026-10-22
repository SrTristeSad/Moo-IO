-- Permanent account clans (NOT in-game temporary Tribe alliances).
-- Data and all mutations come from the bundled Node's /api/name + /api/clan/*
-- This UI deliberately does not invent clan membership or simulate purchases.
-- Requires the LOCAL test account, whose authentication is not production-safe.
local Auth=require("src.net.local_auth")
local C={}
C.__index=C
local function trim(s) return (s or ""):match("^%s*(.-)%s*$") or "" end
local function inside(x,y,a,b,w,h)
  return x>=a and x<a+w and y>=b and y<b+h
end
function C.new(options)
  return setmetatable({
    api=options and options.api or Auth,
    opened=false,token=nil,accountName=nil,mine=nil,
    tab="create",field="clan",inputs={name="",clan="",target=""},
    selectedMember=nil,confirmDisband=false,confirmTransfer=nil,
    scroll=0,message="",lastError=nil
  },C)
end
function C:reset()
  self.opened=false;self.token=nil;self.accountName=nil;self.mine=nil
  self.tab="create";self.field="clan";self.inputs={name="",clan="",target=""}
  self.scroll=0;self.message="";self.lastError=nil
  self.confirmDisband=false;self.confirmTransfer=nil
end
function C:buttonRect(w)
  return w-461,22,59,58
end
function C:geometry(w,h)
  local width=590
  local height=math.min(558,h-58)
  return math.floor((w-width)/2),math.floor((h-height)/2),width,height
end
function C:isOpen() return self.opened end
function C:open(token)
  self.opened=true;self.token=token
  self.tab="create";self.scroll=0;self.field="clan"
  self.confirmDisband=false;self.confirmTransfer=nil
  self.message="";self.lastError=nil
  return self:refresh()
end
function C:close()
  self.opened=false;self.confirmDisband=false;self.confirmTransfer=nil
  self.inputs.name="";self.inputs.target=""
end
function C:toggle(token)
  if self.opened then self:close();return true end
  return self:open(token)
end
function C:refresh()
  if not self.token then
    self.mine=nil;self.accountName=nil
    self.message="Entre ou cadastre uma conta local no menu inicial."
    return false
  end
  local account,err=self.api.getAccount(self.token)
  if not account then
    self.mine=nil;self.accountName=nil;self.lastError=err
    self.message="Nao foi possivel consultar a conta: "..tostring(err)
    return false
  end
  self.accountName=type(account.name)=="string" and account.name or ""
  if self.accountName=="" then
    self.mine=nil
    self.field="name"
    self.message="Escolha o nome permanente da conta (3 a 15 caracteres)."
    return false
  end
  local mine,reason=self.api.clanMine(self.token)
  if not mine then
    self.mine=nil;self.lastError=reason
    self.message="Nao foi possivel consultar o cla: "..tostring(reason)
    return false
  end
  self.mine=mine;self.lastError=nil
  local clan=self:clan()
  local valid=false
  for _,item in ipairs(self:tabs()) do
    if item.id==self.tab then valid=true;break end
  end
  if not valid then self.tab=clan and "members" or "create" end
  self.scroll=0
  return true
end
function C:clan()
  local c=self.mine and self.mine.clan
  return type(c)=="table" and type(c.name)=="string" and c or nil
end
function C:role()
  return self.mine and self.mine.role or nil
end
function C:leader()
  return self:role()=="owner"
end
function C:officer()
  return self:role()=="owner" or self:role()=="officer"
end
function C:tabs()
  if not self.token or not self.accountName or self.accountName=="" then
    return {}
  elseif self:clan() then
    return {{id="members",label="Membros"},{id="requests",label="Pedidos"},
      {id="manage",label="Administrar"}}
  else
    return {{id="create",label="Criar"},{id="find",label="Solicitar"},
      {id="invites",label="Convites"}}
  end
end
function C:selectTab(id)
  for _,t in ipairs(self:tabs()) do
    if t.id==id then
      self.tab=id;self.scroll=0;self.message=""
      self.confirmDisband=false;self.confirmTransfer=nil
      self.field=id=="manage" and "target" or "clan"
      return true
    end
  end
  return false
end
function C:rows()
  local clan=self:clan()
  if clan then
    if self.tab=="members" then return clan.members or {} end
    if self.tab=="requests" then
      return self:officer() and (self.mine.requests or {}) or {}
    end
  elseif self.tab=="invites" then
    return self.mine and self.mine.invites or {}
  end
  return {}
end
function C:run(action,data)
  if not self.token then self.message="Entre na conta antes de usar o cla.";return false end
  if not self.accountName or self.accountName=="" then
    self.message="Registre o nome permanente primeiro.";return false
  end
  local result,err=self.api.clanAction(self.token,action,data or {})
  if not result then self.lastError=err;self.message=tostring(err);return false end
  self.lastError=nil
  self:refresh()
  if self.lastError then return false end
  -- Player.clanTag is captured by Node on WebSocket join; an existing
  -- in-game session must rejoin before it receives the new permanent tag.
  local membershipChanged=action=="create" or action=="leave" or
    action=="disband" or (action=="answer" and data and data.accept)
  self.message=membershipChanged
    and "Cla salvo no Node. Reentre na partida para atualizar a tag."
    or "Operacao confirmada pelo servidor Node."
  self.confirmDisband=false;self.confirmTransfer=nil
  return true
end
function C:claim()
  local name=trim(self.inputs.name)
  if #name<3 or #name>15 then
    self.message="Nome permanente: de 3 a 15 caracteres.";return false
  end
  local confirmed,err=self.api.claimName(self.token,name)
  if not confirmed then self.message=tostring(err);return false end
  self.accountName=confirmed
  self.inputs.name=""
  self:refresh()
  self.message="Nome registrado: "..confirmed..". Aparece na proxima entrada na partida."
  return true
end
function C:create()
  local tag=trim(self.inputs.clan)
  if not tag:match("^[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]?$") then
    self.message="A sigla do cla deve ter 3 ou 4 letras/numeros."
    return false
  end
  return self:run("create",{name=tag})
end
function C:request()
  local tag=trim(self.inputs.clan)
  if not tag:match("^[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]?$") then
    self.message="Digite a sigla do cla (3 ou 4 caracteres)."
    return false
  end
  local result=self:run("request",{clan=tag})
  if result then self.message="Solicitacao enviada ao cla "..tag.."." end
  return result
end
function C:invite()
  local name=trim(self.inputs.target)
  if name=="" then self.message="Informe o nome do jogador.";return false end
  local ok=self:run("invite",{name=name})
  if ok then self.inputs.target="" end
  return ok
end
function C:answerInvite(tag,accept)
  if type(tag)~="string" or #tag==0 then return false end
  return self:run("answer",{clan=tag,accept=not not accept})
end
function C:decide(name,accept)
  if not self:officer() or type(name)~="string" then return false end
  return self:run("decide",{name=name,accept=not not accept})
end
function C:kick(name)
  if not self:officer() or type(name)~="string" then return false end
  if name==self.accountName then return false end
  return self:run("kick",{name=name})
end
function C:changeRole(name,newRole)
  if not self:leader() or type(name)~="string" then return false end
  if newRole~="member" and newRole~="officer" and newRole~="owner" then
    return false
  end
  -- Ownership transfer requires a second confirmation.
  if newRole=="owner" and self.confirmTransfer~=name then
    self.confirmTransfer=name
    self.message="Confirme novamente para transferir a lideranca a "..name.."."
    return false
  end
  return self:run("role",{name=name,role=newRole})
end
function C:toggleRequests()
  if not self:leader() then return false end
  return self:run("requests",{open=self:clan().closed==true})
end
function C:leave()
  if not self:clan() then return false end
  return self:run("leave",{})
end
function C:disband()
  if not self:leader() then return false end
  if not self.confirmDisband then
    self.confirmDisband=true
    self.message="Clique novamente para EXCLUIR o cla permanentemente."
    return false
  end
  return self:run("disband",{})
end
function C:textinput(s)
  if not self.opened or not self.token or type(s)~="string" then return false end
  local field=self.field
  if field~="name" and field~="clan" and field~="target" then return false end
  local limit=(field=="clan" and 4) or 15
  for i=1,#s do
    local ch=s:sub(i,i)
    -- Clan tags: [A-Za-z0-9] 3-4. Account names follow the
    -- original Node help text: letters, digits and _ : ( ) / ? -.
    local allowed=field=="clan" and ch:match("^[A-Za-z0-9]$")
      or (ch:match("^[A-Za-z0-9_:%(%)%/%?%-]$") or ch==" ")
    if allowed and #self.inputs[field]<limit then
      self.inputs[field]=self.inputs[field]..ch
    end
  end
  return true
end
function C:keypressed(key)
  if not self.opened then return false end
  if key=="escape" then self:close();return true end
  if key=="backspace" and self.inputs[self.field] then
    self.inputs[self.field]=self.inputs[self.field]:sub(1,-2);return true
  end
  if key=="up" then self.scroll=math.max(0,self.scroll-1);return true end
  if key=="down" then self.scroll=math.min(math.max(0,#self:rows()-5),self.scroll+1);return true end
  if key=="return" or key=="kpenter" then
    if not self.accountName or self.accountName=="" then self:claim()
    elseif not self:clan() and self.tab=="create" then self:create()
    elseif not self:clan() and self.tab=="find" then self:request()
    elseif self:clan() and self.tab=="manage" then self:invite()
    end
    return true
  end
  return true
end
function C:wheelmoved(_,dy)
  if not self.opened then return false end
  self.scroll=math.max(0,math.min(math.max(0,#self:rows()-5),
    self.scroll-math.floor(dy or 0)))
  return true
end
function C:click(x,y,w,h,hasGameplayButton,token)
  if type(x)~="number" or type(y)~="number" then return false end
  if hasGameplayButton then
    local bx,by,bw,bh=self:buttonRect(w)
    if inside(x,y,bx,by,bw,bh) then self:toggle(token);return true end
  end
  if not self.opened then return false end
  local px,py,pw,ph=self:geometry(w,h)
  if not inside(x,y,px,py,pw,ph) then self:close();return true end
  if inside(x,y,px+pw-50,py+13,34,34) then self:close();return true end
  if not self.token then return true end
  if not self.accountName or self.accountName=="" then
    if inside(x,y,px+40,py+184,345,49) then self.field="name";return true end
    if inside(x,y,px+402,py+184,145,49) then self:claim();return true end
    return true
  end
  for i,tab in ipairs(self:tabs()) do
    if inside(x,y,px+24+(i-1)*181,py+75,175,42) then
      self:selectTab(tab.id);return true
    end
  end
  local clan=self:clan()
  if not clan then
    if self.tab=="create" or self.tab=="find" then
      if inside(x,y,px+26,py+180,348,48) then
        self.field="clan";return true
      end
      if inside(x,y,px+393,py+180,163,48) then
        if self.tab=="create" then self:create() else self:request() end
        return true
      end
    elseif self.tab=="invites" then
      for i=1,math.min(5,#self:rows()-self.scroll) do
        local invite=self:rows()[i+self.scroll]
        local row=py+150+(i-1)*59
        if inside(x,y,px+368,row+10,79,36) then
          self:answerInvite(invite.clan,true);return true
        end
        if inside(x,y,px+465,row+10,88,36) then
          self:answerInvite(invite.clan,false);return true
        end
      end
    end
  elseif self.tab=="members" then
    for i=1,math.min(5,#self:rows()-self.scroll) do
      local member=self:rows()[self.scroll+i]
      local ry=py+154+(i-1)*58
      if member and member.name~=self.accountName then
        if self:officer() and inside(x,y,px+469,ry+8,92,38) then
          self:kick(member.name);return true
        end
        if self:leader() and inside(x,y,px+354,ry+8,108,38) then
          if member.role=="member" then
            self:changeRole(member.name,"officer")
          elseif member.role=="officer" then
            self:changeRole(member.name,"owner")
          end
          return true
        end
      end
    end
  elseif self.tab=="requests" then
    for i=1,math.min(5,#self:rows()-self.scroll) do
      local player=self:rows()[i+self.scroll]
      local ry=py+154+(i-1)*59
      if self:officer() then
        if inside(x,y,px+369,ry+8,80,38) then
          self:decide(player,true);return true
        end
        if inside(x,y,px+467,ry+8,90,38) then
          self:decide(player,false);return true
        end
      end
    end
  elseif self.tab=="manage" then
    if self:officer() then
      if inside(x,y,px+26,py+181,352,46) then
        self.field="target";return true
      end
      if inside(x,y,px+394,py+181,163,46) then
        self:invite();return true
      end
    end
    if self:leader() and inside(x,y,px+30,py+255,252,45) then
      self:toggleRequests();return true
    end
    if inside(x,y,px+30,py+ph-117,250,47) then
      self:leave();return true
    end
    if self:leader() and inside(x,y,px+308,py+ph-117,251,47) then
      self:disband();return true
    end
  end
  return true
end
-- Only love.draw depends on graphics; controller unit tests run headlessly.
local fonts={}
local function font(size)
  if not fonts[size] then fonts[size]=love.graphics.newFont(size) end
  love.graphics.setFont(fonts[size])
end
local function color(r,g,b,a) love.graphics.setColor(r,g,b,a or 1) end
local function rect(x,y,w,h,r,g,b,a)
  color(r,g,b,a or 1);love.graphics.rectangle("fill",x,y,w,h,5,5)
end
local function text(s,x,y,size,alpha)
  font(size or 17);color(1,1,1,alpha or 1)
  love.graphics.print(tostring(s),x,y)
end
local function centered(s,x,y,w,size)
  font(size or 17);color(1,1,1)
  love.graphics.printf(tostring(s),x,y,w,"center")
end
local function button(label,x,y,w,h,selected)
  rect(x,y,w,h,selected and 0.49 or 0.25,selected and 0.84 or 0.28,
    selected and 0.31 or 0.30,0.92)
  centered(label,x,y+(h-18)/2,w,16)
end
local function input(value,x,y,w,h,active,hint)
  rect(x,y,w,h,0.04,0.05,0.06,0.85)
  text((value~="" and value or hint)..(active and "|" or ""),x+14,y+12,18,
    value=="" and 0.65 or 1)
end
local function tabTitle(id)
  return tostring(id or ""):upper()
end
function C:draw(showGameplayButton)
  local w,h=love.graphics.getDimensions()
  if showGameplayButton then
    local bx,by,bw,bh=self:buttonRect(w)
    button("Clan",bx,by,bw,bh,self.opened)
  end
  if not self.opened then return end
  local px,py,pw,ph=self:geometry(w,h)
  rect(0,0,w,h,0,0,0,0.40)
  rect(px,py,pw,ph,0.10,0.13,0.14,0.96)
  text("CLANS - CONTA PERMANENTE",px+25,py+20,23)
  button("X",px+pw-50,py+13,34,34,false)
  if not self.token then
    centered("Entre ou cadastre uma conta no menu inicial",
      px+30,py+168,pw-60,20)
    centered("As tribos temporarias continuam separadas dos clas.",
      px+30,py+207,pw-60,15)
    return
  end
  if not self.accountName or self.accountName=="" then
    text("Escolha um nome de conta para poder criar ou entrar em clas.",
      px+28,py+109,16)
    input(self.inputs.name,px+40,py+184,345,49,self.field=="name",
      "Nome permanente (3 a 15)")
    button("Salvar nome",px+402,py+184,145,49,true)
  else
    text("Conta: "..self.accountName,px+29,py+55,16,0.9)
    local clan=self:clan()
    if clan then
      text("Cla: "..clan.name.."   |   Cargo: "..tostring(self:role()),
        px+275,py+55,16,0.9)
    end
    for i,t in ipairs(self:tabs()) do
      button(t.label,px+24+(i-1)*181,py+75,175,42,self.tab==t.id)
    end
    if not clan then
      if self.tab=="create" or self.tab=="find" then
        local isCreate=self.tab=="create"
        text(isCreate and "Criar um cla permanente" or
          "Solicitar entrada em um cla",px+27,py+142,21)
        input(self.inputs.clan,px+26,py+180,348,48,
          self.field=="clan","Sigla 3-4 caracteres")
        button(isCreate and "Criar cla" or "Solicitar",
          px+393,py+180,163,48,true)
        text(isCreate and "Apenas uma conta registrada pode ser lider."
          or "O lider precisa aceitar sua solicitacao.",
          px+30,py+247,16,0.85)
      elseif self.tab=="invites" then
        local invites=self:rows()
        if #invites==0 then
          text("Nenhum convite de cla recebido.",px+27,py+156,19)
        end
        for i=1,math.min(5,#invites-self.scroll) do
          local it=invites[i+self.scroll]
          local ry=py+150+(i-1)*59
          rect(px+19,ry,pw-38,55,0,0,0,0.24)
          text(tostring(it.clan),px+34,ry+8,18)
          text("Convidado por "..tostring(it.by):sub(1,18),px+34,ry+30,13,0.8)
          button("Aceitar",px+368,ry+10,79,36,true)
          button("Recusar",px+465,ry+10,88,36,false)
        end
      end
    elseif self.tab=="members" or self.tab=="requests" then
      local rows=self:rows()
      if #rows==0 then
        text(self.tab=="members" and "Nenhum membro." or
          "Nao ha solicitacoes pendentes.",px+30,py+155,18)
      end
      for i=1,math.min(5,#rows-self.scroll) do
        local member=rows[i+self.scroll]
        local ry=py+154+(i-1)*58
        rect(px+20,ry,pw-40,54,0,0,0,0.23)
        local name=type(member)=="table" and member.name or member
        local rank=type(member)=="table" and member.role or nil
        text(tostring(name):sub(1,20),px+32,ry+11,18)
        if rank then text(tostring(rank),px+32,ry+33,12,0.8) end
        if self.tab=="requests" and self:officer() then
          button("Aceitar",px+369,ry+8,80,38,true)
          button("Recusar",px+467,ry+8,90,38,false)
        elseif self.tab=="members" and name~=self.accountName then
          if self:leader() then
            button(rank=="member" and "Oficial" or rank=="officer" and
              "Lider" or "Cargo",px+354,ry+8,108,38,false)
          end
          if self:officer() then button("Expulsar",px+469,ry+8,92,38,false) end
        end
      end
    elseif self.tab=="manage" then
      if self:officer() then
        text("Convidar jogador pelo nome registrado",px+28,py+143,17)
        input(self.inputs.target,px+26,py+181,352,46,
          self.field=="target","Nome do jogador")
        button("Convidar",px+394,py+181,163,46,true)
      else
        text("Apenas lideres e oficiais podem convidar.",px+28,py+155,17)
      end
      if self:leader() then
        local isClosed=clan.closed==true
        button(isClosed and "Abrir solicitacoes" or "Fechar solicitacoes",
          px+30,py+255,252,45,false)
      end
      button("Sair do cla",px+30,py+ph-117,250,47,false)
      if self:leader() then
        button(self.confirmDisband and "Confirmar exclusao" or "Excluir cla",
          px+308,py+ph-117,251,47,false)
      end
    end
  end
  if self.message~="" then
    rect(px+20,py+ph-54,pw-40,38,0,0,0,0.30)
    font(13);color(1,0.9,0.64)
    love.graphics.printf(self.message,px+30,py+ph-45,pw-60,"left")
  end
end
return C
