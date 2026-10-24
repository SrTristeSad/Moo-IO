-- SPDX-License-Identifier: AGPL-3.0-only
-- Browser login contract test without network, browser or password input.
return function()
  local Auth=require("src.net.browser_auth")
  local Json=require("src.net.json")
  local stage=0
  local id=string.rep("a",40)
  local token="aaaa.bbbb.cccc"
  local ltn12={
    source={string=function(body)
      local read=false
      return function()
        if read then return nil end
        read=true
        return body
      end
    end},
    sink={table=function(chunks)
      return function(chunk)
        if chunk then chunks[#chunks+1]=chunk end
        return 1
      end
    end}
  }
  local http={TIMEOUT=5}
  function http.request(req)
    assert(req.method=="POST")
    assert(req.headers["X-MooIO-Code"]=="testing-room-code")
    assert(req.headers["Content-Type"]=="application/json")
    local body=Json.decode(req.source())
    assert(type(body)=="table")
    assert(body.email==nil and body.password==nil,"password must stay in external browser")
    local reply,status
    if req.url:match("/api/auth/v2/start$") then
      assert(type(body.challenge)=="string" and #body.challenge==43)
      reply={id=id,verificationUri="https://auth.example.org/login?id="..id,
        expiresIn=300,interval=2}
      status=200
    elseif req.url:match("/api/auth/v2/token$") then
      assert(body.id==id and type(body.verifier)=="string" and #body.verifier==64)
      stage=stage+1
      if stage==1 then reply={status="pending"};status=202
      else reply={status="authorized",token=token,email="test@example.org",id="abc"}
        status=200
      end
    else error("wrong HTTP route") end
    req.sink(Json.encode(reply))
    return 1,status
  end
  local opts={http=http,ltn12=ltn12,
    random=function(n)assert(n==48);return string.rep("z",48) end,
    sha256=function(verifier)assert(#verifier==64);return string.rep("\003",32) end}
  local state,why=Auth.begin("100.90.10.8",8080,"testing-room-code",opts)
  assert(state and not why)
  assert(state.verificationUri=="https://auth.example.org/login?id="..id)
  assert(http.TIMEOUT==5,"HTTP timeout must be restored")
  local pending,reason=Auth.poll(state)
  assert(pending==nil and reason=="pending")
  local granted,errorMessage=Auth.poll(state)
  assert(granted and not errorMessage and granted.token==token)
  assert(granted.email=="test@example.org")
  local invalid,reasonBad=Auth.begin("8.8.8.8",443,"testing-room-code",opts)
  assert(invalid==nil and type(reasonBad)=="string" and reasonBad:find("IP privado",1,true))
  print("MOO IO BROWSER AUTH PASS: PKCE, private transport, scoped JWT")
end
