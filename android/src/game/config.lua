-- Moo-Quest Lua values transcribed from al007ex/moomoo-clone
-- shared/config.js @ 06f7c1ca965a7628671676c8d9a7efd3997bb5e7
-- These are the authoritative reference values for world generation.
local C = {
  mapScale = 14400,
  -- Moo-Quest bundled Node shared/config.js uses the normal gathering economy.
  -- These flags must follow OUR running server, not the archived sandbox demo.
  inSandbox = false,
  unlimitedResources = false,
  unlimitedAmount = 1000000,
  maxPlayers = 40,
  maxPlayersHard = 50,
  gatherAngle = math.pi/2.6,
  colGrid = 10,
  areaCount = 7,
  treesPerArea = 9,
  bushesPerArea = 3,
  totalRocks = 32,
  goldOres = 7,
  riverWidth = 724,
  riverPadding = 114,
  waterCurrent = 0.0011,
  waveSpeed = 0.0001,
  waveMax = 1.3,
  treeScales = {150,160,165,175},
  bushScales = {80,85,95},
  rockScales = {80,85,90},
  snowBiomeTop = 2400,
  snowSpeed = 0.75,
  -- Exact labels and HUD constants from shared/config.js.
  nameY = 34,
  healthBarWidth = 50,
  healthBarPad = 4.5,
  deathFadeout = 3000, -- shared/config.js, CSS #diedText duration (ms)
  crownIconScale = 60,
  crownPad = 35,
  gatherWiggle = 10,
  cowNames = {
    "Sid", "Steph", "Bmoe", "Romn", "Jononthecool", "Fiona",
    "Vince", "Nathan", "Nick", "Flappy", "Ronald", "Otis",
    "Pepe", "Mc Donald", "Theo", "Fabz", "Oliver", "Jeff",
    "Jimmy", "Helena", "Reaper", "Ben", "Alan", "Naomi",
    "XYZ", "Clever", "Jeremy", "Mike", "Destined", "Stallion",
    "Allison", "Meaty", "Sophia", "Vaja", "Joey", "Pendy",
    "Murdoch", "Theo", "Jared", "July", "Sonia", "Mel",
    "Dexter", "Quinn", "Milky"
  },
  playerScale = 35,
  playerSpeed = 0.0016,
  playerDecel = 0.993,
  collisionDepth = 6,
  serverUpdateRate = 9,
  clientSendRate = 5,
  resourceTypes = {"wood","food","stone","points"},
  secretPool = {
    gorgeX0 = -1500,
    gorgeHalf = 520,
    pool = {
      {-2500,7200,1150},{-3300,6750,750},{-3200,7750,700},
      {-1700,6900,600},{-1800,7550,600}
    },
    waterfall = {x=-3860,y=7250,half=210},
    shallows = {start=-1500,length=320}
  }
}
C.server = {
  animalSpawnPlan = {
    {index=0,desired=10},
    {index=1,desired=8},
    {index=12,desired=6},
    {index=2,desired=5},
    {index=3,desired=2},
    {index=4,desired=6,area="snow"},
    {index=5,desired=4,area="river"},
    {index=9,desired=4},
    {index=10,desired=2,area="snow"},
    {index=6,desired=1,positions={{xRatio=0.5,yRatio=0.93}}},
    {index=7,desired=1,positions={{xRatio=0.18,yRatio=0.22}}},
    {index=8,desired=1,positions={{xRatio=0.78,yRatio=0.08}}},
    {index=11,desired=1,area="secret",positions={{x=-2500,y=7200}}}
  },
  cactusDamage=20,
  leaderboardRate=1000,
  statsRate=2000
}
return C
