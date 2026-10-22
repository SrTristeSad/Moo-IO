-- Direct Lua/LÖVE equivalents of Canvas shapes in client/src/index.js:
-- renderCircle, renderStar, renderBlob, renderRect, renderRectCircle,
-- renderTriangle and renderLeaf. No invented art assets.
local P={}
local pi=math.pi
local cos,sin=math.cos,math.sin
P.outline="#525252"
P.darkOutline="#3d3f42"
P.width=5.5

function P.color(hex,alpha)
  if type(hex)~="string" or not hex:match("^#%x%x%x%x%x%x$") then
    hex=P.outline
  end
  love.graphics.setColor(
    tonumber(hex:sub(2,3),16)/255,
    tonumber(hex:sub(4,5),16)/255,
    tonumber(hex:sub(6,7),16)/255,
    alpha or 1)
end

function P.path(points,fillColor,strokeColor,width)
  if #points<6 then return end
  -- Canvas closePath is implicit. Strip the duplicate final vertex for triangulation.
  local dx=points[#points-1]-points[1]
  local dy=points[#points]-points[2]
  if dx*dx+dy*dy<0.000001 and #points>6 then
    local clipped={}
    for i=1,#points-2 do clipped[i]=points[i] end
    points=clipped
  end
  if fillColor then
    P.color(fillColor)
    -- LÖVE fill only supports convex polygons; Canvas stars and blobs are concave.
    local convex=love.math.isConvex(points)
    if convex then
      love.graphics.polygon("fill",points)
    else
      -- Some concave Bezier outlines make LÖVE's ear clipping reject the
      -- outline. The original Canvas still fills them. Try triangulation,
      -- then render the same radial outline as a triangle fan if necessary.
      local ok,triangles=pcall(love.math.triangulate,points)
      if ok and triangles and #triangles>0 then
        for _,triangle in ipairs(triangles) do
          love.graphics.polygon("fill",triangle)
        end
      else
        for i=3,#points-2,2 do
          love.graphics.polygon("fill",
            points[1],points[2],points[i],points[i+1],
            points[i+2],points[i+3])
        end
      end
    end
  end
  if strokeColor then
    P.color(strokeColor)
    local radius=(width or P.width)/2
    love.graphics.setLineWidth(radius*2)
    love.graphics.setLineJoin("bevel")
    love.graphics.polygon("line",points)
    -- Canvas uses round joins for getResSprite()/getItemSprite().
    for i=1,#points,2 do
      love.graphics.circle("fill",points[i],points[i+1],radius)
    end
  end
end

function P.circle(x,y,r,fillColor,strokeColor,width)
  if type(r)~="number" or r<=0 then return end
  if fillColor then
    P.color(fillColor);love.graphics.circle("fill",x,y,r)
  end
  if strokeColor then
    P.color(strokeColor);love.graphics.setLineWidth(width or P.width)
    love.graphics.circle("line",x,y,r)
  end
end

-- Exact radial vertices used by JS renderStar (two vertices per spike).
function P.star(spikes,outer,inner,fillColor,strokeColor,width)
  local pts={}
  local angle=3*pi/2
  local step=pi/spikes
  if math.abs(inner-outer)<0.001 then
    -- client/src/index.js renderStar: equal radii are a regular 2*spike
    -- polygon; repeating inner vertices distorted original rocks/walls.
    for i=0,spikes*2-1 do
      local a=angle+i*step
      pts[#pts+1]=cos(a)*outer
      pts[#pts+1]=sin(a)*outer
    end
  else
    for _=1,spikes do
      pts[#pts+1]=cos(angle)*outer;pts[#pts+1]=sin(angle)*outer
      angle=angle+step
      pts[#pts+1]=cos(angle)*inner;pts[#pts+1]=sin(angle)*inner
      angle=angle+step
    end
  end
  P.path(pts,fillColor,strokeColor,width)
end

-- JS renderBlob uses one random quadratic Bezier segment per spike.
-- LÖVE polygons approximate those same quadratic segments using samples.
function P.blob(spikes,outer,inner,fillColor,strokeColor,width)
  local pts={0,-inner}
  local x0,y0=0,-inner
  local rot=3*pi/2
  local step=pi/spikes
  for _=1,spikes do
    local maxR=math.floor(outer*1.2)
    local minR=math.ceil(outer+0.9)
    local rad=math.max(minR,math.floor(minR+love.math.random()*math.max(1,maxR-minR+1)))
    local cx,cy=cos(rot+step)*rad,sin(rot+step)*rad
    local x1,y1=cos(rot+2*step)*inner,sin(rot+2*step)*inner
    for j=1,12 do
      local t=j/12
      local a=(1-t)*(1-t);local b=2*(1-t)*t;local c=t*t
      pts[#pts+1]=a*x0+b*cx+c*x1
      pts[#pts+1]=a*y0+b*cy+c*y1
    end
    x0,y0=x1,y1
    rot=rot+2*step
  end
  -- JS closes the path back to its first point; LÖVE triangulation needs
  -- that duplicated final vertex removed from the submitted polygon list.
  local dx=pts[#pts-1]-pts[1]
  local dy=pts[#pts]-pts[2]
  if dx*dx+dy*dy<0.000001 then
    pts[#pts]=nil
    pts[#pts]=nil
  end
  P.path(pts,fillColor,strokeColor,width)
end

function P.rect(x,y,w,h,fillColor,strokeColor,width)
  if fillColor then
    P.color(fillColor)
    love.graphics.rectangle("fill",x-w/2,y-h/2,w,h)
  end
  if strokeColor then
    P.color(strokeColor)
    love.graphics.setLineWidth(width or P.width)
    love.graphics.rectangle("line",x-w/2,y-h/2,w,h)
  end
end

-- Canvas renderRectCircle rotates identical bars around the shared centre.
function P.rectCircle(x,y,s,sw,seg,fillColor,strokeColor,width)
  local n=math.ceil(seg/2)
  love.graphics.push()
  love.graphics.translate(x,y)
  for _=1,n do
    P.rect(0,0,s*2,sw,fillColor,strokeColor,width)
    love.graphics.rotate(pi/n)
  end
  love.graphics.pop()
end

function P.triangle(s,color)
  local h=s*math.sqrt(3)/2
  P.path({0,-h/2,-s/2,h/2,s/2,h/2},color,nil)
end

function P.leaf(x,y,length,r,fillColor,strokeColor,width)
  local ex=x+length*cos(r)
  local ey=y+length*sin(r)
  local spread=length*0.4
  local mx=(x+ex)/2
  local my=(y+ey)/2
  local nx,ny=cos(r+pi/2)*spread,sin(r+pi/2)*spread
  local pts={x,y}
  for j=1,12 do
    local t=j/12
    pts[#pts+1]=(1-t)^2*x+2*(1-t)*t*(mx+nx)+t*t*ex
    pts[#pts+1]=(1-t)^2*y+2*(1-t)*t*(my+ny)+t*t*ey
  end
  for j=1,12 do
    local t=j/12
    pts[#pts+1]=(1-t)^2*ex+2*(1-t)*t*(mx-nx)+t*t*x
    pts[#pts+1]=(1-t)^2*ey+2*(1-t)*t*(my-ny)+t*t*y
  end
  P.path(pts,fillColor,strokeColor,width)
end
return P
