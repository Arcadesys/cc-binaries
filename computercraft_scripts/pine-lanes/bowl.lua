local args={...}
local base=fs.getDir(shell.getRunningProgram())
local env=setmetatable({}, {__index=_ENV})
env.require,env.package=require('cc.require').make(env,base)
-- The arcade installer (cc-arcade/get.lua) shares one Pine3D: use it when vendor/ is absent.
env.package.path=env.package.path..';/'..fs.combine(base,'..','derby')..'/?.lua'
local require=env.require
local options={}
local i=1
while i<=#args do
  if args[i]=='--terminal' then options.terminal=true
  elseif args[i]=='--monitor' then i=i+1; options.monitor=assert(args[i],'--monitor needs a name')
  elseif args[i]=='--diagnostic' then options.diagnostic=true
  elseif args[i]=='--seed' then i=i+1; options.seed=assert(tonumber(args[i]),'--seed needs a number')
  elseif args[i]=='--log' then i=i+1; options.log=assert(args[i],'--log needs a path')
  else error('Unknown option: '..args[i]) end
  i=i+1
end
local log
if options.log then
  log=assert(fs.open(options.log,'w'))
  options.record=function(kind,data,app)
    local receipt={kind=kind,data=data,phase=app.phase,
      player=app.match.currentPlayer,frame=app.match.frame,ball=app.match.ballNumber,time=os.epoch('utc')}
    if kind=='resolved' or kind=='exit' then
      receipt.complete=app.match.complete;receipt.summary=app.rollSummary;receipt.scorecards=app:view().scorecards
    end
    log.writeLine(textutils.serializeJSON(receipt)); log.flush()
  end
end
local ok,err=pcall(function() require('lib.app').run(options) end)
if log then log.close() end
if not ok then printError(err) else print('Pine Lanes closed.') end
