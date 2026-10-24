// SPDX-License-Identifier: AGPL-3.0-only
// Data-only mods: no eval(), dynamic scripts or filesystem access given to mod files.
// A room runs in a separate Node process so overrides never leak into other rooms.
const RANGES={
  world:{
    treesPerArea:[0,30],bushesPerArea:[0,30],totalRocks:[0,1000],
    goldOres:[0,500]
  },
  animals:{health:[1,1000000],dmg:[0,10000],speed:[0,0.02],killScore:[0,1000000]},
  weapons:{dmg:[0,10000]},
  structures:{health:[1,1000000],dmg:[0,10000]},
  spawns:{desired:[0,200]}
};
const ALLOWED = Object.keys(RANGES);
const indexed = /^(0|[1-9][0-9]{0,3})$/;
const own=(object,key)=>Object.prototype.hasOwnProperty.call(object,key);
function plain(x){ return !!x&&typeof x==="object"&&!Array.isArray(x)&&Object.getPrototypeOf(x)===Object.prototype; }

export function validateManifest(mod) {
  if(!plain(mod)) throw new Error("Mod precisa ser objeto JSON");
  for(const k of Object.keys(mod)) if(!["schemaVersion","id","name","description","changes","requiresClient"].includes(k)) throw new Error("Campo desconhecido no mod: "+k);
  if(mod.schemaVersion!==1) throw new Error("schemaVersion do mod deve ser 1");
  if(typeof mod.id!=="string"||!/^[a-z0-9][a-z0-9-]{1,47}$/.test(mod.id)) throw new Error("id invalido");
  if(typeof mod.name!=="string"||!mod.name.trim()||mod.name.length>70) throw new Error("name invalido");
  if(mod.description!==undefined&&(typeof mod.description!=="string"||mod.description.length>500)) throw new Error("description invalida");
  if(mod.requiresClient!=="base") throw new Error("Somente requiresClient=base e suportado agora; novos sprites/protocolo nao estao prontos");
  if(!plain(mod.changes)||!Object.keys(mod.changes).length) throw new Error("changes precisa de ao menos uma alteracao");
  for(const [type,group] of Object.entries(mod.changes)) {
    if(!ALLOWED.includes(type)||!plain(group)||!Object.keys(group).length) throw new Error("Grupo desconhecido/vazio: "+type);
    for(const [id,attributes] of Object.entries(group)){
      if(type==="world") {
        if(!own(RANGES.world,id)) throw new Error("Regra de mundo nao suportada: "+id);
        validNumber(group[id],RANGES.world[id],type+"."+id);
      }else{
        if(!indexed.test(id)||!plain(attributes)||!Object.keys(attributes).length) throw new Error("Indice ou atributos invalidos: "+type+"."+id);
        for(const [field,value] of Object.entries(attributes)){
          if(!own(RANGES[type],field)) throw new Error("Atributo nao suportado: "+type+"."+id+"."+field);
          validNumber(value,RANGES[type][field],type+"."+id+"."+field);
        }
      }
    }
  }
  return mod;
}
function validNumber(n,[min,max],label){
  if(typeof n!=="number"||!Number.isFinite(n)||n<min||n>max) throw new Error("Valor fora do intervalo "+min+".."+max+": "+label);
  if(Number.isInteger(min)&&Number.isInteger(max)&&!Number.isInteger(n)) throw new Error("Numero inteiro exigido: "+label);
}
export function buildPlan(manifests,{config,items,aiTypes}){
  if(manifests.length>32) throw new Error("Limite de 32 mods ativos.");
  const plan=[],written=new Map(),seen=new Set();
  for(const raw of manifests){
    const mod=validateManifest(raw);
    if(seen.has(mod.id)) throw new Error("Mod repetido: "+mod.id);
    seen.add(mod.id);
    for(const [group,definitions] of Object.entries(mod.changes)){
      if(group==="world"){
        for(const [field,value] of Object.entries(definitions)){
          if(!own(config,field)||typeof config[field]!=="number") throw new Error("Regra ausente no motor: "+field);
          register(mod.id,"world."+field,config,field,value);
        }
        continue;
      }
      for(const [id,fields] of Object.entries(definitions)){
        const number=Number(id);
        const target=group==="animals"?aiTypes[number]:group==="weapons"?items.weapons[number]:group==="structures"?items.list[number]:config.server.animalSpawnPlan.find(x=>x.index===number);
        if(!target) throw new Error("Indice inexistente no motor: "+group+"."+id);
        for(const [field,value] of Object.entries(fields)){
          if(!own(target,field)||typeof target[field]!=="number") throw new Error("Atributo nao existente na referencia: "+group+"."+id+"."+field);
          register(mod.id,group+"."+id+"."+field,target,field,value);
        }
      }
    }
  }
  return plan;
  function register(mod,path,target,field,value){
    if(written.has(path)) throw new Error("Conflito: "+path+" alterado por "+written.get(path)+" e "+mod);
    written.set(path,mod);
    plan.push({mod,path,from:target[field],to:value,target,field});
  }
}
export function applyPlan(plan){
  // Called only after every mod was parsed and validated; never partially mutate.
  for(const step of plan) step.target[step.field]=step.to;
  return plan.map(({mod,path,from,to})=>({mod,path,from,to}));
}
export function summary(plan){return plan.map(({mod,path,from,to})=>({mod,path,from,to}));}
