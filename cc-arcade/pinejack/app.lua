-- Entry: pinejack [--demo] [--terminal | --monitor NAME]
local M={}
function M.run(args)
 require('casino.app').run(args or {},'pinejack','PINE JACK',function(t,wallet)
  require('pinejack.game').run({target=t,wallet=wallet})
 end)
end
return M
