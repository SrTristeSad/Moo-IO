-- Packet names and public server-side semantics from al007ex/moomoo-clone.
-- This is a reference inventory, NOT a working transport implementation.
local P = {}
P.c2s = {
  M="spawn", D="aim", ["9"]="move", e="resetMove", F="mouse",
  z="selectItem", H="upgrade", K="toggle", L="createTribe",
  N="leaveTribe", b="requestJoin", P="answerJoinRequest",
  Q="kickMember", c="store", ["6"]="chat", S="mapPing",
  ["0"]="ping", T="telemetry", R="reportOrStaff",
  A="adminCommand", V="watchStats", I="anonymousMode", U="mapPointPing", Y="categoryRankingRequest"
}
P.s2c = {
  A="initData", B="disconnect", C="setupGame", D="addPlayer",
  E="removePlayer", a="updatePlayers", G="leaderboard",
  H="loadObjects", I="updateAnimals", J="animalAttack",
  K="gatherAnimation", L="wiggle", M="turretShoot",
  N="playerValue", O="health", P="killPlayer",
  Q="killObject", R="killObjects", S="itemCount",
  T="age", U="upgrades", V="items", X="addProjectile",
  Y="removeProjectile", Z="shutdownNotice", g="addTribe",
  ["1"]="deleteTribe", ["2"]="joinRequest",
  ["3"]="setTribe", ["4"]="tribeMembers",
  ["5"]="storeUpdate", ["6"]="chat", ["7"]="minimap",
  ["8"]="showText", ["9"]="mapPing", ["0"]="pong",
  W="effect", F="stats", p="profile", q="integrityProbes",
  r="updateCountdown", m="playerDive", n="categoryLeaderboard"
}
P.transport = {
  handshake="io-init",
  modeKeyed=1,
  macLength=6,
  tableSize=128,
  maxPacketBytes=2048,
  maxPayloadItems=16
}
-- Exact order from server/src/protocol/constants.js (required for per-session IDs).
P.c2sList={"M","D","9","e","F","z","H","K","L","N","b","P","Q","c","6","S","0","T","R","A","V","I","U","Y"}
P.s2cList={"A","B","C","D","E","a","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","X","Y","Z","g","1","2","3","4","5","6","7","8","9","0","W","F","p","q","r","m","n"}
return P
