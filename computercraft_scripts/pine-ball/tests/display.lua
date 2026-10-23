-- Real Pine3D drawing at supported sizes; every touch target stays on screen.
local App = require("lib.app")
local render = require("lib.render")
local ui = require("lib.ui")
local original = term.current()
for _, size in ipairs({{39, 19}, {51, 19}, {82, 40}}) do
  local target = window.create(original, 1, 1, size[1], size[2], false)
  term.redirect(target)
  local r = render.new(target)
  local app = App.new({seed = 2})
  local seen = {}
  local function check()
    r:draw(app:view())
    for _, b in ipairs(r.buttons) do
      assert(b.x >= 1 and b.y >= 1 and b.x + b.w - 1 <= size[1] and b.y + b.h - 1 <= size[2], "target out of bounds " .. b.id)
      assert(b.h >= 2, "target too short")
      seen[b.id] = true
    end
  end
  check(); app:action("start"); check(); app:action("swing"); check()
  for _ = 1, 50 do app:advance(20) end; check()
  app:action("help"); check(); app:action("help")
  local duel = App.new({mode = "duel"}); duel:action("start"); duel:action("swing"); app = duel; check()
  for _, id in ipairs({"mode", "innings_up", "innings_down", "start", "swing", "aim_x", "aim_y", "pause", "throw", "pitch_cycle", "quit", "restart"}) do
    assert(seen[id], "missing control " .. id)
  end
  r:close(); term.redirect(original)
end
assert(ui.layout(20, 10, "PITCH").small)
-- The scoreboard keeps the bases visible at the minimum width, even with big numbers.
local late = {score = {light = 12, dark = 10}, bases = {first = "a", third = "b"}, inning = 9, half = "bottom", balls = 3, strikes = 2, outs = 2}
for _, w in ipairs({39, 30, 26}) do
  local line = ui.scoreLine(late, w)
  assert(#line <= w and line:sub(-3) == "1-3", "bases cut at " .. w .. ": " .. line)
end
assert(ui.scoreLine({}, 51) == "LIGHT 0  DARK 0 | TOP 1 | B0 S0 O0 | ---")
-- Touch players can reach setup from the final screen.
local finalIds = {}
for _, b in ipairs(ui.layout(39, 19, "FINAL")) do finalIds[b.id] = true end
assert(finalIds.restart and finalIds.swing and finalIds.quit, "final screen controls")
local wrapped = ui.wrap("one two three four", 9)
assert(table.concat(wrapped, "|") == "one two|three|four", "wrap: " .. table.concat(wrapped, "|"))
for _, l in ipairs(ui.wrap("Hold arrows while swinging: LEFT/RIGHT aim the field, UP lifts, DOWN chops.", 39)) do assert(#l <= 39) end
return true
