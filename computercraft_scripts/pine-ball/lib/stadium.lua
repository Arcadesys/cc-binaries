-- Pine3D meshes converted from furball-simulator src/game/field.ts: Rogers Bark Municipal
-- Field, its neighbourhood stands and skyline. Built in furball field metres (home at the
-- origin, first base +x, centre field -z) and converted to Pine axes (X = -z, Y = y, Z = x).
-- Character avatars are not converted; players are simple team-coloured pawns.
local plays = require("lib.plays")
local stadium = {}

-- Palette slots, chosen from furball's flat colours (set in render.lua).
stadium.palette = {
  [colors.black] = 0x101418, [colors.white] = 0xfff5db, [colors.lightGray] = 0xbac7cf,
  [colors.gray] = 0x344c61, [colors.green] = 0x3f7f3c, [colors.lime] = 0x5f9d4a,
  [colors.brown] = 0xa8744a, [colors.orange] = 0xe4c889, [colors.yellow] = 0xeeae54,
  [colors.red] = 0xcf734e, [colors.purple] = 0x413b49, [colors.blue] = 0x3c5b87,
  [colors.lightBlue] = 0x9cc6dc, [colors.cyan] = 0x6b8990, [colors.magenta] = 0xf1b79b,
  [colors.pink] = 0xded0ef,
}
local CROWD = {colors.yellow, colors.lightBlue, colors.pink, colors.red, colors.orange, colors.cyan}

local function P(x, y, z) return -z, y, x end

local function builder()
  local m = {}
  local b = {model = m}
  function b.tri(p1, p2, p3, c)
    local x1, y1, z1 = P(p1[1], p1[2], p1[3]); local x2, y2, z2 = P(p2[1], p2[2], p2[3]); local x3, y3, z3 = P(p3[1], p3[2], p3[3])
    m[#m + 1] = {x1 = x1, y1 = y1, z1 = z1, x2 = x2, y2 = y2, z2 = z2, x3 = x3, y3 = y3, z3 = z3, c = c, forceRender = true}
  end
  function b.quad(p1, p2, p3, p4, c) b.tri(p1, p2, p3, c); b.tri(p1, p3, p4, c) end
  -- Box centred at (x, y, z) with width along its local x, rotated by angle about y
  -- (THREE.Object3D rotation.y). Bottom faces are skipped: nothing is seen from below.
  function b.box(w, h, d, x, y, z, angle, side, top)
    local ca, sa = math.cos(angle or 0), math.sin(angle or 0)
    local function v(lx, ly, lz) return {x + lx * ca + lz * sa, y + ly, z - lx * sa + lz * ca} end
    local hw, hh, hd = w / 2, h / 2, d / 2
    local c = {v(-hw, -hh, -hd), v(hw, -hh, -hd), v(hw, -hh, hd), v(-hw, -hh, hd), v(-hw, hh, -hd), v(hw, hh, -hd), v(hw, hh, hd), v(-hw, hh, hd)}
    b.quad(c[5], c[6], c[7], c[8], top or side)
    for _, f in ipairs({{1, 2, 6, 5}, {2, 3, 7, 6}, {3, 4, 8, 7}, {4, 1, 5, 8}}) do b.quad(c[f[1]], c[f[2]], c[f[3]], c[f[4]], side) end
  end
  function b.disc(cx, cz, r, y, c, segments)
    segments = segments or 12
    for i = 0, segments - 1 do
      local a1, a2 = i / segments * math.pi * 2, (i + 1) / segments * math.pi * 2
      b.tri({cx, y, cz}, {cx + math.cos(a1) * r, y, cz + math.sin(a1) * r}, {cx + math.cos(a2) * r, y, cz + math.sin(a2) * r}, c)
    end
  end
  -- Flat strip from a to b (ground points), given width.
  function b.strip(ax, az, bx, bz, width, y, c)
    local dx, dz = bx - ax, bz - az
    local len = math.sqrt(dx * dx + dz * dz)
    local nx, nz = -dz / len * width / 2, dx / len * width / 2
    b.quad({ax + nx, y, az + nz}, {bx + nx, y, bz + nz}, {bx - nx, y, bz - nz}, {ax - nx, y, az - nz}, c)
  end
  return b
end

local WALL, WALL_H = plays.WALL_DISTANCE, plays.WALL_HEIGHT
local BASES = plays.BASES

function stadium.fieldModel()
  local b = builder()
  -- Foul-territory grass, then the fair-territory fan out to the wall.
  b.quad({-200, -.05, 60}, {200, -.05, 60}, {200, -.05, -200}, {-200, -.05, -200}, colors.green)
  local fan = 24
  for i = 0, fan - 1 do
    local a1 = -math.pi * 0.75 + i / fan * math.pi * 0.5
    local a2 = -math.pi * 0.75 + (i + 1) / fan * math.pi * 0.5
    local r = WALL + 10
    b.tri({0, 0, 0}, {math.cos(a1) * r, 0, math.sin(a1) * r}, {math.cos(a2) * r, 0, math.sin(a2) * r}, i % 2 == 0 and colors.lime or colors.green)
  end
  -- Infield grass square inside narrow dirt basepaths.
  local d = plays.BASE_DISTANCE / math.sqrt(2)
  local inner = (plays.BASE_DISTANCE - 2.6) / math.sqrt(2)
  b.quad({0, .015, -d + inner}, {inner, .015, -d}, {0, .015, -d - inner}, {-inner, .015, -d}, colors.lime)
  for i = 1, 4 do
    local from, to = BASES[i], BASES[i % 4 + 1]
    b.strip(from.x, from.z, to.x, to.z, 2.6, .025, colors.brown)
  end
  for i = 2, 4 do b.disc(BASES[i].x, BASES[i].z, 1.85, .045, colors.brown, 10) end
  b.disc(0, 0, 4.4, .045, colors.brown, 16)
  -- Mound: low octagonal frustum.
  local mz = -plays.MOUND_DISTANCE
  for i = 0, 7 do
    local a1, a2 = i / 8 * math.pi * 2, (i + 1) / 8 * math.pi * 2
    b.quad({math.cos(a1) * 2.8, 0, mz + math.sin(a1) * 2.8}, {math.cos(a2) * 2.8, 0, mz + math.sin(a2) * 2.8},
      {math.cos(a2) * 2.4, .25, mz + math.sin(a2) * 2.4}, {math.cos(a1) * 2.4, .25, mz + math.sin(a1) * 2.4}, colors.brown)
    b.tri({0, .25, mz}, {math.cos(a1) * 2.4, .25, mz + math.sin(a1) * 2.4}, {math.cos(a2) * 2.4, .25, mz + math.sin(a2) * 2.4}, colors.brown)
  end
  b.box(.6, .05, .15, 0, .27, mz, 0, colors.white)                              -- rubber
  -- Chalk batter boxes, bags, plate and foul lines.
  for _, sx in ipairs({-1, 1}) do
    local cx = sx * 1.3
    for _, edge in ipairs({-1, 1}) do
      b.strip(cx + edge * .7, -1.05, cx + edge * .7, 1.55, .12, .065, colors.white)
      b.strip(cx - .75, .25 + edge * 1.3, cx + .75, .25 + edge * 1.3, .12, .065, colors.white)
    end
  end
  for i = 2, 4 do b.box(.6, .1, .6, BASES[i].x, .06, BASES[i].z, math.pi / 4, colors.white) end
  b.quad({-.22, .07, -.22}, {.22, .07, -.22}, {.22, .07, .1}, {-.22, .07, .1}, colors.white)
  b.tri({-.22, .07, .1}, {.22, .07, .1}, {0, .07, .32}, colors.white)
  for _, sx in ipairs({-1, 1}) do
    local e = WALL / math.sqrt(2)
    b.strip(0, 0, sx * e, -e, .3, .06, colors.white)
  end
  return b.model
end

function stadium.standsModel()
  local b = builder()
  local wallCount = 14
  local arcStart, arcStep = -math.pi * 0.75, math.pi * 0.5 / wallCount
  local wallWidth = 2 * WALL * math.sin(arcStep / 2)
  -- Mural walls in furball's mural palette, a coping rail and four rows of bleachers.
  local mural = {colors.blue, colors.red, colors.cyan, colors.yellow, colors.purple, colors.magenta}
  for i = 0, wallCount - 1 do
    local a = arcStart + (i + .5) * arcStep
    local angle = -a - math.pi / 2
    local x, z = math.cos(a), math.sin(a)
    b.box(wallWidth + .15, WALL_H, .65, x * WALL, WALL_H / 2, z * WALL, angle, mural[i % #mural + 1])
    b.box(wallWidth + .15, .3, .9, x * WALL, WALL_H + .15, z * WALL, angle, colors.orange)
    if i ~= 6 and i ~= 7 then
      for row = 0, 3 do
        local radius, y = WALL + 4 + row * 2.4, 2.6 + row * 1.7
        b.box(wallWidth, .55, 1.7, x * radius, y, z * radius, angle, colors.cyan)
        for seat = 0, 6, 2 do
          local tangent = (seat - 3) * 1.45
          local px, pz = x * radius - z * tangent, z * radius + x * tangent
          b.box(1.6, 1.8, .6, px, y + 1.2, pz, angle, CROWD[(i * 5 + row * 3 + seat) % #CROWD + 1])
        end
      end
    end
  end
  -- Foul-side stands down each line.
  for _, sx in ipairs({-1, 1}) do for section = 0, 5 do
    local a = .15 - section * .17
    local x, z = sx * math.cos(a), math.sin(a)
    local angle = math.atan2 and math.atan2(x, z) or math.atan(x, z)
    for row = 0, 4 do
      local radius, y = 65 + row * 2.4, .8 + row * 1.65
      b.box(10.4, .55, 1.7, x * radius, y, z * radius, angle, colors.cyan)
      for seat = 0, 6, 2 do
        local tangent = (seat - 3) * 1.4
        local px, pz = x * radius + z * tangent, z * radius - x * tangent
        b.box(1.6, 1.8, .6, px, y + 1.2, pz, angle, CROWD[(section * 5 + row * 3 + seat) % #CROWD + 1])
      end
    end
  end end
  -- Dugouts.
  for _, sx in ipairs({-1, 1}) do
    local x, z, angle = sx * 33, -11, sx * math.pi / 4
    b.box(14, .6, 6, x, 3.4, z, angle, colors.blue)
    b.box(14, 3, .5, x + sx * 2, 1.5, z + 2, angle, colors.gray)
  end
  return b.model
end

function stadium.skylineModel()
  local b = builder()
  for i = 0, 15 do
    local a = -math.pi * 0.82 + i / 15 * math.pi * 0.64
    local radius = WALL + 40 + (i % 3) * 7
    local height = 13 + (i * 7 % 5) * 3
    local x, z = math.cos(a) * radius, math.sin(a) * radius
    local angle = -a - math.pi / 2
    b.box(12, height, 10, x, height / 2, z, angle, i % 2 == 1 and colors.magenta or colors.lightGray)
    b.box(12.8, .7, 10.8, x, height + .35, z, angle, colors.purple)
  end
  for i = 0, 23 do
    local a = -math.pi * 0.85 + i / 23 * math.pi * 0.7
    local radius = WALL + 23 + i % 3 * 5
    local x, z = math.cos(a) * radius, math.sin(a) * radius
    b.box(.8, 6, .8, x, 3, z, 0, colors.brown)
    local cy, crown = 7.3 + i % 3, i % 2 == 1 and colors.lime or colors.green
    local ring = {{x + 3.5, cy, z}, {x, cy, z + 3}, {x - 3.5, cy, z}, {x, cy, z - 3}}
    for k = 1, 4 do
      b.tri(ring[k], ring[k % 4 + 1], {x, cy + 5.5, z}, crown)
      b.tri(ring[k], ring[k % 4 + 1], {x, cy - 4, z}, crown)
    end
  end
  -- Lattice light towers: twin masts, frame and a lit lamp bank.
  for _, t in ipairs({{-73, -68}, {73, -68}, {-41, -5}, {41, -5}}) do
    local x, z = t[1], t[2]
    local face = math.atan2 and math.atan2(-x, -z) or math.atan(-x, -z)
    for _, dx in ipairs({-.9, .9}) do b.box(.3, 27, .3, x + dx, 13.5, z, 0, colors.lightGray) end
    b.box(7.6, 3, .7, x, 27, z, face, colors.gray)
    b.box(7, 2.4, .2, x - math.sin(face) * .45, 27, z - math.cos(face) * .45, face, colors.white)
  end
  -- Scoreboard cabinet, supports, civic arch and slogan boards.
  b.box(26, 14, 1.5, 0, 11, -102, 0, colors.gray)
  b.box(22, 9, .2, 0, 11, -101.2, 0, colors.black)
  for _, x in ipairs({-9, 9}) do b.box(.8, 10, .8, x, 5, -WALL - 6.3, 0, colors.lightGray) end
  b.box(31, 5, .7, 0, 19.5, -102, 0, colors.orange)
  for k = 0, 7 do
    local a1, a2 = k / 8 * math.pi, (k + 1) / 8 * math.pi
    b.quad({math.cos(a1) * 5, 22 + math.sin(a1) * 5, -101.6}, {math.cos(a2) * 5, 22 + math.sin(a2) * 5, -101.6},
      {math.cos(a2) * 5, 22, -101.6}, {math.cos(a1) * 5, 22, -101.6}, colors.orange)
  end
  b.box(29, 3.6, .3, 0, 19.2, -101, 0, colors.blue)
  b.box(25, 3.1, .3, -44, 5.7, -86, math.atan2 and math.atan2(44, 86) or 0, colors.red)
  b.box(23, 3.1, .3, 44, 5.7, -86, math.atan2 and math.atan2(-44, 86) or 0, colors.yellow)
  return b.model
end

-- Simple pawn: legs, jersey, head and cap in team colours. Light: cream with red cap;
-- Dark: navy with cream cap. Batters carry a bat on their swing side.
function stadium.pawnModel(team, role)
  local b = builder()
  local jersey = team == "light" and colors.white or colors.blue
  local cap = team == "light" and colors.red or colors.white
  b.box(.5, .8, .35, 0, .4, 0, 0, colors.gray)
  b.box(.75, .85, .45, 0, 1.22, 0, 0, jersey)
  b.box(.45, .42, .42, 0, 1.86, 0, 0, colors.orange)
  b.box(.5, .14, .5, 0, 2.12, -.05, 0, cap)
  if role == "batR" or role == "batL" then
    local sx = role == "batR" and 1 or -1
    b.box(.12, 1.1, .12, sx * .3, 2.0, .2, 0, colors.brown)
  end
  return b.model
end

-- Furball draws a 0.07 m ball with an outline; the terminal needs a bigger stand-in.
function stadium.ballModel()
  local b = builder()
  local r = .22
  local ring = {{r, 0, 0}, {0, 0, r}, {-r, 0, 0}, {0, 0, -r}}
  for k = 1, 4 do
    b.tri(ring[k], ring[k % 4 + 1], {0, r, 0}, colors.white)
    b.tri(ring[k], ring[k % 4 + 1], {0, -r, 0}, colors.lightGray)
  end
  return b.model
end

-- Strike-zone frame at the plate, as drawn by furball (0.26 half width, 0.48-1.12 high).
function stadium.zoneModel()
  local b = builder()
  local hw, y0, y1, t = .26, .48, 1.12, .07
  b.quad({-hw - t, y0 - t, 0}, {hw + t, y0 - t, 0}, {hw + t, y0, 0}, {-hw - t, y0, 0}, colors.yellow)
  b.quad({-hw - t, y1, 0}, {hw + t, y1, 0}, {hw + t, y1 + t, 0}, {-hw - t, y1 + t, 0}, colors.yellow)
  b.quad({-hw - t, y0, 0}, {-hw, y0, 0}, {-hw, y1, 0}, {-hw - t, y1, 0}, colors.yellow)
  b.quad({hw, y0, 0}, {hw + t, y0, 0}, {hw + t, y1, 0}, {hw, y1, 0}, colors.yellow)
  return b.model
end

stadium.P = P
return stadium
