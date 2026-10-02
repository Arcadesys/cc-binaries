local loadModule=require
if shell and fs and shell.getRunningProgram():match('tests/run.lua$') then
 local root=fs.getDir(fs.getDir(shell.getRunningProgram()))
 local env=setmetatable({}, {__index=_ENV});env.require,env.package=require('cc.require').make(env,root);loadModule=env.require
end
local names={'tests.furball','tests.plays','tests.input','tests.app','tests.display','tests.sound'}
for _,name in ipairs(names) do assert(loadModule(name)==true,name);print('PASS '..name) end
print('PASS '..#names..' core modules')
