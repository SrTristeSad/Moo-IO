-- SPDX-License-Identifier: AGPL-3.0-only
return function()
  local TLS=require("src.net.tls_bridge")
  local Upgrade=require("src.net.upgrade")
  local Network=require("src.net.mooio_network")
  assert(TLS.validDomain("normal.play.example.org"))
  for _,bad in ipairs({"127.0.0.1","8.8.8.8","local","EXAMPLE.COM",
     "evil.com:443","wrong..example.com","example.com/evil"}) do
    assert(not TLS.validDomain(bad),bad)
  end
  local target=Network.invite("https://normal.play.example.org/abcdefgh12345678")
  assert(target and target.secure and target.host=="normal.play.example.org" and
    target.port==443 and target.mode=="public")
  assert(Network.invite("normal.play.example.org:443/abcdefgh12345678")==nil,
    "Public connections must require explicit HTTPS scheme")
  local token=string.rep("a",48)
  local connectedTo,preface
  local mock={
    tcp=function()
      return {
        settimeout=function()return 1 end,
        connect=function(_,host,port)
          connectedTo=host..":"..port
          return 1
        end,
        send=function(_,data)
          preface=data
          return #data
        end,
        receive=function(_,pattern)
          assert(pattern=="*l")
          return "OK"
        end,
        close=function()end
      }
    end,
    select=function()return {},{} end
  }
  local settings,why=TLS.options("normal.play.example.org",443,{
    bridge={port=8469,token=token},socket=mock
  })
  assert(settings and not why)
  local tcp=settings.socket.tcp()
  tcp:settimeout(0)
  assert(tcp:connect("normal.play.example.org",443))
  assert(connectedTo=="127.0.0.1:8469")
  assert(preface=="MOOIO-TLS1 "..token.." normal.play.example.org 443\n")
  local no,err=TLS.options("normal.play.example.org",80,{
    bridge={port=8469,token=token},socket=mock
  })
  assert(no==nil and err)
  local bad,reason=TLS.options("evil.example.org",443,{
    bridge={port=8469,token="weak"},socket=mock
  })
  assert(bad==nil and reason)
  local upgrade=Upgrade.request("normal.play.example.org",443,"/s/LC","ABCDEFGHIJKLMNOPQRSTUV==",nil,true)
  assert(upgrade:find("Host: normal.play.example.org\r\n",1,true))
  assert(upgrade:find("Origin: https://normal.play.example.org\r\n",1,true))
  assert(not upgrade:find("Origin: http://",1,true))
  local localUpgrade=Upgrade.request("127.0.0.1",8080,"/s/LC","ABCDEFGHIJKLMNOPQRSTUV==")
  assert(localUpgrade:find("Origin: http://127.0.0.1:8080\r\n",1,true))
  print("MOO IO VERIFIED TLS CONTRACT PASS")
end
