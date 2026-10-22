-- Read the original pinned server's protocol-build.json (READ-ONLY).
-- The Lua client does not patch or write any file in the upstream server.
local M={}
local fields={"salt","rounds","tapA","tapB","rotA","rotB","mult"}
function M.parse(json)
  if type(json)~="string" or #json>32768 then return nil,"invalid build JSON" end
  local buildId=json:match('"buildId"%s*:%s*"([%w]+)"')
  if not buildId then return nil,"buildId absent" end
  local values={buildId=buildId}
  for _,name in ipairs(fields) do
    local match=json:match('"'..name..'"%s*:%s*(%d+)')
    if not match then return nil,"missing "..name end
    values[name]=tonumber(match)
  end
  local array=json:match('"constants"%s*:%s*%[([^%]]+)%]')
  if not array then return nil,"missing constants" end
  values.constants={}
  for number in array:gmatch("%d+") do
    values.constants[#values.constants+1]=tonumber(number)
  end
  if #values.constants~=8 then return nil,"invalid constants" end
  for _,v in ipairs(values.constants) do
    if v<0 or v>4294967295 then return nil,"invalid constant range" end
  end
  if values.salt>4294967295 or values.mult>4294967295
    or values.rounds<1 or values.rounds>16
    or values.tapA<1 or values.tapA>7
    or values.tapB<1 or values.tapB>7
    or values.rotA<1 or values.rotA>31
    or values.rotB<1 or values.rotB>31 then
    return nil,"invalid build parameters"
  end
  return values
end
-- Locate the actual protocol build of the RUNNING Node server, read-only.
-- The old implementation stopped at the first invalid MOOQUEST_BUILD_FILE and
-- made the Windows client unusable even when the right file existed nearby.
local function join(dir,child)
  if not dir or dir=="" then return nil end
  return (dir:gsub("[/\\]+$","")).."/"..child
end
local function candidates()
  local result,seen={},{}
  local function add(path)
    if type(path)~="string" or path=="" then return end
    -- Windows accepts '/' separators, but preserve the original casing/path.
    local canonical=path:gsub("\\","/"):lower()
    if seen[canonical] then return end
    seen[canonical]=true
    result[#result+1]=path
  end
  add(os.getenv("MOOQUEST_BUILD_FILE"))
  add(os.getenv("PROTOCOL_BUILD_FILE"))
  add(join(os.getenv("DATA_DIR"),"protocol-build.json"))
  local server=os.getenv("MOOQUEST_SERVER_DIR") or "node-runtime"
  add(join(server,"server/data/protocol-build.json"))
  -- Explicit alternative layouts for people who started Node manually.
  add("node-runtime/server/data/protocol-build.json")
  add("server/data/protocol-build.json")
  local base=nil
  if love and love.filesystem and love.filesystem.getSourceBaseDirectory then
    local ok,dir=pcall(love.filesystem.getSourceBaseDirectory)
    if ok and type(dir)=="string" then base=dir end
  end
  if base then
    add(join(base,"node-runtime/server/data/protocol-build.json"))
    add(join(base,"server/data/protocol-build.json"))
    local folder=os.getenv("MOOQUEST_SERVER_DIR")
    if folder and not folder:match("^%a:[/\\]") and folder:sub(1,1)~="/" then
      add(join(base,folder.."/server/data/protocol-build.json"))
    end
  end
  return result
end
M.candidates=candidates

function M.load(expectedBuildId)
  local inspected=0
  local incompatible=false
  local malformed=false
  for _,filename in ipairs(candidates()) do
    local file=io.open(filename,"rb")
    if file then
      local data=file:read(32769)
      file:close()
      inspected=inspected+1
      local params,err=M.parse(data)
      if params and (not expectedBuildId or params.buildId==expectedBuildId) then
        return params,nil,filename
      end
      if params and expectedBuildId and params.buildId~=expectedBuildId then
        incompatible=true
      elseif err then
        malformed=true
      end
    end
  end
  -- Fall back to the embedded LOVE filesystem for a supported local source.
  if love and love.filesystem and love.filesystem.getInfo and
     love.filesystem.getInfo("node-runtime/server/data/protocol-build.json") then
    local data=love.filesystem.read("node-runtime/server/data/protocol-build.json")
    local params=M.parse(data)
    if params and (not expectedBuildId or params.buildId==expectedBuildId) then
      return params,nil,"node-runtime/server/data/protocol-build.json"
    end
  end
  if incompatible then
    return nil,"O build local e diferente do Node ativo. Reinicie pelo INICIAR-WINDOWS.bat ou indique o arquivo gerado pelo servidor correto."
  end
  if malformed then
    return nil,"O protocol-build.json encontrado esta incompleto ou invalido. Verifique a instalacao do Node."
  end
  return nil,"protocol-build.json nao localizado. Reinicie pelo INICIAR-WINDOWS.bat; se usar outro servidor, configure MOOQUEST_BUILD_FILE."
end
return M
