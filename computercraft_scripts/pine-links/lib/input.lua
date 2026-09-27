local input = {}
local touchSwingAt = -1

local function keyAction(key)
  if not keys then return nil end
  local map = {}
  local function bind(name, action)
    local code=keys[name]
    if code then map[code]=action end
  end
  bind("left","aim_left"); bind("right","aim_right")
  bind("up","power_up"); bind("down","power_down")
  bind("q","club_prev"); bind("e","club_next")
  bind("space","swing"); bind("tab","view"); bind("f","fine")
  bind("h","help"); bind("p","pause"); bind("r","restart")
  bind("escape","quit"); bind("backspace","quit"); bind("s","skip")
  return map[key]
end

local function unpackEvent(event)
  if type(event) == "table" then
    return event.name or event[1], event.side or event.monitor or event[2],
      event.x or event[3], event.y or event[4], event.key or event[2]
  end
  return event
end

local function hit(buttons, x, y)
  if type(buttons) ~= "table" then return nil end
  for i = 1, #buttons do
    local b = buttons[i]
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then return b.id end
  end
end

function input.action(event, buttons, monitorName)
  local name, side, x, y, key = unpackEvent(event)
  if name == "key" then
    if type(event) == "table" and (event.repeated or event[3] == true) then
      local action=keyAction(key)
      if action=="swing" or action=="restart" or action=="quit" then return nil end
    end
    return keyAction(key)
  end
  if name == "monitor_touch" then
    -- Touch events are meaningful only for the selected monitor target.
    if not monitorName or side ~= monitorName then return nil end
    local id = hit(buttons, x, y)
    if id == "swing" then
      local now = os and os.clock and os.clock() or 0
      if now - touchSwingAt < 0.3 then return nil end
      touchSwingAt = now
    end
    return id
  end
  -- Computer terminal mouse input has its own event shape; monitor taps do not.
  if name == "mouse_click" and not monitorName then return hit(buttons, x, y) end
  return nil
end

return input
