-- Live dispatcher smoke: real timers, queued keys, full redraw path, clean restoration.
local App = require("lib.app")
local original = term.current()
local log, final = {}, nil
parallel.waitForAny(function()
  final = App.run({terminal = true, seed = 21, record = function(kind, data, app)
    if kind ~= "frame" and kind ~= "input" then log[#log + 1] = kind .. ":" .. app.phase end
  end})
end, function()
  local function key(name, held) os.queueEvent("key", keys[name], held or false); sleep(.1) end
  sleep(.3); key("enter"); sleep(.3); key("space")
  for _ = 1, 6 do
    sleep(1.05); key("space")
  end
  sleep(3); key("p"); sleep(.2); key("backspace")
  sleep(1); os.queueEvent("terminate")
end)
assert(term.current() == original, "terminal not restored")
local commits = 0
for _, l in ipairs(log) do if l:match("^commit") then commits = commits + 1 end end
assert(commits >= 2, "live loop committed too few pitches: " .. table.concat(log, " "))
print("PASS live loop: " .. commits .. " commits, " .. #log .. " events")
return true
