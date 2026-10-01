-- Pine3D view of Rogers Bark Municipal Field. Reads App:view(); never decides outcomes.
local ui = require("lib.ui")
local stadium = require("lib.stadium")
local pine = require("vendor.Pine3D")
local render = {}
local P = stadium.P

local function paletteSave(t)
  local saved = {}
  if t.getPaletteColor then for i = 0, 15 do local ok, r, g, b = pcall(t.getPaletteColor, 2 ^ i); if ok then saved[i] = {r, g, b} end end end
  return saved
end

function render.new(target)
  local t = target or term.current(); local oldTerm = term.current()
  local saved = paletteSave(t)
  for c, hex in pairs(stadium.palette) do if t.setPaletteColor then pcall(t.setPaletteColor, c, hex) end end
  t.setBackgroundColor(colors.black); t.setTextColor(colors.white); t.clear()
  local w, h = t.getSize()
  local controls = ui.layout(w, h, "PITCH")
  local sceneY = 5
  local sceneH = math.max(1, h - 4 - controls.rowH * 2)
  local frame = pine.newFrame(1, sceneY, w, sceneH)
  frame:setBackgroundColor(colors.lightBlue); frame:setFoV(64)
  local objects = {
    frame:newObject(stadium.fieldModel(), 0, 0, 0),
    frame:newObject(stadium.standsModel(), 0, 0, 0),
    frame:newObject(stadium.skylineModel(), 0, 0, 0),
  }
  local zone = frame:newObject(stadium.zoneModel(), 0, -100, 0); objects[#objects + 1] = zone
  local ball = frame:newObject(stadium.ballModel(), 0, -100, 0); objects[#objects + 1] = ball
  local landing = frame:newObject({{x1 = -1.2, y1 = .08, z1 = 0, x2 = 0, y2 = .08, z2 = 1.2, x3 = 1.2, y3 = .08, z3 = 0, c = colors.yellow, forceRender = true},
    {x1 = -1.2, y1 = .08, z1 = 0, x2 = 1.2, y2 = .08, z2 = 0, x3 = 0, y3 = .08, z3 = -1.2, c = colors.yellow, forceRender = true}}, 0, -100, 0)
  objects[#objects + 1] = landing
  -- Pawn pools: models are cached per team/role and swapped only when that changes.
  local models = {}
  local function model(team, role)
    local key = team .. ":" .. role
    models[key] = models[key] or stadium.pawnModel(team, role)
    return models[key]
  end
  local pawns = {}
  for i = 1, 14 do
    pawns[i] = {object = frame:newObject(model("dark", "field"), 0, -100, 0), key = "dark:field"}
    objects[#objects + 1] = pawns[i].object
  end
  local closed = false
  local api = {buttons = {}}

  local function camera(view)
    local s = view.scene
    if view.phase == "SETUP" or view.phase == "FINAL" then
      local x, y, z = P(0, 34, 40)
      frame:setCamera({x = x, y = y, z = z, rotX = -90, rotY = 0, rotZ = -24}); frame:setFoV(70)
    elseif s.camera == "field" then
      local spot = s.landing or {x = 0, z = -60}
      local yaw = math.deg(math.atan2 and math.atan2(spot.x, -spot.z) or math.atan(spot.x, -spot.z)) * .8
      local x, y, z = P(0, 24, 30)
      frame:setCamera({x = x, y = y, z = z, rotX = -90, rotY = yaw, rotZ = -17}); frame:setFoV(66)
    else
      -- Furball's batting view: low behind the plate, offset toward the batter's side.
      local side = s.batter and (s.batter.bats == "R" and -1 or 1) or 0
      local x, y, z = P(-side * .55, 3.1, 11)
      frame:setCamera({x = x, y = y, z = z, rotX = -90, rotY = 0, rotZ = -8}); frame:setFoV(46)
    end
  end

  function api:draw(view)
    if closed then return end
    local tw, th = t.getSize()
    controls = ui.layout(tw, th, view.phase, view)
    self.buttons = controls
    local s = view.scene
    -- Place pawns: fielders, batter, runners. The catcher stays hidden in the batting view, as in furball.
    local used = 0
    local function place(team, role, x, z)
      used = used + 1
      local pawn = pawns[used]
      if not pawn then return end
      local key = team .. ":" .. role
      if pawn.key ~= key then pawn.object:setModel(model(team, role)); pawn.key = key end
      local px, py, pz = P(x, 0, z)
      pawn.object:setPos(px, py, pz)
    end
    for _, f in ipairs(s.fielders) do
      if not (f.pos == "C" and s.camera == "batting") then place(f.team, "field", f.x, f.z) end
    end
    if s.batter then place(s.batter.team, s.batter.bats == "R" and "batR" or "batL", s.batter.x, s.batter.z) end
    for _, r in ipairs(s.runners) do place(r.team, "field", r.x, r.z) end
    for i = used + 1, #pawns do pawns[i].object:setPos(0, -100, 0) end
    if s.ball then local x, y, z = P(s.ball.x, s.ball.y, s.ball.z); ball:setPos(x, y, z) else ball:setPos(0, -100, 0) end
    if s.zone or view.phase == "PITCH_SELECT" then zone:setPos(0, 0, 0) else zone:setPos(0, -100, 0) end
    if s.landing then local x, y, z = P(s.landing.x, 0, s.landing.z); landing:setPos(x, y, z) else landing:setPos(0, -100, 0) end
    camera(view)
    t.setBackgroundColor(colors.black); t.setTextColor(colors.white); t.clear()
    frame:drawObjects(objects); frame:drawBuffer()
    -- The ball is a few pixels at outfield distance; mark it while a play is live.
    if s.camera == "field" and s.ball then
      local x, y, z = P(s.ball.x, s.ball.y, s.ball.z)
      local px, py, visible = frame:map3dTo2d(x, y, z)
      if visible then
        local cx, cy = math.floor((px - 1) / 2 + .5) + 1, sceneY + math.floor((py - 1) / 3 + .5)
        if cy >= sceneY and cy < sceneY + sceneH and cx >= 1 and cx <= tw then ui.put(t, cx, cy, "o", colors.black, colors.white, 1) end
      end
    end
    -- Duel pitcher's target, marked in the zone for the pitching player.
    if view.phase == "PITCH_SELECT" and view.draft then
      local x, y, z = P(view.draft.x * .26, .8 + view.draft.y * .32, 0)
      local px, py, visible = frame:map3dTo2d(x, y, z)
      if visible then
        local cx, cy = math.floor((px - 1) / 2 + .5) + 1, sceneY + math.floor((py - 1) / 3 + .5)
        if cy >= sceneY and cy < sceneY + sceneH then ui.put(t, cx, cy, "+", colors.red, colors.white, 1) end
      end
    end
    ui.draw(t, view, controls)
  end

  function api:close()
    if closed then return end; closed = true
    if frame and frame.buffer and frame.buffer.blitWin then pcall(frame.buffer.blitWin.setVisible, false) end
    for i, rgb in pairs(saved) do if t.setPaletteColor then pcall(t.setPaletteColor, 2 ^ i, rgb[1], rgb[2], rgb[3]) end end
    t.setBackgroundColor(colors.black); t.setTextColor(colors.white); t.clear(); t.setCursorPos(1, 1)
    if term.redirect then term.redirect(oldTerm) end
  end
  return api
end

return render
