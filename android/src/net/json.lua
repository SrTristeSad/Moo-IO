-- Small self-contained JSON codec for Moo-Quest local API payloads.
-- Lua 5.1+; never evaluate JSON as executable Lua. Parse limits avoid cycles
-- and unexpectedly enormous responses from a misconfigured server.
local J={}
J.null=setmetatable({},{__tostring=function() return "json.null" end})
local function spaces(c) return c==" " or c=="\t" or c=="\n" or c=="\r" end
local function utf8(n)
  if n<=0x7f then return string.char(n)
  elseif n<=0x7ff then
    return string.char(0xc0+math.floor(n/64),0x80+n%64)
  elseif n<=0xffff then
    return string.char(0xe0+math.floor(n/4096),0x80+math.floor(n/64)%64,0x80+n%64)
  end
  return string.char(0xf0+math.floor(n/262144),0x80+math.floor(n/4096)%64,
    0x80+math.floor(n/64)%64,0x80+n%64)
end
function J.decode(data)
  if type(data)~="string" or #data>131072 then return nil,"JSON too large or not text" end
  local i,n=1,#data
  local function skip()
    while i<=n and spaces(data:sub(i,i)) do i=i+1 end
  end
  local parse
  local function quoted()
    if data:sub(i,i)~='"' then error("expected JSON string") end
    i=i+1
    local out={}
    local start=i
    while i<=n do
      local b=data:byte(i)
      if b==34 then
        out[#out+1]=data:sub(start,i-1);i=i+1
        return table.concat(out)
      elseif b==92 then
        out[#out+1]=data:sub(start,i-1)
        i=i+1
        local e=data:sub(i,i)
        local symbols={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',
          n='\n',r='\r',t='\t'}
        if symbols[e] then out[#out+1]=symbols[e];i=i+1
        elseif e=="u" then
          local hex=data:sub(i+1,i+4)
          if not hex:match("^%x%x%x%x$") then error("invalid unicode escape") end
          local cp=tonumber(hex,16)
          i=i+5
          if cp>=0xd800 and cp<=0xdbff then
            if data:sub(i,i+1)~="\\u" then error("missing low surrogate") end
            local lo=data:sub(i+2,i+5)
            if not lo:match("^%x%x%x%x$") then error("bad surrogate") end
            local l=tonumber(lo,16)
            if l<0xdc00 or l>0xdfff then error("bad low surrogate") end
            cp=0x10000+(cp-0xd800)*1024+(l-0xdc00)
            i=i+6
          elseif cp>=0xdc00 and cp<=0xdfff then
            error("unexpected low surrogate")
          end
          out[#out+1]=utf8(cp)
        else error("invalid escape") end
        start=i
      elseif b<32 then error("unescaped JSON control") else i=i+1 end
    end
    error("unterminated JSON string")
  end
  local function number()
    local start=i
    if data:sub(i,i)=="-" then i=i+1 end
    if data:sub(i,i)=="0" then
      i=i+1
    else
      if not data:sub(i,i):match("%d") then error("bad JSON number") end
      while data:sub(i,i):match("%d") do i=i+1 end
    end
    if data:sub(i,i)=="." then
      i=i+1
      if not data:sub(i,i):match("%d") then error("bad fraction") end
      while data:sub(i,i):match("%d") do i=i+1 end
    end
    if data:sub(i,i):lower()=="e" then
      i=i+1
      if data:sub(i,i)=="+" or data:sub(i,i)=="-" then i=i+1 end
      if not data:sub(i,i):match("%d") then error("bad exponent") end
      while data:sub(i,i):match("%d") do i=i+1 end
    end
    local result=tonumber(data:sub(start,i-1))
    if not result or result~=result or result==math.huge or result==-math.huge then
      error("nonfinite JSON number")
    end
    return result
  end
  parse=function(depth)
    if depth>32 then error("JSON too deeply nested") end
    skip()
    local ch=data:sub(i,i)
    if ch=='"' then return quoted()
    elseif ch=="{" then
      i=i+1;skip()
      local result={}
      if data:sub(i,i)=="}" then i=i+1;return result end
      while i<=n do
        skip()
        local key=quoted()
        skip()
        if data:sub(i,i)~=":" then error("object missing colon") end
        i=i+1
        result[key]=parse(depth+1)
        skip()
        local sep=data:sub(i,i);i=i+1
        if sep=="}" then return result end
        if sep~="," then error("object missing separator") end
      end
      error("unterminated object")
    elseif ch=="[" then
      i=i+1;skip()
      local result={}
      if data:sub(i,i)=="]" then i=i+1;return result end
      while i<=n do
        result[#result+1]=parse(depth+1)
        skip()
        local sep=data:sub(i,i);i=i+1
        if sep=="]" then return result end
        if sep~="," then error("array missing separator") end
      end
      error("unterminated array")
    elseif data:sub(i,i+3)=="true" then i=i+4;return true
    elseif data:sub(i,i+4)=="false" then i=i+5;return false
    elseif data:sub(i,i+3)=="null" then i=i+4;return J.null
    elseif ch=="-" or ch:match("%d") then return number()
    end
    error("invalid JSON value")
  end
  local ok,result=pcall(function()
    local value=parse(0)
    skip()
    if i<=n then error("extra bytes after JSON") end
    return value
  end)
  if not ok then return nil,tostring(result) end
  return result
end
local function escape(s)
  local map={['"']='\\"',['\\']='\\\\',['\b']='\\b',
    ['\f']='\\f',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
  return '"'..s:gsub('[%z\1-\31\\"]',function(ch)
    return map[ch] or string.format("\\u%04x",ch:byte())
  end)..'"'
end
local function encode(v,seen,depth)
  if depth>32 then error("JSON too deeply nested") end
  local t=type(v)
  if v==J.null or t=="nil" then return "null"
  elseif t=="boolean" then return v and "true" or "false"
  elseif t=="number" then
    if v~=v or v==math.huge or v==-math.huge then error("invalid number") end
    return tostring(v)
  elseif t=="string" then return escape(v)
  elseif t=="table" then
    if seen[v] then error("cyclic JSON structure") end
    seen[v]=true
    local num,max=0,0
    for key in pairs(v) do
      if type(key)=="number" and key>=1 and key%1==0 then
        num=num+1;max=math.max(max,key)
      else num=-999;break end
    end
    local out={}
    if num==max and num>0 then
      for k=1,max do out[#out+1]=encode(v[k],seen,depth+1) end
      seen[v]=nil
      return "["..table.concat(out,",").."]"
    end
    local keys={}
    for key in pairs(v) do
      if type(key)~="string" then error("JSON object key not a string") end
      keys[#keys+1]=key
    end
    table.sort(keys)
    for _,key in ipairs(keys) do
      out[#out+1]=escape(key)..":"..encode(v[key],seen,depth+1)
    end
    seen[v]=nil
    return "{"..table.concat(out,",").."}"
  end
  error("unsupported JSON type")
end
function J.encode(v)
  local ok,result=pcall(encode,v,{},0)
  if not ok then return nil,tostring(result) end
  return result
end
return J
