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

-- Pulling the monitor mid-game falls back to the terminal, paused, instead of crashing.
-- CraftOS-PC only emulates monitors with --gui (tools/test_smoke.sh); headless runs skip this.
local name = "pineball_smoke"
if periphemu and pcall(periphemu.create, name, "monitor") and peripheral.isPresent(name) then
  local app, frames, onTerminal = nil, 0, 0
  parallel.waitForAny(function()
    app = App.run({monitor = name, seed = 4, record = function(kind, data, a)
      if kind == "frame" then
        frames = frames + 1
        if a.phase == "PAUSED" and a.message:find("detached", 1, true) then onTerminal = onTerminal + 1 end
      end
    end})
  end, function()
    sleep(.3); os.queueEvent("key", keys.space, false); sleep(.5)
    periphemu.remove(name); sleep(.6)
    os.queueEvent("key", keys.p, false); sleep(.3)
    os.queueEvent("key", keys.p, false); sleep(.3); os.queueEvent("key", keys.backspace, false)
    sleep(.5); os.queueEvent("terminate")
  end)
  assert(term.current() == original, "terminal not restored after detach")
  assert(onTerminal >= 1 and frames > 3, "no terminal fallback after detach")
  print("PASS monitor detach: " .. frames .. " frames")
else print("SKIP monitor detach: no emulated monitors") end
return true
