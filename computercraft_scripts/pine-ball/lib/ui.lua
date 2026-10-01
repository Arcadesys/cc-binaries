-- Text HUD and touch targets. Four status rows on top, two button rows at the bottom.
local bb = require("lib.baseball")
local ui = {}

local PITCH_NAMES = {"FASTBALL", "CHANGEUP", "CURVE L", "CURVE R"}
ui.PITCH_NAMES = PITCH_NAMES

local function button(id, label, x, y, w, h) return {id = id, label = label, x = x, y = y, w = w, h = h} end

function ui.layout(w, h, phase, view)
  local out = {rowH = h < 24 and 2 or 3}
  local rowH = out.rowH
  if w < 39 or h < 19 then
    out[1] = button("quit", "QUIT", 1, h, w, 1); out.small = true; return out
  end
  local startY = h - rowH * 2 + 1
  local function row(r, items)
    local cols = 0
    for _, it in ipairs(items) do cols = cols + (it[3] or 1) end
    local cellW = math.floor((w - (cols - 1)) / cols)
    local x = 1
    for i, it in ipairs(items) do
      local span = it[3] or 1
      local width = i == #items and (w - x + 1) or (cellW * span + span - 1)
      out[#out + 1] = button(it[1], it[2], x, startY + (r - 1) * rowH, width, rowH)
      x = x + width + 1
    end
  end
  local mode = view and view.mode or "cpu"
  if phase == "SETUP" then
    row(1, {{"mode", mode == "duel" and "MODE: DUEL" or "MODE: CPU", 2}, {"innings_down", "INN -"}, {"innings_up", "INN +"}})
    row(2, {{"start", "PLAY BALL", 3}, {"help", "HELP"}})
  elseif phase == "FINAL" then
    row(1, {{"help", "HELP"}, {"quit", "QUIT"}})
    row(2, {{"swing", "PLAY AGAIN"}})
  elseif phase == "HELP" or phase == "PAUSED" then
    row(1, {{"restart", "NEW GAME"}, {"quit", "QUIT"}})
    row(2, {{"start", "RESUME"}})
  elseif phase == "PITCH_SELECT" then
    local d = view and view.draft or {type = 1}
    row(1, {{"pitch_cycle", PITCH_NAMES[d.type] or "TYPE", 2}, {"pitch_left", "<"}, {"pitch_right", ">"}, {"pitch_up", "^"}, {"pitch_down", "v"}})
    row(2, {{"throw", "THROW", 3}, {"pause", "MENU"}})
  else
    local aim = view and view.aim or {x = 0, y = 0}
    row(1, {{"aim_x", aim.x < 0 and "AIM: LEFT" or aim.x > 0 and "AIM: RIGHT" or "AIM: CENTER", 2},
      {"aim_y", aim.y > 0 and "LIFT" or aim.y < 0 and "CHOP" or "LEVEL"}, {"pause", "MENU"}})
    row(2, {{"swing", phase == "INTRO" and "SKIP INTRO" or "SWING"}})
  end
  return out
end

local function ascii(s) return (tostring(s):gsub("[\128-\255]", "")) end
local function put(t, x, y, text, fg, bg, width)
  local w, h = t.getSize()
  if y < 1 or y > h or x > w then return end
  text = ascii(text)
  width = math.max(0, math.min(width or #text, w - x + 1))
  text = text:sub(1, width)
  t.setCursorPos(x, y); t.setTextColor(fg); t.setBackgroundColor(bg)
  t.write(text .. string.rep(" ", math.max(0, width - #text)))
end
ui.put = put

function ui.draw(t, view, buttons)
  local w, h = t.getSize()
  local black, white, gold = colors.black, colors.white, colors.yellow
  if buttons.small then
    t.setBackgroundColor(black); t.clear()
    put(t, 1, 1, "PINE BALL", black, gold, w); put(t, 1, 2, "RESIZE TO 39x19", white, black, w)
    put(t, 1, h, "QUIT", black, colors.lime, w)
    return
  end
  local b = view.board or {}
  local score = b.score or {light = 0, dark = 0}
  local bases = b.bases or {}
  local half = b.half == "bottom" and "BOT" or "TOP"
  local diamond = (bases.first and "1" or "-") .. (bases.second and "2" or "-") .. (bases.third and "3" or "-")
  local title = ("LIGHT %d  DARK %d | %s %d | B%d S%d O%d | %s"):format(score.light, score.dark, half, b.inning or 1,
    b.balls or 0, b.strikes or 0, b.outs or 0, diamond)
  if view.phase == "SETUP" then title = "PINE BALL | ROGERS BARK MUNICIPAL FIELD" end
  put(t, 1, 1, title, black, gold, w)
  local row2
  if view.phase == "SETUP" then
    row2 = ("%s | %d INNINGS"):format(view.mode == "duel" and "2-PLAYER DUEL" or "CPU PITCHES", view.innings)
  elseif view.batter then
    local roles = view.roles and (" | " .. view.roles.batter .. " BATS") or ""
    row2 = ("AB: %s #%d (%s)%s"):format(view.batter.name, view.batter.number, view.batter.bats, roles)
  end
  put(t, 1, 2, row2 or "", white, black, w)
  if view.flash then
    put(t, 1, 3, view.flash.label, view.flash.big and gold or white, black, w)
    put(t, 1, 4, view.flash.detail or "", white, black, w)
  else
    put(t, 1, 3, view.message or "", gold, black, w)
    local line4 = ""
    if view.phase == "PITCH_SELECT" and view.draft then
      line4 = ("%s PITCHES: %s  X%+.2f Y%+.2f"):format(view.roles and view.roles.pitcher or "", PITCH_NAMES[view.draft.type], view.draft.x, view.draft.y)
    elseif view.phase ~= "SETUP" and view.phase ~= "FINAL" then
      local a = view.aim or {x = 0, y = 0}
      line4 = ("AIM %s %s | SPACE swing, arrows aim"):format(a.x < 0 and "LEFT" or a.x > 0 and "RIGHT" or "CENTER", a.y > 0 and "LIFT" or a.y < 0 and "CHOP" or "LEVEL")
    end
    put(t, 1, 4, line4, white, black, w)
  end
  if view.phase == "HELP" then
    local lines = {"BATTER: SPACE swing just before the plate.", "Hold arrows: <- -> aim field, UP lift, DOWN chop.",
      "DUEL PITCHER: 1-4 type, WASD spot, E throw.", "P menu  H help  R new game  BACKSPACE quit"}
    for i, l in ipairs(lines) do put(t, 1, 4 + i, l, white, black, w) end
  elseif view.phase == "PAUSED" then
    put(t, 1, 5, "PAUSED | RESUME, NEW GAME OR QUIT", gold, black, w)
  end
  for _, btn in ipairs(buttons) do
    local primary = btn.id == "swing" or btn.id == "start" or btn.id == "throw"
    local fg, bg = primary and black or white, primary and colors.lime or colors.gray
    for y = btn.y, math.min(h, btn.y + btn.h - 1) do put(t, btn.x, y, string.rep(" ", btn.w), fg, bg, btn.w) end
    put(t, btn.x + math.max(0, math.floor((btn.w - #btn.label) / 2)), btn.y + math.floor((btn.h - 1) / 2), btn.label, fg, bg, math.min(#btn.label, btn.w))
  end
  t.setCursorPos(1, h)
end

return ui
