-- Standalone CraftOS entry; also works as a module or under a host Lua runner.
local loadModule=require
if shell and fs and shell.getRunningProgram():match('tests/run.lua$') then
  local root=fs.getDir(fs.getDir(shell.getRunningProgram()))
  local env=setmetatable({}, {__index=_ENV})
  env.require,env.package=require('cc.require').make(env,root)
  loadModule=env.require
end

local tests = { "tests.furball", "tests.physics", "tests.rules", "tests.input", "tests.app" }
local passed = 0
for _, name in ipairs(tests) do
  local ok, result = pcall(loadModule, name)
  if not ok then error(name .. " failed: " .. tostring(result), 0) end
  if result ~= true then error(name .. " did not return true", 0) end
  passed = passed + 1
  print("PASS " .. name)
end
print("PASS " .. passed .. " test modules")
