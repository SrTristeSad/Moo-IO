-- Reference PNG loader. Images stay in assets/reference/img copied locally
-- from node-runtime/client/public/img. Never silently replace absent sprites.
local A={}
local cache={}
local missing={}
local allowed={animals=true,weapons=true,hats=true,accessories=true,
  resources=true,icons=true}
-- Give original user artwork precedence. If a local custom file cannot
-- decode, the reference PNG remains available as a fallback.
local function candidatePaths(category,filename)
  local rel=category.."/"..filename
  return {"assets/custom/img/"..rel,"assets/reference/img/"..rel}
end
function A.get(category,filename)
  if not allowed[category] then return nil end
  if type(filename)~="string" or not filename:match("^[%w_%-]+%.png$") then
    return nil
  end
  local id=category.."/"..filename
  if cache[id]~=nil then return cache[id] or nil end
  local failed={}
  for _,path in ipairs(candidatePaths(category,filename)) do
    if love.filesystem.getInfo(path,"file") then
      local ok,result=pcall(love.graphics.newImage,path)
      if ok and result then
        result:setFilter("linear","linear")
        cache[id]=result
        missing[id]=nil
        return result
      end
      failed[#failed+1]=path.." nao pode ser aberto ("..tostring(result)..")"
    end
  end
  missing[id]=#failed>0 and table.concat(failed,"; ") or "arquivo nao encontrado"
  cache[id]=false
  return nil
end
-- The pinned source is missing bow_1_d.png (diamond bow), despite
-- containing all the other 16 x 5 weapon variants. Never synthesize
-- proprietary art: prefer that weapon's ORIGINAL base image rather than
-- making an upgraded weapon disappear. If the user adds bow_1_d.png later,
-- it will be used automatically with no additional code changes.
function A.weaponFilename(source,suffix,exists)
  if type(source)~="string" or
    not source:match("^[%w_%-]+$") then return nil,false end
  suffix=suffix or ""
  if type(suffix)~="string" or
    (suffix~="" and suffix~="_g" and suffix~="_d" and
      suffix~="_r" and suffix~="_e") then return nil,false end
  local desired=source..suffix..".png"
  if suffix=="" then return desired,false end
  local check=exists or function(file)
    for _,path in ipairs(candidatePaths("weapons",file)) do
      if love.filesystem.getInfo(path,"file") then return true end
    end
    return false
  end
  if check(desired) then return desired,false end
  return source..".png",true
end
function A.draw(category,filename,x,y,w,h,angle,alpha)
  local image=A.get(category,filename)
  if not image then return false end
  love.graphics.setColor(1,1,1,alpha or 1)
  love.graphics.draw(image,x,y,angle or 0,
    w/image:getWidth(),h/image:getHeight(),image:getWidth()/2,image:getHeight()/2)
  return true
end
function A.missing()
  local paths={}
  for p,why in pairs(missing) do
    paths[#paths+1]={path=p,reason=why}
  end
  table.sort(paths,function(a,b) return a.path<b.path end)
  return paths
end
function A.missingSummary(limit)
  local list=A.missing()
  local lines={}
  for i=1,math.min(limit or 3,#list) do
    lines[#lines+1]=list[i].path.." ("..list[i].reason..")"
  end
  return lines,#list
end
function A.reset()
  cache={}
  missing={}
end
return A
