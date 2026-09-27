local args={...}
local base=fs.getDir(shell.getRunningProgram())
local env=setmetatable({}, {__index=_ENV})
env.require,env.package=require("cc.require").make(env,base)
local require=env.require
local options={}
local i=1
while i<=#args do
  if args[i]=="--terminal" then options.terminal=true
  elseif args[i]=="--monitor" then i=i+1;options.monitor=assert(args[i],"--monitor needs a name")
  elseif args[i]=="--log" then i=i+1;options.log=assert(args[i],"--log needs a path")
  else error("Unknown option: "..args[i]) end
  i=i+1
end
local log
if options.log then
  log=assert(fs.open(options.log,"w"))
  options.record=function(kind,data,app)
    log.writeLine(textutils.serializeJSON({kind=kind,data=data,floor=app.state.floor,
      turn=app.state.turn,phase=app.state.phase,hp=app.state.player.hp,
      gold=app.state.player.gold}))
    log.flush()
  end
end
local ok,err=pcall(function() require("lib.app").run(options) end)
if log then log.close() end
if not ok then printError(err) else print("Pine Dungeon closed.") end
