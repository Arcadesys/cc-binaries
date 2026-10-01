local args={...}
local base=fs.getDir(shell.getRunningProgram())
local env=setmetatable({}, {__index=_ENV})
env.require,env.package=require("cc.require").make(env,base)
-- The arcade installer (cc-arcade/get.lua) shares one Pine3D: use it when vendor/ is absent.
env.package.path=env.package.path..";/"..fs.combine(base,"..","derby").."/?.lua"
local require=env.require
local options={}
local i=1
while i<=#args do
  if args[i]=="--terminal" then options.terminal=true
  elseif args[i]=="--monitor" then i=i+1;options.monitor=assert(args[i],"--monitor needs a name")
  elseif args[i]=="--solo" then options.solo=true
  elseif args[i]=="--host" then options.solo=false
  elseif args[i]=="--join" then
    -- An optional host computer ID follows; without one the host is found by rednet lookup.
    if args[i+1] and tonumber(args[i+1]) then i=i+1;options.join=args[i] else options.join=false end
  elseif args[i]=="--log" then i=i+1;options.log=assert(args[i],"--log needs a path")
  else error("Unknown option: "..args[i].."\nUsage: face [--host|--join [id]|--solo] [--terminal|--monitor name]") end
  i=i+1
end
local log
if options.log then
  log=assert(fs.open(options.log,"w"))
  options.record=function(kind,data,app)
    if kind=="tick" or kind=="snap" then return end
    log.writeLine(textutils.serializeJSON({kind=kind,data=data,phase=app.session.phase}))
    log.flush()
  end
end
local ok,err=pcall(function() require("lib.app").run(options) end)
if log then log.close() end
if not ok then printError(err) else print("Pine Face closed.") end
