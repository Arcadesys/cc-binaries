-- GUI CraftOS-PC only: monitor emulation is unavailable in --headless mode.
assert(periphemu,'Run this integration check in CraftOS-PC')
local root=fs.getDir(shell.getRunningProgram())
local env=setmetatable({}, {__index=_ENV})
env.require,env.package=require('cc.require').make(env,root)
fs.makeDir('/results')
local lines={}
env.print=function(...)
  local parts={...}; for i=1,#parts do parts[i]=tostring(parts[i]) end
  lines[#lines+1]=table.concat(parts,' ')
end
local ok,err=pcall(env.require,'tests.runtime_scenarios')
lines[#lines+1]=ok and 'PASS runtime scenarios' or ('FAIL '..tostring(err))
local log=assert(fs.open('/results/runtime.txt','w'))
log.write(table.concat(lines,'\n')); log.close()
term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear();term.setCursorPos(1,1)
for _,line in ipairs(lines) do print(line) end
