// Moo IO private-room opponents. Uses the REAL server Player implementation:
// shared combat, collision, resources, damage, respawn and network snapshots.
import { items } from "../moomoo/modules/items.js";
const MAX_BOTS = 8;
const NAMES = ["Lince", "Ari", "Raposa", "Falcao", "Rubi", "Tora", "Lua", "Caio"];
const range = (a,b) => Math.hypot(a.x-b.x,a.y-b.y);
const angle = (a,b) => Math.atan2(b.y-a.y,b.x-a.x);
const clamp = (n,a,b) => Math.max(a,Math.min(b,n));
const angular = (a,b) => Math.atan2(Math.sin(a-b),Math.cos(a-b));

export function parseBotCount(raw) {
  if (raw === undefined || raw === "" || raw === null) return 0;
  if (!/^(?:[0-8])$/.test(String(raw))) throw new Error("MOO_IO_BOT_COUNT must be an integer 0..8");
  return Number(raw);
}
export class RoomBots {
  constructor(game,count=0) {
    this.game=game;
    this.agents=[];
    this.elapsed=0;
    this.thinkMs=270;
    this.count=parseBotCount(count);
    for(let i=0;i<this.count;i++) this.create(i);
  }
  create(index) {
    const g=this.game;
    const p=g.addPlayer({id:"mooio-bot-"+index,ip:"internal-bot",send:()=>{}});
    if(!p)throw new Error("Room bot could not reserve a player slot");
    p.isBot=true;
    p.setUserData({name:"Bot "+NAMES[index],skin:index%7});
    p.spawn(false);
    const agent={p,index,target:null,targetUntil:0,wander:null,at:0,
      prevX:p.x,prevY:p.y,stuck:0,detour:0,detourDir:0,respawn:0};
    this.agents.push(agent);
    return agent;
  }
  // A low-frequency decision loop; movement/physics still execute every
  // server tick, so remote clients receive normal smooth state snapshots.
  tick(delta) {
    this.elapsed+=delta;
    if(this.elapsed<this.thinkMs)return;
    const ms=this.elapsed;
    this.elapsed=0;
    for(const agent of this.agents)this.decide(agent,ms);
  }
  decide(a,delta) {
    const g=this.game,p=a.p;
    if(!p.alive) {
      a.respawn+=delta;
      if(a.respawn>=4300) {
        a.respawn=0;
        p.spawn(false);
        a.target=null;a.wander=null;a.stuck=0;
      }
      return;
    }
    a.respawn=0;
    a.at+=delta;
    if(p.health<p.maxHealth*0.74 && p.food>=10 && a.at>=850) {
      p.buildIndex=0;
      p.buildItem(items.list[0]);
      p.buildIndex=-1;
      a.at=0;
    }
    // Survival: perceive nearby living opponents/hostile animals.
    // No omniscient targeting across the map. Predators beat weak resource
    // targets, with low-health retreat and obstacle detours.
    let threat=null,dist=Infinity;
    for(const opponent of g.players) {
      if(opponent===p || !opponent.alive ||
        (p.team && opponent.team===p.team))continue;
      const d=range(p,opponent);
      if(d<dist && d<490) {threat=opponent;dist=d;}
    }
    for(const animal of g.ais) {
      if(!animal.alive || !animal.active || animal.spawnCounter ||
        animal.submerged || animal.index>=7)continue;
      const d=range(p,animal);
      // Avoid powerful bosses; normal wolves/bulls are threats, too.
      if(d<dist && d<380 && (animal.hostile || animal.index===4)) {
        threat=animal;dist=d;
      }
    }
    let target=null,mode="wander";
    const weak=p.health<p.maxHealth*0.37;
    if(threat && dist<480) {
      target=threat;mode=weak?"flee":"fight";
    } else {
      // Look for gatherable food/wood/stone in a local view radius. Favor
      // food when injured or low on food. Do not see through the full map.
      let best=Infinity;
      for(const object of g.game_objects) {
        if(!object.active || object.isItem || object.dontGather ||
          object.type<0 || object.type>3)continue;
        const d=range(p,object);
        if(d>500)continue;
        const foodNeed=p.food<30 || p.health<75;
        const score=d + (foodNeed && object.type!==1 ? 125:0) +
          (object.type===3 ? -25 : 0);
        if(score<best) {best=score;target=object;}
      }
      if(target)mode="gather";
      else {
        for(const animal of g.ais) {
          if(!animal.alive || !animal.active || animal.spawnCounter ||
             animal.submerged || animal.index>1)continue;
          const d=range(p,animal);
          if(d<400 && (p.food<35 || p.health<70)) {
            target=animal;mode="hunt";break;
          }
        }
      }
    }
    if(!target) {
      if(!a.wander || a.targetUntil<a.at || range(p,a.wander)<55) {
        const turn=(Math.random()*2-1)*Math.PI;
        const heading=(a.heading||0)+turn;
        a.heading=heading;
        const limit=g.config?.mapScale||14400;
        a.wander={x:clamp(p.x+Math.cos(heading)*470,80,limit-80),
          y:clamp(p.y+Math.sin(heading)*470,80,limit-80)};
        a.targetUntil=a.at+2500+Math.random()*2100;
      }
      target=a.wander;
    }
    let dir=angle(p,target),d=range(p,target);
    if(mode==="flee")dir+=Math.PI;
    // Strafe and retreat at medium distance so combat is not a simple
    // line-following collision; respect melee range when attacking.
    if(mode==="fight" && d<94 && p.health>35)dir+=Math.PI/2*(a.index%2?1:-1);
    if(Math.hypot(p.x-a.prevX,p.y-a.prevY)<4 && p.moveDir!==undefined)
      a.stuck+=delta;
    else a.stuck=0;
    if(a.stuck>900) {a.detour=a.at+1300;a.detourDir=dir+Math.PI/2*(a.index%2?1:-1);a.stuck=0;}
    if(a.at<a.detour)dir=a.detourDir;
    a.prevX=p.x;a.prevY=p.y;
    p.dir=angle(p,target);
    p.moveDir=(mode==="gather"&&d<85)||(mode==="wander"&&d<45)?undefined:dir;
    p.mouseState=0;
    if((mode==="fight"||mode==="gather"||mode==="hunt")
       && d<(items.weapons[p.weaponIndex]?.range||70)+
          (target.scale||0)*0.8+20 && mode!=="flee") {
      p.mouseState=1;
      p.gathering=1;
    }
  }
}
export const BOT_LIMIT=MAX_BOTS;
