-- Keyboard and touch to actions. Batter: Space swings, arrows held to aim (furball:
-- left/right field, up lift, down chop). Duel pitcher shares the keyboard: 1-4 pitch
-- type, WASD location, E throws. Repeated key-downs never re-swing.
local input = {}
local function keyMap()
  local k = keys or {}
  local map = {}
  local function bind(name, action) if k[name] ~= nil then map[k[name]] = action end end
  bind("space", "swing"); bind("enter", "start")
  bind("left", "left"); bind("right", "right"); bind("up", "up"); bind("down", "down")
  bind("one", "pitch_1"); bind("two", "pitch_2"); bind("three", "pitch_3"); bind("four", "pitch_4")
  bind("w", "pitch_up"); bind("a", "pitch_left"); bind("s", "pitch_down"); bind("d", "pitch_right")
  bind("e", "throw"); bind("m", "mode"); bind("h", "help"); bind("p", "pause"); bind("r", "restart")
  bind("backspace", "quit")
  return map
end
local function hit(buttons, x, y)
  for i = 1, #(buttons or {}) do
    local b = buttons[i]
    if x >= b.x and y >= b.y and x < b.x + b.w and y < b.y + b.h then return b.id end
  end
end
function input.action(event, buttons, monitorName)
  if type(event) ~= "table" then return nil end
  local name = event[1]
  if name == "key" then
    local action = keyMap()[event[2]]
    if action == "left" or action == "right" or action == "up" or action == "down" then return "hold_" .. action end
    if event[3] then return nil end -- held/repeat events never retrigger
    return action
  elseif name == "key_up" then
    local action = keyMap()[event[2]]
    if action == "left" or action == "right" or action == "up" or action == "down" then return "release_" .. action end
  elseif name == "monitor_touch" then
    if monitorName and event[2] == monitorName then return hit(buttons, event[3], event[4]) end
  elseif name == "mouse_click" then
    if not monitorName then return hit(buttons, event[3], event[4]) end
  end
  return nil
end
return input
