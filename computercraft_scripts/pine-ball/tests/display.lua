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
  for _, id in ipairs({"mode", "innings_up", "innings_down", "start", "swing", "aim_x", "aim_y", "pause", "throw", "pitch_cycle", "quit"}) do
    assert(seen[id], "missing control " .. id)
  end
  r:close(); term.redirect(original)
end
assert(ui.layout(20, 10, "PITCH").small)
return true
