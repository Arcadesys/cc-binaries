-- Daily Wordle: the server's word of the day, a Minecraft word, in six guesses.
-- wordle [--terminal | --monitor NAME]
local args={...}
local t
for i,a in ipairs(args) do
 if a=='--terminal' then t=term.current() end
 if a=='--monitor' then t=assert(peripheral.wrap(args[i+1] or ''),'No monitor named '..tostring(args[i+1])); t.setTextScale(1) end
end
t=t or require('derby.ui').target()
local restore=require('derby.palette').save(t)
local ok,err=pcall(require('wordle.app').run,{target=t,args=args})
restore()
t.setBackgroundColor(colors.black); t.setTextColor(colors.white); t.clear(); t.setCursorPos(1,1)
if not ok then error(err,0) end
