-- Port of client/src/data/player.js and client/src/data/ai.js attack poses.
-- This affects drawing only; the authoritative Node server decides hits/damage.
local Animation={}
local PI=math.pi
local HIT_RATIO=0.25  -- shared/config.js: hitReturnRatio
local HIT_ANGLE=PI/2  -- shared/config.js: hitAngle

function Animation.player(entity,didHit,weapon,speedFactor)
  if type(entity)~="table" or type(weapon)~="table" then return false end
  local speed=weapon.speed
  if type(speed)~="number" or speed<=0 then return false end
  -- The current reference Node server sends optional attack speed multiplier
  -- in K(sid, hit, weaponIndex, speedFactor).
  if type(speedFactor)=="number" and speedFactor>0 then
    speed=speed/speedFactor
  end
  entity.animTime=speed
  entity.animSpeed=speed
  entity.targetAngle=(didHit==1 or didHit==true) and -HIT_ANGLE or -PI
  entity.animRatio=0
  entity.animStage=0
  entity.dirPlus=0
  return true
end

function Animation.animal(entity)
  if type(entity)~="table" then return false end
  entity.animTime=600
  entity.animSpeed=600
  entity.targetAngle=PI*0.8
  entity.animRatio=0
  entity.animStage=0
  entity.dirPlus=0
  return true
end

function Animation.update(entity,dt)
  if type(entity)~="table" then return end
  local remaining=entity.animTime or 0
  if remaining<=0 then return end
  if type(dt)~="number" or dt<=0 then return end
  -- JS passes milliseconds, LÖVE passes seconds.
  local delta=dt*1000
  remaining=remaining-delta
  entity.animTime=math.max(0,remaining)
  if remaining<=0 then
    entity.dirPlus=0
    entity.animRatio=0
    entity.animStage=0
    return
  end
  local speed=entity.animSpeed
  if not speed or speed<=0 then return end
  local ratio=entity.animRatio or 0
  if (entity.animStage or 0)==0 then
    ratio=ratio+delta/(speed*HIT_RATIO)
    entity.dirPlus=(entity.targetAngle or 0)*math.min(1,ratio)
    if ratio>=1 then ratio=1;entity.animStage=1 end
  else
    ratio=ratio-delta/(speed*(1-HIT_RATIO))
    entity.dirPlus=(entity.targetAngle or 0)*math.max(0,ratio)
  end
  entity.animRatio=ratio
end
return Animation
