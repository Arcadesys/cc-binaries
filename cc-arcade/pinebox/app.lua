-- Entry: pinebox [--demo] [--terminal | --monitor NAME]
local M={}
function M.run(args)
 require('casino.app').run(args or {},'pinebox','PINE SHUT THE BOX',function(t,wallet)
  require('pinebox.game').run({target=t,wallet=wallet})
 end)
end
return M
