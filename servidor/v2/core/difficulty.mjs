// Server-side difficulty presets. No client changes or arbitrary scripting.
// Applied before explicit JSON mod overrides; the original preset is identical.
const PRESETS=Object.freeze({
  normal:{spawn:1,damage:1,speed:1,range:1},
  dificil:{spawn:1.5,damage:1.2,speed:1.1,range:1.2},
  extremo:{spawn:2,damage:1.5,speed:1.2,range:1.4}
});
export const levels=Object.keys(PRESETS);
export function applyDifficulty(name,{config,aiTypes}){
  if(!Object.hasOwn(PRESETS,name))throw Error("Dificuldade desconhecida: "+name);
  const preset=PRESETS[name],changes=[];
  if(name==="normal")return changes;
  const edit=(target,property,value)=>{
    if(target[property]===value)return;
    changes.push({path:property,from:target[property],to:value});
    target[property]=value;
  };
  for(const entry of config.server.animalSpawnPlan){
    const type=aiTypes[entry.index];
    if(!type)throw Error("Tipo de animal desconhecido: "+entry.index);
    if(type.boss||type.fixedSpawn)continue;
    edit(entry,"desired",Math.min(200,Math.ceil(entry.desired*preset.spawn)));
  }
  for(const animal of aiTypes){
    if(!animal?.hostile||animal.boss)continue;
    if(typeof animal.dmg==="number")edit(animal,"dmg",Math.min(10000,animal.dmg*preset.damage));
    if(typeof animal.speed==="number")edit(animal,"speed",Math.min(.02,animal.speed*preset.speed));
    if(typeof animal.viewRange==="number")edit(animal,"viewRange",Math.min(6000,animal.viewRange*preset.range));
  }
  if(config.server.animalSpawnPlan.reduce((sum,row)=>sum+row.desired,0)>600)
    throw Error("Excesso de animais no preset");
  return changes;
}
