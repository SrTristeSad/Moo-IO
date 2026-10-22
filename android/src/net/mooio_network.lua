-- SPDX-License-Identifier: AGPL-3.0-only
-- Private addresses used by LAN and virtual VPN adapters. No arbitrary Internet IPs.
local N={}
local function parse(ip)
  if type(ip)~="string" then return nil end
  local a,b,c,d=ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if not a then return nil end
  local parts={a,b,c,d}
  local n={}
  for i=1,4 do
    if #parts[i]>1 and parts[i]:sub(1,1)=="0" then return nil end
    n[i]=tonumber(parts[i])
    if not n[i] or n[i]>255 then return nil end
  end
  return n
end
function N.kind(ip)
  local v=parse(ip)
  if not v then return nil end
  local a,b,c,d=v[1],v[2],v[3],v[4]
  if a==127 then return "loopback" end
  if a==10 or a==192 and b==168 or a==172 and b>=16 and b<=31 then return "lan" end
  if a==100 and b>=64 and b<=127 and not (b==100 and c==100 and d==100) then return "tailscale" end
  if a==25 or a==26 then return "vpn" end
  return nil
end
function N.accept(ip,mode)
  local kind=N.kind(ip)
  if not kind then return false end
  if mode=="vpn" then return kind~="loopback" end
  if mode=="lan" then return kind=="lan" or kind=="loopback" end
  return false
end
function N.invite(value)
  if type(value)~="string" then return nil,"Convite vazio." end
  value=value:match("^%s*(.-)%s*$")
  local host,port,code=value:match("^([%d%.]+):(%d%d?%d?%d?%d?)/([%w%-]+)$")
  local kind=N.kind(host)
  if not kind then return nil,"Use IP da LAN/VPN privada, nao um endereco publico." end
  port=tonumber(port)
  if not port or port<1 or port>65535 or #code<8 or #code>64 then
    return nil,"Porta ou codigo do convite invalido."
  end
  return {host=host,port=port,code=code,mode=(kind=="tailscale" or kind=="vpn") and "vpn" or "lan"}
end
return N
