-- Transport lifecycle; no pretend successful connection.
local State={}
State.__index=State
local allowed={
  idle={connecting=true},
  connecting={handshake=true,failed=true,closed=true},
  handshake={ready=true,failed=true,closed=true},
  ready={closed=true,failed=true},
  failed={connecting=true,closed=true},
  closed={connecting=true}
}
function State.new()
  return setmetatable({value="idle",reason=nil},State)
end
function State:transition(nextState,reason)
  if not (allowed[self.value] and allowed[self.value][nextState]) then
    return false,"invalid transition "..self.value.." -> "..tostring(nextState)
  end
  self.value=nextState
  self.reason=reason
  return true
end
return State
