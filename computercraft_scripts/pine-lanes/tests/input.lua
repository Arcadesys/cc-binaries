local input=require("lib.input")
local oldKeys=keys
local function check(value,message) assert(value,message) end
local function tests()
  keys={up=1,down=2,left=3,right=4,space=5,tab=6,f=7,h=8,p=9,s=10,r=11,backspace=12,one=13,two=14,three=15,four=16}
  input._resetDebounce()
  check(input.action({"key",keys.space,false,time=0},nil,nil)=="primary","space primary")
  check(input.action({"key",keys.space,true,time=.1},nil,nil)==nil,"held primary ignored")
  check(input.action({"key",keys.left,false,time=.2},nil,nil)=="adjust_down","left adjusts")
  check(input.action({"key",keys.up,false,time=.3},nil,nil)=="select_prev","up selects previous")
  local buttons={{id="roll",x=2,y=3,w=8,h=2}}
  check(input.action({"monitor_touch","left",3,3,time=1},buttons,"left")=="roll","selected monitor hit")
  check(input.action({"monitor_touch","right",3,3,2},buttons,"left")==nil,"foreign monitor ignored")
  check(input.action({"monitor_touch","left",3,3,3},buttons,nil)==nil,"monitor event without selected monitor ignored")
  check(input.action({"mouse_click",1,3,3,time=4},buttons,"left")==nil,"terminal mouse ignored on monitor")
  check(input.action({"mouse_click",1,3,3,time=1.2},buttons,nil)==nil,"primary debounce")
  check(input.action({"mouse_click",1,3,3,time=5},buttons,nil)=="roll","primary after debounce")
  check(input.action({"key",keys.backspace,false,time=6},nil,nil)=="quit","backspace quits")
end
local ok,err=pcall(tests)
keys=oldKeys
if not ok then error(err,0) end
return true
