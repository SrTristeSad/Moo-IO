-- Headless Android-specific menu contract: real bot controls must not be hidden.
package.path="./?.lua;./?/init.lua;"..package.path
love={
  system={getOS=function() return "Android" end},
  graphics={getDimensions=function() return 1280,720 end}
}
local Home=require("src.game.mooio_home")
local home=Home.new()
assert(home.screen=="home" and not home.botsEnabled)
assert(home:click(128,311)=="play_tab")
assert(home.screen=="play" and not home.hosting)
assert(home:click(175,439)=="bots_toggle")
assert(home.botsEnabled and home.botCount==2)
assert(home:click(550,496)=="bots_count" and home.botCount==3)
assert(home:click(220,496)=="bots_count" and home.botCount==2)
assert(home:click(176,559)=="create",
  "Creating a local Android room must honor user-selectable bots")
home.hosting=true
assert(home:click(175,439)=="copy" and home.botCount==2,
  "The running-room invite replaces bot controls without changing active bots")
home.hosting=false
home.screen="home"
assert(home:click(190,480)=="settings_tab")
assert(home:click(830,418)=="hud_changed")
assert(home.hudScale>1.20)
assert(home:click(600,560)=="controls_tab")
assert(home.screen=="controls")
assert(home:click(835,272)=="hud_changed" and home.moveScale>1)
assert(home:click(836,354)=="hud_changed" and home.fireScale>1)
assert(home:click(834,434)=="hud_changed" and home.deadzone>.15)
assert(home:click(613,536)=="hud_changed" and home.deadzone==.15)
assert(home:click(1108,112)=="back" and home.screen=="settings")
print("MOO IO ANDROID HOME BOTS + FLOATING CONTROL OPTIONS PASS")
