-- Same actual Pine3D/display/input path as the game, with a moving marker.
local args={...}
local path=fs.combine(fs.getDir(shell.getRunningProgram()),'golf.lua')
shell.run(path,'--diagnostic',table.unpack(args))
