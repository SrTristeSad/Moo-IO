-- Exact purchasable catalog transcribed from shared/config/store.js (Apache-licensed reconstructed server).
-- Values must stay synced: no invented hats, accessories or purchase prices.
local Store={}
Store.hats={
  {id=45,name="Shame!",price=0,desc="hacks are for losers",topSprite=false,dontSell=true,earned=false},
  {id=51,name="Moo Cap",price=0,desc="coolest mooer around",topSprite=false,dontSell=false,earned=false},
  {id=50,name="Apple Cap",price=0,desc="apple farms remembers",topSprite=false,dontSell=false,earned=false},
  {id=28,name="Moo Head",price=0,desc="no effect",topSprite=false,dontSell=false,earned=false},
  {id=29,name="Pig Head",price=0,desc="no effect",topSprite=false,dontSell=false,earned=false},
  {id=30,name="Fluff Head",price=0,desc="no effect",topSprite=false,dontSell=false,earned=false},
  {id=36,name="Pandou Head",price=0,desc="no effect",topSprite=false,dontSell=false,earned=false},
  {id=37,name="Bear Head",price=0,desc="no effect",topSprite=false,dontSell=false,earned=false},
  {id=38,name="Monkey Head",price=0,desc="no effect",topSprite=false,dontSell=false,earned=false},
  {id=44,name="Polar Head",price=0,desc="no effect",topSprite=false,dontSell=false,earned=false},
  {id=35,name="Fez Hat",price=0,desc="no effect",topSprite=false,dontSell=false,earned=false},
  {id=42,name="Enigma Hat",price=0,desc="join the enigma army",topSprite=false,dontSell=false,earned=false},
  {id=43,name="Blitz Hat",price=0,desc="hey everybody i'm blitz",topSprite=false,dontSell=false,earned=false},
  {id=49,name="Bob XIII Hat",price=0,desc="like and subscribe",topSprite=false,dontSell=false,earned=false},
  {id=57,name="Pumpkin",price=50,desc="Spooooky",topSprite=false,dontSell=false,earned=false},
  {id=8,name="Bummle Hat",price=100,desc="no effect",topSprite=false,dontSell=false,earned=false},
  {id=2,name="Straw Hat",price=500,desc="no effect",topSprite=false,dontSell=false,earned=false},
  {id=15,name="Winter Cap",price=600,desc="allows you to move at normal speed in snow",topSprite=false,dontSell=false,earned=false},
  {id=5,name="Cowboy Hat",price=1000,desc="no effect",topSprite=false,dontSell=false,earned=false},
  {id=4,name="Ranger Hat",price=2000,desc="no effect",topSprite=false,dontSell=false,earned=false},
  {id=18,name="Explorer Hat",price=2000,desc="no effect",topSprite=false,dontSell=false,earned=false},
  {id=31,name="Flipper Hat",price=2500,desc="have more control while in water",topSprite=false,dontSell=false,earned=false},
  {id=1,name="Marksman Cap",price=3000,desc="increases arrow speed and range",topSprite=false,dontSell=false,earned=false},
  {id=10,name="Bush Gear",price=3000,desc="allows you to disguise yourself as a bush",topSprite=false,dontSell=false,earned=false},
  {id=48,name="Halo",price=3000,desc="no effect",topSprite=false,dontSell=false,earned=false},
  {id=6,name="Soldier Helmet",price=4000,desc="reduces damage taken but slows movement",topSprite=false,dontSell=false,earned=false},
  {id=59,name="Scout Hat",price=3500,desc="move faster but take more damage",topSprite=false,dontSell=false,earned=false},
  {id=23,name="Anti Venom Gear",price=4000,desc="makes you immune to poison",topSprite=false,dontSell=false,earned=false},
  {id=13,name="Medic Gear",price=5000,desc="slowly regenerates health over time",topSprite=false,dontSell=false,earned=false},
  {id=9,name="Miners Helmet",price=5000,desc="earn 1 extra gold per resource",topSprite=false,dontSell=false,earned=false},
  {id=32,name="Musketeer Hat",price=5000,desc="reduces cost of projectiles",topSprite=false,dontSell=false,earned=false},
  {id=7,name="Bull Helmet",price=6000,desc="increases damage done but drains health",topSprite=false,dontSell=false,earned=false},
  {id=22,name="Emp Helmet",price=6000,desc="turrets won't attack but you move slower",topSprite=false,dontSell=false,earned=false},
  {id=12,name="Booster Hat",price=6000,desc="increases your movement speed",topSprite=false,dontSell=false,earned=false},
  {id=26,name="Barbarian Armor",price=8000,desc="knocks back enemies that attack you",topSprite=false,dontSell=false,earned=false},
  {id=60,name="Frost Helm",price=7000,desc="normal speed in snow and reduces damage taken",topSprite=false,dontSell=false,earned=false},
  {id=61,name="Crab Shell",price=0,desc="dropped by the Crab King. reflects damage and reduces damage taken",topSprite=false,dontSell=true,earned=true},
  {id=21,name="Plague Mask",price=10000,desc="melee attacks deal poison damage",topSprite=false,dontSell=false,earned=false},
  {id=46,name="Bull Mask",price=10000,desc="bulls won't target you unless you attack them",topSprite=false,dontSell=false,earned=false},
  {id=14,name="Windmill Hat",price=10000,desc="generates points while worn",topSprite=true,dontSell=false,earned=false},
  {id=11,name="Spike Gear",price=10000,desc="deal damage to players that damage you",topSprite=true,dontSell=false,earned=false},
  {id=53,name="Turret Gear",price=10000,desc="you become a walking turret",topSprite=true,dontSell=false,earned=false},
  {id=20,name="Samurai Armor",price=12000,desc="increased attack speed and fire rate",topSprite=false,dontSell=false,earned=false},
  {id=58,name="Dark Knight",price=12000,desc="restores health when you deal damage",topSprite=false,dontSell=false,earned=false},
  {id=27,name="Scavenger Gear",price=15000,desc="earn double points for each kill",topSprite=false,dontSell=false,earned=false},
  {id=40,name="Tank Gear",price=15000,desc="increased damage to buildings but slower movement",topSprite=false,dontSell=false,earned=false},
  {id=52,name="Thief Gear",price=15000,desc="steal half of a players gold when you kill them",topSprite=false,dontSell=false,earned=false},
  {id=55,name="Bloodthirster",price=20000,desc="Restore Health when dealing damage. And increased damage",topSprite=false,dontSell=false,earned=false},
  {id=56,name="Assassin Gear",price=20000,desc="Go invisible when not moving. Can't eat. Increased speed",topSprite=false,dontSell=false,earned=false},
}
Store.accessories={
  {id=12,name="Snowball",price=1000,desc="half the snow slowdown",topSprite=false,dontSell=false,earned=false},
  {id=9,name="Tree Cape",price=1000,desc="1 extra wood per hit on a tree",topSprite=false,dontSell=false,earned=false},
  {id=10,name="Stone Cape",price=1000,desc="1 extra stone per hit on a rock",topSprite=false,dontSell=false,earned=false},
  {id=3,name="Cookie Cape",price=1500,desc="1 extra food per hit on a bush or cactus",topSprite=false,dontSell=false,earned=false},
  {id=8,name="Cow Cape",price=2000,desc="1.5x gold and food from cows",topSprite=false,dontSell=false,earned=false},
  {id=11,name="Monkey Tail",price=2000,desc="Super speed but reduced damage",topSprite=false,dontSell=false,earned=false},
  {id=17,name="Apple Basket",price=3000,desc="slowly regenerates health over time",topSprite=false,dontSell=false,earned=false},
  {id=6,name="Winter Cape",price=3000,desc="no snow slowdown",topSprite=false,dontSell=false,earned=false},
  {id=4,name="Skull Cape",price=4000,desc="3x gold for killing the kill leader",topSprite=false,dontSell=false,earned=false},
  {id=5,name="Dash Cape",price=5000,desc="5% faster",topSprite=false,dontSell=false,earned=false},
  {id=2,name="Dragon Cape",price=6000,desc="5% more damage for 5s after hitting a player",topSprite=false,dontSell=false,earned=false},
  {id=1,name="Super Cape",price=8000,desc="after a kill: 5% more damage and 15% faster for 10s",topSprite=false,dontSell=false,earned=false},
  {id=7,name="Troll Cape",price=8000,desc="2x gold for kills by your spikes",topSprite=false,dontSell=false,earned=false},
  {id=14,name="Thorns",price=10000,desc="heals a little when you hit a player",topSprite=false,dontSell=false,earned=false},
  {id=15,name="Blockades",price=10000,desc="25% less damage from projectiles",topSprite=false,dontSell=false,earned=false},
  {id=20,name="Devils Tail",price=10000,desc="hits make players bleed for 2s",topSprite=false,dontSell=false,earned=false},
  {id=16,name="Sawblade",price=12000,desc="deal damage to players that damage you",topSprite=false,dontSell=false,earned=false},
  {id=13,name="Angel Wings",price=15000,desc="slowly regenerates health over time",topSprite=false,dontSell=false,earned=false},
  {id=19,name="Shadow Wings",price=15000,desc="increased movement speed",topSprite=false,dontSell=false,earned=false},
  {id=18,name="Blood Wings",price=20000,desc="restores health when you deal damage",topSprite=false,dontSell=false,earned=false},
  {id=21,name="Corrupt X Wings",price=20000,desc="deal damage to players that damage you",topSprite=false,dontSell=false,earned=false},
}
function Store.list(isAccessory)
  local result={}
  for _,item in ipairs(isAccessory and Store.accessories or Store.hats) do
    if not item.dontSell then result[#result+1]=item end
  end
  return result
end
function Store.byId(id,isAccessory)
  for _,item in ipairs(isAccessory and Store.accessories or Store.hats) do
    if item.id==id then return item end
  end
end
return Store
