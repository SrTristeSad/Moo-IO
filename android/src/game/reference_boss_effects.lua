-- Node server/src/moomoo/modules/ai.js emits packet "W" for Crab King
-- area telegraphs. These shapes visualize the EXISTING server attack geometry:
-- SPLASH (blue/white ring), GEYSER (dotted rim), SLAM (orange disk),
-- CLAW (red line corridor). Damage/collisions remain Node authoritative.
local E={}
E.SPLASH=1
E.GEYSER=2
E.SLAM=3
E.CLAW=4
local MAX_ACTIVE=128
local PI=math.pi
local sin,cos=math.sin,math.cos
local function finite(v)
  return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge
end

function E.add(list,kind,x,y,r,duration,x2,y2)
  if type(list)~="table" or not finite(kind) or kind%1~=0
    or kind<1 or kind>4 or not finite(x) or not finite(y)
    or not finite(r) or r<=0 or r>4000
    or not finite(duration) or duration<=0 or duration>10000 then return false end
  if kind==E.CLAW and (not finite(x2) or not finite(y2) or
    (x2-x)^2+(y2-y)^2>5000^2) then return false end
  -- Do not retain excessive events if a server sends repeated W packets.
  if #list>=MAX_ACTIVE then table.remove(list,1) end
  list[#list+1]={kind=kind,x=x,y=y,r=r,life=duration,
    duration=duration,x2=x2,y2=y2}
  return true
end

function E.update(list,dt)
  if type(list)~="table" or not finite(dt) or dt<=0 then return end
  local ms=dt*1000
  for i=#list,1,-1 do
    local e=list[i]
    e.life=e.life-ms
    if e.life<=0 then table.remove(list,i) end
  end
end

function E.draw(list,camera)
  if type(list)~="table" or not camera or not love or not love.graphics then
    return end
  local g=love.graphics
  g.push("all")
  for _,e in ipairs(list) do
    if e.life>0 then
      local x,y=camera:worldToScreen(e.x,e.y)
      -- World-space radii are identical to the Node hit-test radius.
      g.push()
      g.translate(x,y)
      g.scale(camera.zoom)
      local urgency=1-math.max(0,math.min(1,e.life/e.duration))
      local ringAlpha=0.45+urgency*0.35
      if e.kind==E.SPLASH then
        -- Water ring and light centre indicate the surfacing impact.
        g.setColor(0.43,0.79,1,0.16+urgency*0.15)
        g.circle("fill",0,0,e.r)
        g.setColor(0.40,0.82,1,ringAlpha)
        g.setLineWidth(9)
        g.circle("line",0,0,e.r)
        g.setColor(1,1,1,0.65)
        g.setLineWidth(4)
        g.circle("line",0,0,e.r*0.75)
      elseif e.kind==E.GEYSER then
        -- Dotted perimeter from the boss's geyser-effect description.
        g.setColor(0.28,0.75,1,0.15+urgency*0.13)
        g.circle("fill",0,0,e.r)
        g.setColor(0.66,0.92,1,ringAlpha)
        for n=0,15 do
          local a=2*PI*n/16
          g.circle("fill",cos(a)*e.r,sin(a)*e.r,7)
        end
      elseif e.kind==E.SLAM then
        g.setColor(1,0.57,0.19,0.16+urgency*0.15)
        g.circle("fill",0,0,e.r)
        g.setColor(1,0.64,0.24,ringAlpha)
        g.setLineWidth(10)
        g.circle("line",0,0,e.r)
      elseif e.kind==E.CLAW then
        -- Server damage uses distToSegment <= e.r + player.scale.
        -- Draw the actual 2*r wide threat corridor, not a narrow arrow.
        local dx,dy=e.x2-e.x,e.y2-e.y
        local length=math.sqrt(dx*dx+dy*dy)
        if length>0 then
          g.rotate(math.atan2 and math.atan2(dy,dx) or math.atan(dy,dx))
          g.setColor(1,0.24,0.26,0.15+urgency*0.13)
          g.setLineWidth(e.r*2)
          g.line(0,0,length,0)
          g.circle("fill",0,0,e.r)
          g.circle("fill",length,0,e.r)
          g.setColor(1,0.28,0.29,ringAlpha)
          g.setLineWidth(6)
          g.line(0,-e.r,length,-e.r)
          g.line(0,e.r,length,e.r)
          -- Three small chevrons make this distinguishable from circles.
          for i=1,3 do
            local pos=length*i/4
            g.line(pos-22,-20,pos,0,pos-22,20)
          end
        end
      end
      g.pop()
    end
  end
  g.pop()
end

return E
