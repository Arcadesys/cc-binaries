-- Plain Lua 5.3/5.4 runner for the core suites that need no CraftOS (used by CI).
-- Furball parity and the Pine3D display checks need CraftOS: run tools/test_craftos.sh.
-- Run from the game folder: lua tests/headless.lua
package.path = './?.lua;' .. package.path
colors = colors or {}
for i, name in ipairs({'white', 'orange', 'magenta', 'lightBlue', 'yellow', 'lime', 'pink', 'gray',
  'lightGray', 'cyan', 'purple', 'blue', 'brown', 'green', 'red', 'black'}) do
  colors[name] = colors[name] or math.floor(2 ^ (i - 1))
end
os.epoch = os.epoch or function() return math.floor(os.clock() * 1000) end
-- CC:Tweaked provides bit32 for lib/rng.lua; Lua 5.3+ has native unsigned-safe operators.
bit32 = bit32 or assert(load([[
  local M = 0xffffffff
  return {band = function(a, b) return (a & M) & (b & M) end, bor = function(a, b) return (a | b) & M end,
    bxor = function(a, b) return (a ~ b) & M end, rshift = function(a, n) return (a & M) >> n end}
]]))()
local names = {'tests.physics', 'tests.rules', 'tests.input', 'tests.sound', 'tests.app'}
for _, name in ipairs(names) do assert(require(name) == true, name); print('PASS ' .. name) end
print('PASS ' .. #names .. ' headless core modules')
