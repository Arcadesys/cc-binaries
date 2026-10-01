-- Pine3D meshes converted from furball-simulator src/sports/bowling/game/{pinModel,lane,alley}.ts:
-- the faceted lathe pin, the home lane with a dressed neighbour on each side, gutters,
-- kickbacks, pin decks, masking unit, pit, benches, ball return and score monitors.
-- Built in furball scene units (x across, z along the lane, pins toward -z) and converted
-- to Pine axes (X = 5.7 - z, Y = y, Z = x). Display only; physics lives in lib/pindeck.lua.
local alley = {}

-- Palette slots (set in render.lua) chosen to match furball's flat Lambert colours.
alley.palette = {
  [colors.black] = 0x120f0e, [colors.white] = 0xfffdf2, [colors.lightGray] = 0xd9cbb0,
  [colors.gray] = 0x453a35, [colors.brown] = 0x785136, [colors.orange] = 0xd5aa6d,
  [colors.pink] = 0xc49558, [colors.magenta] = 0xb98a55, [colors.yellow] = 0xefc56c,
  [colors.red] = 0xbf2c35, [colors.purple] = 0x86202a, [colors.blue] = 0x315ecd,
  [colors.lightBlue] = 0x6b8fe6, [colors.cyan] = 0x2b2f36, [colors.green] = 0x672f27,
  [colors.lime] = 0x6ad84a,
}

local RELEASE_Z = 5.7
local LANE_CENTERS = {-8.1, 0, 8.1}
local LIGHT = {x = -0.35, y = 0.85, z = 0.4} -- furball key light (-3, 10, 6), normalised loosely

local function P(x, y, z) return RELEASE_Z - z, y, x end

local function shade(a, b, c, lit, dark)
  local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
  local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
  local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
  local len = math.sqrt(nx * nx + ny * ny + nz * nz)
  if len == 0 or not dark then return lit end
  return math.abs(nx * LIGHT.x + ny * LIGHT.y + nz * LIGHT.z) / len > 0.55 and lit or dark
end

-- Builder over Pine polygons. Points are furball scene coordinates.
local function builder()
  local m = {}
  local b = {model = m}
  function b.tri(p1, p2, p3, lit, dark)
    local x1, y1, z1 = P(p1[1], p1[2], p1[3]); local x2, y2, z2 = P(p2[1], p2[2], p2[3]); local x3, y3, z3 = P(p3[1], p3[2], p3[3])
    m[#m + 1] = {x1 = x1, y1 = y1, z1 = z1, x2 = x2, y2 = y2, z2 = z2, x3 = x3, y3 = y3, z3 = z3,
      c = shade(p1, p2, p3, lit, dark), forceRender = true}
  end
  function b.quad(p1, p2, p3, p4, lit, dark) b.tri(p1, p2, p3, lit, dark); b.tri(p1, p3, p4, lit, dark) end
  -- Axis-aligned box centred at (x, y, z), sized like THREE.BoxGeometry(w, h, d).
  function b.box(w, h, d, x, y, z, top, side)
    side = side or top
    local x0, x1, y0, y1, z0, z1 = x - w / 2, x + w / 2, y - h / 2, y + h / 2, z - d / 2, z + d / 2
    b.quad({x0, y1, z0}, {x1, y1, z0}, {x1, y1, z1}, {x0, y1, z1}, top)
    b.quad({x0, y0, z1}, {x1, y0, z1}, {x1, y1, z1}, {x0, y1, z1}, side) -- toward the bowler
    b.quad({x0, y0, z0}, {x1, y0, z0}, {x1, y1, z0}, {x0, y1, z0}, side)
    b.quad({x0, y0, z0}, {x0, y0, z1}, {x0, y1, z1}, {x0, y1, z0}, side)
    b.quad({x1, y0, z0}, {x1, y0, z1}, {x1, y1, z1}, {x1, y1, z0}, side)
  end
  function b.plane(x0, x1, z0, z1, y, color) b.quad({x0, y, z0}, {x1, y, z0}, {x1, y, z1}, {x0, y, z1}, color) end
  return b
end

-- Furball pinModel.ts: 15 regulation inches at a 2.4 inch belly radius (0.2 scene units).
local U = 0.2 / 2.4
alley.PIN_HEIGHT = 15 * U
local BASE, BELLY, BELLY_H, NECK, NECK_H, HEAD, HEAD_H = 1.1 * U, 0.2, 4.5 * U, 0.95 * U, 10 * U, 1.3 * U, 13.4 * U
alley.PIN_PROFILE = {
  {0, 0}, {BASE, 0}, {BELLY * 0.85, BELLY_H * 0.45}, {BELLY, BELLY_H}, {BELLY * 0.82, BELLY_H * 1.6},
  {NECK * 1.35, NECK_H * 0.9}, {NECK * 1.1, NECK_H * 0.96}, {NECK, NECK_H * 1.04}, {NECK * 1.05, NECK_H * 1.1},
  {HEAD, HEAD_H * 0.9}, {HEAD * 0.85, HEAD_H * 1.05}, {0, alley.PIN_HEIGHT},
}
alley.PIN_STRIPE_SEGMENTS = {[5] = true, [7] = true} -- zero-based profile segments, as in furball

-- Lathe in pin-local space (Y up the pin axis), oriented by fall direction and tilt.
-- Neighbour racks use fewer facets; they are small on screen and never move.
function alley.pinModel(angle, tilt, segments)
  angle, tilt, segments = angle or 0, tilt or 0, segments or 8
  local sa, ca, st, ct = math.sin(angle), math.cos(angle), math.sin(tilt), math.cos(tilt)
  -- Pin axis tips over toward (cos angle, sin angle) in the Pine X/Z plane.
  local function point(r, q, h)
    local lx, lz = math.cos(q) * r, math.sin(q) * r
    -- Rotate local (lx, h, lz) so +Y leans toward +X by tilt, then yaw by angle.
    local x, y = lx * ct + h * st, -lx * st + h * ct
    return x * ca - lz * sa, y, x * sa + lz * ca
  end
  local m = {}
  local profile = alley.PIN_PROFILE
  for s = 1, #profile - 1 do
    local r1, h1, r2, h2 = profile[s][1], profile[s][2], profile[s + 1][1], profile[s + 1][2]
    local stripe = alley.PIN_STRIPE_SEGMENTS[s - 1]
    for j = 0, segments - 1 do
      local q1, q2 = j * math.pi * 2 / segments, (j + 1) * math.pi * 2 / segments
      local lit = math.sin((q1 + q2) / 2 + 0.6) > -0.1
      local c = stripe and (lit and colors.red or colors.purple) or (lit and colors.white or colors.lightGray)
      local ax, ay, az = point(r1, q1, h1); local bx, by, bz = point(r1, q2, h1)
      local cx, cy, cz = point(r2, q2, h2); local dx, dy, dz = point(r2, q1, h2)
      if r1 > 0 then m[#m + 1] = {x1 = ax, y1 = ay, z1 = az, x2 = bx, y2 = by, z2 = bz, x3 = cx, y3 = cy, z3 = cz, c = c, forceRender = true} end
      if r2 > 0 then m[#m + 1] = {x1 = ax, y1 = ay, z1 = az, x2 = cx, y2 = cy, z2 = cz, x3 = dx, y3 = dy, z3 = dz, c = c, forceRender = true} end
    end
  end
  return m
end

-- Furball's ball: radius 0.3055 low-poly sphere in #315ecd, lit from the key light.
function alley.ballModel(radius, color, litColor)
  local m = {}
  local rings, segs = 5, 8
  local function v(i, j)
    local phi, th = math.pi * i / rings, math.pi * 2 * j / segs
    return {math.sin(phi) * math.cos(th) * radius, radius + math.cos(phi) * radius, math.sin(phi) * math.sin(th) * radius}
  end
  for i = 0, rings - 1 do for j = 0, segs - 1 do
    local a, b, c, d = v(i, j), v(i, j + 1), v(i + 1, j + 1), v(i + 1, j)
    local mx, my, mz = (a[1] + c[1]) / 2, (a[2] + c[2]) / 2 - radius, (a[3] + c[3]) / 2
    local col = (mx * -0.35 + my * 0.85 + mz * -0.4) > 0 and (litColor or colors.lightBlue) or (color or colors.blue)
    if i > 0 then m[#m + 1] = {x1 = a[1], y1 = a[2], z1 = a[3], x2 = b[1], y2 = b[2], z2 = b[3], x3 = c[1], y3 = c[2], z3 = c[3], c = col, forceRender = true} end
    if i < rings - 1 then m[#m + 1] = {x1 = a[1], y1 = a[2], z1 = a[3], x2 = c[1], y2 = c[2], z2 = c[3], x3 = d[1], y3 = d[2], z3 = d[3], c = col, forceRender = true} end
  end end
  return m
end

-- Static scenery for the whole alley, in one Pine model.
function alley.sceneryModel()
  local b = builder()
  local DECK = {minZ = -9.7, maxZ = -4.2}
  b.box(30, .3, 34, 0, -.55, -1, colors.gray)                                  -- carpet
  for _, cx in ipairs(LANE_CENTERS) do
    local home = cx == 0
    -- Maple lane with alternating board tones for motion cues at terminal resolution.
    for board = 0, 11 do
      local x0 = cx - 3 + board * 0.5
      b.plane(x0, x0 + 0.5, DECK.maxZ, RELEASE_Z + 0.3, -.05, board % 2 == 0 and colors.orange or colors.pink)
    end
    b.plane(cx - 3, cx + 3, RELEASE_Z + 0.3, 10, -.05, colors.orange)            -- approach
    b.plane(cx - 3, cx + 3, DECK.minZ, DECK.maxZ, -.04, colors.magenta)           -- pale pin deck
    b.plane(cx - 3, cx + 3, RELEASE_Z - .09, RELEASE_Z + .09, -.03, colors.black) -- foul line
    for i = -2, 2 do                                                              -- targeting arrows
      local x, z = cx + i * .65, 1.5 - math.abs(i) * .13
      b.tri({x - .12, -.035, z + .12}, {x + .12, -.035, z + .12}, {x, -.035, z - .3}, colors.brown)
    end
    for side = -1, 1, 2 do
      -- Half-round gutter channel as three facets, then walnut divider and kickback with its stripe.
      local gx = cx + side * 3.32
      local r = 0.31
      for k = 0, 2 do
        local a1, a2 = math.pi * k / 3, math.pi * (k + 1) / 3
        local x1, y1 = gx - math.cos(a1) * r, -math.sin(a1) * r
        local x2, y2 = gx - math.cos(a2) * r, -math.sin(a2) * r
        b.quad({x1, y1, -10.2}, {x2, y2, -10.2}, {x2, y2, RELEASE_Z}, {x1, y1, RELEASE_Z}, colors.cyan)
      end
      b.box(.2, .38, 24, cx + side * 3.8, .04, -2, colors.brown)
      b.box(.3, 1.4, 5.7, cx + side * 3.8, .6, -7.35, colors.brown)
      b.box(.32, .12, 5.7, cx + side * 3.8, 1.05, -7.35, colors.yellow)
    end
    if not home then
      for _, pin in ipairs(require("lib.pindeck").PINS) do
        local px, py, pz = P(cx + pin.x, 0, -5 - pin.row * .8)
        for _, poly in ipairs(alley.pinModel(0, 0, 5)) do
          b.model[#b.model + 1] = {x1 = poly.x1 + px, y1 = poly.y1, z1 = poly.z1 + pz, x2 = poly.x2 + px, y2 = poly.y2, z2 = poly.z2 + pz,
            x3 = poly.x3 + px, y3 = poly.y3, z3 = poly.z3 + pz, c = poly.c, forceRender = true}
        end
      end
    end
    -- Painted masking face per lane; the home lane (8) is lit.
    b.quad({cx - 3.85, 2.1, -10.18}, {cx + 3.85, 2.1, -10.18}, {cx + 3.85, 4.3, -10.18}, {cx - 3.85, 4.3, -10.18}, home and colors.red or colors.green)
    b.quad({cx - 1, 2.8, -10.17}, {cx + 1, 2.8, -10.17}, {cx + 1, 3.6, -10.17}, {cx - 1, 3.6, -10.17}, colors.white)
  end
  b.plane(-3, 3, -12.5, -9, -.06, colors.black)                                  -- rear pit
  b.box(26, 2.4, .6, 0, 3.2, -10.5, colors.black)                                -- masking unit
  b.box(26, .08, .1, 0, 1.96, -10.2, colors.white)                              -- masking light
  b.quad({-13, -.3, -10.82}, {13, -.3, -10.82}, {13, 2, -10.82}, {-13, 2, -10.82}, colors.black) -- pit curtain
  b.box(30, 2.4, .4, 0, .8, -12.7, colors.brown)                                -- back wall
  b.box(30, 3.8, .4, 0, 3.9, -12.7, colors.lightGray)
  for _, x in ipairs({-9, 0, 9}) do
    b.box(4.7, .14, 1.1, x, 6.4, -1.5, colors.gray, colors.gray)                -- ceiling fixtures
    b.box(4.3, .03, .7, x, 6.29, -1.5, colors.white)
    b.box(2.5, .3, .9, x + 4, .9, 7.7, colors.green)                            -- benches
    b.box(.13, .9, .13, x + 3, .3, 7.7, colors.black)
    b.box(.13, .9, .13, x + 5, .3, 7.7, colors.black)
  end
  b.box(.9, 1.2, 2, 4.4, .4, 6.4, colors.lightGray)                             -- ball return hood
  b.box(.65, .3, 2.4, 4.4, .65, 7.2, colors.cyan)                               -- return rack
  for i, col in ipairs({colors.purple, colors.cyan, colors.brown}) do           -- spare balls
    local sx, sy, sz = P(4.4, .7, 6.7 + (i - 1) * .55)
    for _, poly in ipairs(alley.ballModel(.3, col, col)) do
      b.model[#b.model + 1] = {x1 = poly.x1 + sx, y1 = poly.y1 + sy, z1 = poly.z1 + sz, x2 = poly.x2 + sx, y2 = poly.y2 + sy, z2 = poly.z2 + sz,
        x3 = poly.x3 + sx, y3 = poly.y3 + sy, z3 = poly.z3 + sz, c = poly.c, forceRender = true}
    end
  end
  for _, x in ipairs({-2.8, 2.8}) do                                           -- overhead score monitors
    b.box(2.08, 1.63, 1.1, x, 5.6, 2.45, colors.cyan)
    b.quad({x - .9, 4.95, 3.01}, {x + .9, 4.95, 3.01}, {x + .9, 6.25, 3.01}, {x - .9, 6.25, 3.01}, colors.blue)
    b.box(.08, 2, .08, x, 7.2, 2.6, colors.black)
  end
  return b.model
end

return alley
