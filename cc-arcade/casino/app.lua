-- Shared launcher for the Pine3D casino games: display choice, palette restore and
-- live-or-exhibition wallet. Args: --terminal | --monitor NAME | --demo
local M={}
function M.target(args)
 for i,a in ipairs(args) do
  if a=='--terminal' then return term.current() end
  if a=='--monitor' then local m=assert(peripheral.wrap(args[i+1] or ''),'No monitor named '..tostring(args[i+1])); m.setTextScale(1); return m end
 end
 return require('derby.ui').target()
end
-- Live play needs this computer configured as a house station (house setup station ...).
function M.wallet(args,game,name)
 local w=require('casino.wallet')
 for _,a in ipairs(args) do if a=='--demo' or a=='demo' then return w.exhibition(name) end end
 local c=require('derby.config').read()
 if c and (c.role=='station' or c.role=='cashier') then return w.live(game,name) end
 return w.exhibition(name)
end
-- start(target, wallet) runs the game; the terminal and palette are restored afterwards.
function M.run(args,game,name,start)
 local t=M.target(args)
 local restore=require('derby.palette').save(t)
 local old=term.current()
 local ok,err=xpcall(function() start(t,M.wallet(args,game,name)) end,debug.traceback)
 term.redirect(old); restore()
 t.setBackgroundColor(colors.black); t.setTextColor(colors.white); t.clear(); t.setCursorPos(1,1)
 if not ok then error(err,0) end
end
return M
