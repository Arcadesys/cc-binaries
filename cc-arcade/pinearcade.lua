-- Pine Arcade: a Pine3D menu of every game installed beside it (get all), and the place
-- to choose what this computer boots into.
-- pinearcade [--terminal | --monitor NAME]
local args={...}
require('pinearcade.app').run({dir=fs.getDir(shell.getRunningProgram()),target=require('casino.app').target(args),args=args})
