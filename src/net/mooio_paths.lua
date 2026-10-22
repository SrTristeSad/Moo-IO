-- SPDX-License-Identifier: AGPL-3.0-only
-- A folder launched by LÖVE is itself the project root. getSourceBaseDirectory()
-- is its PARENT, which was causing the false "start-server.ps1 absent" error.
local Paths={}
local function strip(s)
  return type(s)=="string" and s:gsub("[/\\]+$","") or ""
end
local function join(a,b)
  return strip(a).."/"..b
end
local function existsFile(p)
  local f=io.open(p,"rb")
  if not f then return false end
  f:close()
  return true
end
local function goodRoot(root)
  if root=="" then return false end
  return existsFile(join(root,"main.lua"))
    and existsFile(join(root,"server/src/index.js"))
    and existsFile(join(root,"scripts/start-server.ps1"))
end
function Paths.find(fs)
  fs=fs or (love and love.filesystem)
  if not fs then return nil,"O sistema de arquivos do jogo nao esta disponivel." end
  local candidates={}
  local function add(value)
    if type(value)=="string" and #value>0 then
      value=strip(value)
      for _,existing in ipairs(candidates) do if existing==value then return end end
      candidates[#candidates+1]=value
    end
  end
  -- getSource() points to the game FOLDER when launched as love.exe <folder>.
  -- getSourceBaseDirectory() points to the containing folder, not the project.
  if type(fs.getSource)=="function" then add(fs.getSource()) end
  if type(fs.getSourceBaseDirectory)=="function" then add(fs.getSourceBaseDirectory()) end
  if type(fs.getWorkingDirectory)=="function" then add(fs.getWorkingDirectory()) end
  for _,candidate in ipairs(candidates) do
    if goodRoot(candidate) then return candidate end
  end
  -- LÖVE archives are readable for graphics but not executable as
  -- filesystem scripts. Do not shell out to an arbitrary guessed path.
  return nil,"Instalacao incompleta: extraia o ZIP inteiro e abra MOO-IO.vbs na pasta do projeto."
end
function Paths.script(root)
  return join(root,"scripts/start-server.ps1")
end
function Paths.log(root)
  return join(root,"server/data/mooio-host.log")
end
return Paths
