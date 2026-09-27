local ui = {}

local function button(id, label, x, y, w, h)
  return { id = id, label = label, x = x, y = y, w = w, h = h }
end

-- Control targets occupy three character rows wherever the display allows it.
function ui.layout(w, h, phase)
  local out = {}
  local rowH = h < 24 and 2 or math.max(1, math.min(3, math.floor(h / 5)))
  -- Keep the same three-row action grid on smaller monitors; labels shorten
  -- naturally inside the narrower cells, so every touch action remains present.
  local cols = w >= 24 and 4 or 2
  local gap = 1
  local cellW = math.floor((w - gap * (cols - 1)) / cols)
  local rows = 3
  local startY = math.max(1, h - rowH * rows + 1)
  local function add(row, col, id, label, span)
    local x = (col - 1) * (cellW + gap) + 1
    local width = math.min(w - x + 1, cellW * (span or 1) + gap * ((span or 1) - 1))
    out[#out + 1] = button(id, label, x, startY + (row - 1) * rowH, width, rowH)
  end

  out.rows=rows
  if w < 39 or h < 19 then
    add(3,1,"quit","QUIT",cols)
    return out
  end

  if phase == "TITLE" then
    add(2, 1, "start", "START", cols)
    add(3, 1, "help", "HELP", cols)
  elseif phase == "SCORECARD" then
    add(2, 1, "restart", "RESTART", cols)
    add(3, 1, "quit", "QUIT", cols)
  elseif phase == "HELP" or phase == "PAUSED" then
    add(2, 1, "start", phase == "HELP" and "RESUME" or "RESUME", math.max(1, cols - 1))
    add(2, cols, "restart", "RESTART", 1)
    add(3, 1, "help", "HELP", 1)
    add(3, math.max(1, cols - 1), "quit", "QUIT", 2)
  elseif phase == "SIMULATE" or phase == "SHOT_PLAYBACK" then
    add(3, 1, "skip", "SKIP", cols)
  else
    -- AIM and diagnostics: all discrete adjustments and primary actions are visible.
    if cols == 4 then
      local labels = w >= 48
      add(1, 1, "aim_left", labels and "AIM LEFT" or "AIM-", 1); add(1, 2, "aim_right", labels and "AIM RIGHT" or "AIM+", 1)
      add(1, 3, "power_down", labels and "POWER -" or "PWR-", 1); add(1, 4, "power_up", labels and "POWER +" or "PWR+", 1)
      add(2, 1, "club_prev", labels and "CLUB -" or "CLB-", 1); add(2, 2, "club_next", labels and "CLUB +" or "CLB+", 1)
      add(2, 3, "fine", "FINE", 1); add(2, 4, "view", "VIEW", 1)
      add(3, 1, "swing", "SWING", 2); add(3, 3, "help", "HELP", 1); add(3, 4, "pause", "MENU", 1)
    else
      add(1, 1, "aim_left", "AIM -", 1); add(1, 2, "aim_right", "AIM +", 1)
      add(2, 1, "power_down", "PWR -", 1); add(2, 2, "power_up", "PWR +", 1)
      add(2, 3, "view", "VIEW", 1)
      add(3, 1, "swing", "SWING", 1); add(3, 2, "club_prev", "CLUB -", 1)
      add(3, 3, "club_next", "CLUB +", 1)
    end
  end
  return out
end

local function writeAt(t, x, y, s, fg, bg, maxW)
  if y < 1 or y > select(2, t.getSize()) or x > select(1, t.getSize()) then return end
  local w = math.min(maxW or #s, select(1, t.getSize()) - x + 1)
  s = tostring(s):sub(1, math.max(0, w))
  t.setCursorPos(x, y)
  t.setTextColor(fg); t.setBackgroundColor(bg)
  t.write(s .. string.rep(" ", math.max(0, w - #s)))
end

function ui.draw(t, view, buttons, sceneRows)
  local w, h = t.getSize()
  local white, black = colors.white, colors.black
  local bright = colors.yellow

  local rowY = math.max(1, h - math.min(3, math.floor(h / 5)) * 3 + 1)
  if view.message and view.phase ~= "HELP" and view.phase ~= "PAUSED" then
    writeAt(t, 1, 4, view.message, colors.yellow, colors.black, w)
  end
  for i = 1, #buttons do
    local b = buttons[i]
    local label=b.id=='fine' and (view.fine and 'FINE ON' or 'COARSE') or b.label
    if b.id=='view' then label=({tee='VIEW: TEE',overview='VIEW: 3D',map='VIEW: MAP'})[view.view] or 'VIEW' end
    local focused = view.focus == b.id or b.id == "swing"
    local fg, bg = focused and black or white, focused and colors.lime or colors.gray
    for yy = b.y, math.min(h, b.y + b.h - 1) do
      writeAt(t, b.x, yy, string.rep(" ", b.w), fg, bg, b.w)
    end
    local labelX=b.x+math.max(0,math.floor((b.w-#label)/2))
    local labelY=b.y+math.floor((b.h-1)/2)
    writeAt(t,labelX,labelY,label,fg,bg,math.min(#label,b.w))
  end
  if view.phase == "DIAGNOSTIC" then
    writeAt(t, 1, 4, "INPUT: "..tostring(view.lastInput or "Ready").." | 10 Hz target", bright, black, w)
  end
  if w < 39 or h < 19 then
    writeAt(t,1,4,'RESIZE TO 39 x 19',bright,black,w)
    writeAt(t,1,5,'or enlarge monitor wall',white,black,w)
    return
  end
  if view.phase == "SCORECARD" then
    local lines={"HOLE COMPLETE", "PEBBLE BEACH 7  |  PAR 3",
      string.upper(view.scoreName or ""),
      "STROKES: "..tostring(view.strokes or 0).."  PENALTIES: "..tostring(view.penalties or 0)}
    local panelW=math.min(35,w-4)
    local x=math.floor((w-panelW)/2)+1
    for i,line in ipairs(lines) do
      writeAt(t,x,5+i,string.rep(" ",panelW),black,white,panelW)
      writeAt(t,x+math.max(0,math.floor((panelW-#line)/2)),5+i,line,black,white,math.min(#line,panelW))
    end
  end
  if view.phase == "HELP" then
    writeAt(t, 1, 4, "KEYBOARD CONTROLS", bright, black, w)
    writeAt(t, 1, 5, "ARROWS aim and power   Q/E choose club", white, black, w)
    writeAt(t, 1, 6, "SPACE swing   TAB view   F fine adjust", white, black, w)
    writeAt(t, 1, 7, "P menu  H help  R restart  Backspace quit", white, black, w)
  end
  if view.phase == "PAUSED" then writeAt(t, 1, 4, "PAUSED  |  Choose RESUME, RESTART or QUIT", bright, black, w) end
  t.setCursorPos(1, h)
end

return ui
