local input = require("lib.input")

local oldKeys, oldClock = keys, os.clock
keys = {left=1,right=2,up=3,down=4,q=5,e=6,space=7,tab=8,f=9,h=10,p=11,r=12,backspace=13,s=14,a=15,c=16,enter=17}
local now=1
os.clock=function() return now end
local buttons={
  {id="aim_left",x=1,y=11,w=12,h=3},
  {id="swing",x=1,y=17,w=25,h=3},
}

assert(input.action({"key",keys.left},buttons)=="aim_left")
assert(input.action({"key",keys.space},buttons)=="swing")
assert(input.action({"key",keys.s},buttons)=="skip")
assert(input.action({"key",keys.a},buttons)=="aim_cup")
assert(input.action({"key",keys.c},buttons)=="club_next")
assert(input.action({"key",keys.enter},buttons)=="swing")
assert(input.action({"key",keys.space,true},buttons)==nil) -- repeated key-down
assert(input.action({"key",keys.backspace},buttons)=="quit")
assert(input.action({"monitor_touch","right_monitor",1,12},buttons,"right_monitor")=="aim_left")
assert(input.action({"monitor_touch","left_monitor",1,12},buttons,"right_monitor")==nil)
assert(input.action({"monitor_touch","right_monitor",1,18},buttons,nil)==nil)
assert(input.action({"mouse_click",1,1,12},buttons)=="aim_left")
assert(input.action({"mouse_click",1,1,12},buttons,"right_monitor")==nil)

-- Two rapid touch activations of the primary swing target count once.
assert(input.action({"monitor_touch","right_monitor",2,18},buttons,"right_monitor")=="swing")
now=now+0.1
assert(input.action({"monitor_touch","right_monitor",2,18},buttons,"right_monitor")==nil)

keys,os.clock=oldKeys,oldClock
return true
