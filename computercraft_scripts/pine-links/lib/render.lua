-- Pine3D view of furball's Marovitz-inspired Hole 3 (lib/course.lua). The scene mirrors
-- furball-simulator src/sports/golf/scene.ts in low-poly terminal form; it never decides outcomes.
-- Furball metres (x right, z downrange) are drawn at Pine (X = z, Y = y, Z = x).
local ui = require("lib.ui")
local mascots = require("lib.mascots")
local pine = require("vendor.Pine3D")
local course = require("lib.course")
local render = {}

local function P(x, y, z) return {x = z, y = y, z = x} end -- furball -> Pine coordinates
local function tri(m, a, b, c, color)
  m[#m + 1] = {x1 = a.x, y1 = a.y, z1 = a.z, x2 = b.x, y2 = b.y, z2 = b.z, x3 = c.x, y3 = c.y, z3 = c.z, c = color, forceRender = true}
end
local function rect(m, x0, x1, z0, z1, y, color)
  tri(m, P(x0, y, z0), P(x1, y, z0), P(x1, y, z1), color)
  tri(m, P(x0, y, z0), P(x1, y, z1), P(x0, y, z1), color)
end
local function ellipse(m, cx, cz, rx, rz, y, color, segments)
  segments = segments or 16
  for i = 0, segments - 1 do
    local a, b = i / segments * math.pi * 2, (i + 1) / segments * math.pi * 2
    tri(m, P(cx, y, cz), P(cx + math.cos(a) * rx, y, cz + math.sin(a) * rz), P(cx + math.cos(b) * rx, y, cz + math.sin(b) * rz), color)
  end
end
local function box(m, cx, cz, w, h, d, y0, side, top)
  local x0, x1, z0, z1, y1 = cx - w / 2, cx + w / 2, cz - d / 2, cz + d / 2, y0 + h
  local c = {P(x0, y0, z0), P(x1, y0, z0), P(x1, y0, z1), P(x0, y0, z1), P(x0, y1, z0), P(x1, y1, z0), P(x1, y1, z1), P(x0, y1, z1)}
  local faces = {{1, 2, 6, 5}, {2, 3, 7, 6}, {3, 4, 8, 7}, {4, 1, 5, 8}}
  for _, f in ipairs(faces) do tri(m, c[f[1]], c[f[2]], c[f[3]], side); tri(m, c[f[1]], c[f[3]], c[f[4]], side) end
  tri(m, c[5], c[6], c[7], top or side); tri(m, c[5], c[7], c[8], top or side)
end
-- Tapered trunk plus a stretched octahedron crown, like furball's cylinder + icosahedron trees.
local function tree(m, t)
  box(m, t.x, t.z, 1.2, 8, 1.2, 0, colors.brown)
  local top, mid, r = 17, 10, 5
  local crown = t.z % 3 ~= 0 and colors.purple or colors.green
  local ring = {P(t.x + r, mid, t.z), P(t.x, mid, t.z + r), P(t.x - r, mid, t.z), P(t.x, mid, t.z - r)}
  for i = 1, 4 do
    local a, b = ring[i], ring[i % 4 + 1]
    tri(m, a, b, P(t.x, top, t.z), crown)
    tri(m, a, b, P(t.x, 3.5, t.z), crown)
  end
end

local function courseModel()
  local m = {}
  local B, H, C = course.bounds, course.hole, course.cup
  rect(m, -95, 95, -45, 235, -0.05, colors.green)                -- rough
  rect(m, -12, 12, 4, 153, 0, colors.brown)                      -- fairway
  for z = 9, 144, 18 do rect(m, -12, 12, z - 4.5, z + 4.5, 0.03, colors.lime) end -- mowing stripes
  ellipse(m, C.x, C.z, H.greenRadiusX + 1.8, H.greenRadiusZ + 1.8, 0.05, colors.lime, 20) -- fringe
  ellipse(m, C.x, C.z, H.greenRadiusX, H.greenRadiusZ, 0.08, colors.cyan, 20)              -- green
  for _, b in ipairs(course.bunkers) do
    ellipse(m, b.x, b.z, b.rx + 0.55, b.rz + 0.55, 0.085, colors.orange, 14)
    ellipse(m, b.x, b.z, b.rx, b.rz, 0.09, colors.yellow, 14)
  end
  rect(m, -3, 3, -4, 4, 0.05, colors.lime)                        -- tee box
  for _, x in ipairs({-2.5, 2.5}) do box(m, x, -1, 0.5, 0.5, 0.5, 0.05, colors.blue) end
  ellipse(m, C.x, C.z, H.cupRadius * 2, H.cupRadius * 2, 0.1, colors.black, 8)
  for _, t in ipairs(course.trees) do tree(m, t) end
  for z = B.near, B.far, 20 do for _, x in ipairs({-B.halfWidth, B.halfWidth}) do box(m, x, z, 0.4, 1.4, 0.4, 0, colors.white) end end
  for x = -B.halfWidth, B.halfWidth, 12 do for _, z in ipairs({B.near, B.far}) do box(m, x, z, 0.4, 1.4, 0.4, 0, colors.white) end end
  -- Original skyline and park-path dressing; neither encodes compass orientation nor survey landmarks.
  rect(m, -50.5, -45.5, -21.5, 213.5, 0.02, colors.lightGray)
  for i = 0, 11 do
    local height = 7 + (i % 4) * 4
    box(m, -66 - (i % 3) * 10, 20 + i * 17, 7, height, 9, 0, i % 2 == 1 and colors.gray or colors.red, colors.lightGray)
  end
  -- Flag: white pole and red pennant.
  box(m, C.x, C.z, 0.15, 3.8, 0.15, 0, colors.white)
  tri(m, P(C.x, 3.8, C.z), P(C.x, 3.1, C.z), P(C.x + 1.4, 3.45, C.z), colors.red)
  return m
end

local function ballModel()
  local r = 0.45 -- display only: furball draws a 0.24 m ball with an on-screen marker
  local m = {}
  local top, bottom = {x = 0, y = r * 2, z = 0}, {x = 0, y = 0, z = 0}
  local ring = {{x = r, y = r, z = 0}, {x = 0, y = r, z = r}, {x = -r, y = r, z = 0}, {x = 0, y = r, z = -r}}
  for i = 1, 4 do
    local a, b = ring[i], ring[i % 4 + 1]
    tri(m, a, b, top, i % 2 == 0 and colors.white or colors.lightGray)
    tri(m, a, b, bottom, colors.lightGray)
  end
  return m
end

-- Flat diamonds along the calm-weather forecast; the last one marks the predicted finish.
local function forecastModel(points, penalty)
  local m = {}
  local color = penalty and colors.red or colors.white
  for i = 2, #points do
    local p = points[i]
    local s = i == #points and 1.1 or 0.45
    local y = p.y + 0.12
    tri(m, P(p.x - s, y, p.z), P(p.x, y, p.z - s), P(p.x + s, y, p.z), color)
    tri(m, P(p.x - s, y, p.z), P(p.x + s, y, p.z), P(p.x, y, p.z + s), color)
  end
  return m
end

local function sceneBoxFor(t)
  local w, h = t.getSize()
  local layout = ui.layout(w, h, "AIM")
  local rowH = layout[1] and layout[1].h or 2
  return {x = 1, y = 5, w = w, h = math.max(1, h - 4 - rowH * (layout.rows or 3))}
end

function render.new(target)
  local t = term.current()
  local originalPalette = {}
  if t.getPaletteColor then
    for i = 0, 15 do
      local ok, r, g, b = pcall(t.getPaletteColor, 2 ^ i)
      if ok then originalPalette[#originalPalette + 1] = {2 ^ i, r, g, b} end
    end
  end
  -- Furball's flat-shaded park palette; restored on exit.
  if t.setPaletteColor then
    local shades = {[colors.green] = 0x4c753a, [colors.brown] = 0x80a24c, [colors.lime] = 0x88ae50,
      [colors.cyan] = 0xa1bf69, [colors.yellow] = 0xf3db9c, [colors.orange] = 0xb7a16e,
      [colors.purple] = 0x294f36, [colors.lightBlue] = 0x92b6c4, [colors.blue] = 0x304e81,
      [colors.gray] = 0x7a6360, [colors.red] = 0xa53443, [colors.lightGray] = 0xc6baa1}
    for c, rgb in pairs(shades) do t.setPaletteColor(c, rgb) end
  end
  local renderer = {target = target, buttons = {}}
  local sceneBox = sceneBoxFor(t)
  local frame = pine.newFrame(sceneBox.x, sceneBox.y, sceneBox.w, sceneBox.h)
  frame:setBackgroundColor(colors.lightBlue)
  frame:setFoV(60)
  local tee = course.hole.tee
  local objects = {frame:newObject(courseModel(), 0, 0, 0)}
  local ballObject = frame:newObject(ballModel(), tee.z, 0, tee.x)
  objects[#objects + 1] = ballObject
  local forecastObject = frame:newObject(forecastModel({}), 0, -100, 0)
  objects[#objects + 1] = forecastObject
  local forecastKey
  local axisObject

  function renderer:resize()
    sceneBox = sceneBoxFor(t)
    frame:setSize(sceneBox.x, sceneBox.y, sceneBox.w, sceneBox.h)
  end

  local function marker(x, y, z, glyph, fg, bg)
    local p = P(x, y, z)
    local px, py, visible = frame:map3dTo2d(p.x, p.y, p.z)
    if not visible or px < 0 or py < 0 then return end
    local cx = sceneBox.x + math.floor((px - 1) / 2 + 0.5)
    local cy = sceneBox.y + math.floor((py - 1) / 3 + 0.5)
    if cx >= sceneBox.x and cx < sceneBox.x + sceneBox.w and cy >= sceneBox.y and cy < sceneBox.y + sceneBox.h then
      t.setCursorPos(cx, cy); t.setTextColor(fg); t.setBackgroundColor(bg); t.write(glyph)
    end
  end

  local function drawScene(view)
    local ball = view.ball or tee
    local aim = math.rad(view.aim or 0)
    local fx, fz = math.sin(aim), math.cos(aim) -- furball forward (x, z)
    local yaw = math.deg(math.atan2 and math.atan2(fx, fz) or math.atan(fx, fz))
    if view.phase == "DIAGNOSTIC" then
      frame:setCamera(-25, 22, -18, -90, 35, -30)
    elseif view.view == "overview" then
      -- Fixed three-quarter view from behind the tee, like furball's course camera.
      frame:setCamera(-70, 48, 0, -90, 0, -21)
    elseif view.view == "map" then
      local B = course.bounds
      frame:setCamera((B.near + B.far) / 2, (B.far - B.near) * 0.62, 0, -90, -90, -90)
    else
      -- Furball's follow camera: behind the ball along the aim line, raised, looking downrange.
      local moving = view.phase == "SHOT_PLAYBACK"
      local back, lift = moving and 22 or 12, moving and 11 + (ball.y or 0) * 0.6 or 4.5
      local cam = P(ball.x - fx * back, lift, ball.z - fz * back)
      frame:setCamera(cam.x, cam.y, cam.z, -90, yaw, moving and -20 or -7)
    end
    local b = P(ball.x, ball.y or 0, ball.z)
    ballObject:setPos(b.x, b.y, b.z)
    local fc = view.forecast
    local key = fc and (#fc.points .. ":" .. fc.finish.ball.x .. ":" .. fc.finish.ball.z .. ":" .. tostring(fc.penalty)) or nil
    if key ~= forecastKey then
      forecastKey = key
      if fc then forecastObject:setModel(forecastModel(fc.points, fc.penalty)); forecastObject:setPos(0, 0, 0)
      else forecastObject:setPos(0, -100, 0) end
    end
    local drawObjects = objects
    if view.phase == "DIAGNOSTIC" then
      if not axisObject then
        local m = {}
        box(m, 6, 0, 12, 0.3, 0.3, 0.3, colors.red)   -- +x (right, Pine Z)
        box(m, 0, 0, 0.3, 6, 0.3, 0, colors.white)    -- +y
        box(m, 0, 6, 0.3, 0.3, 12, 0.3, colors.blue)  -- +z (downrange, Pine X)
        axisObject = frame:newObject(m, 0, 0, 0)
      end
      drawObjects = {}
      for i = 1, #objects do drawObjects[i] = objects[i] end
      drawObjects[#drawObjects + 1] = axisObject
    end
    frame:drawObjects(drawObjects)
    frame:drawBuffer()
    if view.mascot then mascots.draw(t,view.mascot,2,5,view.phase=="TITLE" and "PICK" or "READY") end
    -- Readable HUD markers on top of the 3D scene; never collision geometry.
    marker(ball.x, (ball.y or 0) + 1.2, ball.z, "@", colors.black, colors.white)
    marker(course.cup.x, 4.6, course.cup.z, "!", colors.yellow, colors.black)
    if view.view == "map" then marker(tee.x, 0.2, tee.z, "T", colors.black, colors.white) end
    if view.phase == "DIAGNOSTIC" then
      marker(12.5, 0.5, 0, "X+", colors.black, colors.red)
      marker(0, 6.5, 0, "Y+", colors.black, colors.white)
      marker(0, 0.5, 12.5, "Z+", colors.black, colors.blue)
    end
  end

  function renderer:draw(view)
    view = view or {}
    local w, h = t.getSize()
    t.setBackgroundColor(colors.black); t.setTextColor(colors.white); t.clear()
    drawScene(view)
    local club = view.club or {}
    local row2
    if w >= 48 then
      row2 = string.format("%s %dm  POWER %.1f%%  AIM %+.1f deg", tostring(club.name or "?"):upper(), club.carry or 0, view.power or 0, view.aim or 0)
    else
      row2 = string.format("%s PWR%.1f%% AIM%+.1f", tostring(club.name or "?"):upper(), view.power or 0, view.aim or 0)
    end
    local row3
    local fc = view.forecast
    if fc then
      row3 = fc.penalty and "FORECAST: OUT OF BOUNDS (+1)" or string.format("FORECAST %.1fm TO CUP | %s%s",
        require("lib.golf").distanceToCup(fc.finish), fc.finish.lie:upper(), fc.finish.phase == "finished" and " | IN THE CUP" or "")
    else
      row3 = string.format("TO CUP %.1fm  LIE %s%s", view.toCup or 0, tostring(view.lie or "tee"):upper(),
        (view.ball and (view.ball.y or 0) > 0.05) and string.format("  BALL %.1fm HIGH", view.ball.y) or "")
    end
    local title
    if view.phase == "TITLE" then title = w >= 48 and "PINE LINKS  |  ROGERS BARK MUNICIPAL GOLF" or "PINE LINKS  |  MAROVITZ 3"
    else title = string.format("HOLE 3  PAR 3  |  STROKES %d  |  PEN %d", view.strokes or 0, view.penalties or 0) end
    ui.writeAt(t, 1, 1, title, colors.black, colors.yellow, w)
    if h >= 2 then ui.writeAt(t, 1, 2, row2, colors.white, colors.black, w) end
    if h >= 3 then ui.writeAt(t, 1, 3, row3, colors.white, colors.black, w) end
    self.buttons = ui.layout(w, h, view.phase)
    ui.draw(t, view, self.buttons, sceneBox.h)
  end

  function renderer:close()
    if frame and frame.buffer and frame.buffer.blitWin then pcall(frame.buffer.blitWin.setVisible, false) end
    if t.setPaletteColor then
      for _, p in ipairs(originalPalette) do pcall(t.setPaletteColor, p[1], p[2], p[3], p[4]) end
    end
    if t.setBackgroundColor then t.setBackgroundColor(colors.black) end
    if t.setTextColor then t.setTextColor(colors.white) end
    if t.clear then t.clear(); t.setCursorPos(1, 1) end
  end
  return renderer
end

render._testCourseModel = courseModel
return render
