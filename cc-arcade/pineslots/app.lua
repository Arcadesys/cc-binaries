-- Entry: pineslots [setup | --demo] [--terminal | --monitor NAME]
local M={}
function M.run(args)
 args=args or {}
 if args[1]=='setup' then return require('pineslots.controls').setup() end
 require('casino.app').run(args,'pineslots','PINE SLOTS',function(t,wallet)
  require('pineslots.machine').run({target=t,wallet=wallet})
 end)
end
return M
