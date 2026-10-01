-- Furball golf kernel, ported line-for-line from furball-simulator src/sports/golf/golf-core.ts.
-- One fixed 1/120 s tick at a time: flight, tree deflection, bounce, rollout and cup capture.
-- Pure Lua: no terminal, peripheral, renderer or wall-clock dependencies.
local course = require("lib.course")
local golf = {}

golf.CLUB_ORDER = {"5i", "7i", "wedge", "putter"}
golf.CLUBS = {
  ["5i"] = {id = "5i", name = "5 iron", carry = 150, loft = 38},
  ["7i"] = {id = "7i", name = "7 iron", carry = 115, loft = 46},
  wedge = {id = "wedge", name = "Wedge", carry = 48, loft = 62},
  putter = {id = "putter", name = "Putter", carry = 32, loft = 0},
}
golf.STEP = 1 / 120
golf.MAX_TICKS = 30 / golf.STEP
local GRAVITY = 9.81
local FRICTION = {tee = 1.2, fairway = 1.05, rough = 3.2, sand = 6, green = 0.55}
local CUP_SPEED = 3
local CUP, HOLE, TREES = course.cup, course.hole, course.trees
local sqrt, sin, cos, PI = math.sqrt, math.sin, math.cos, math.pi
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function hypot(x, z) return sqrt(x * x + z * z) end
local function finite(n) return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge end

function golf.newHole()
  return {phase = "ready", ball = {x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0}, lie = "tee", strokes = 0,
    penalties = 0, ticks = 0, previous = {x = 0, z = 0},
    message = "On the tee. Choose a club, aim, set power, then strike.", lastCarry = 0, airborne = false}
end

function golf.copy(state)
  local b, p = state.ball, state.previous
  return {phase = state.phase, ball = {x = b.x, y = b.y, z = b.z, vx = b.vx, vy = b.vy, vz = b.vz}, lie = state.lie,
    strokes = state.strokes, penalties = state.penalties, ticks = state.ticks, previous = {x = p.x, z = p.z},
    message = state.message, lastCarry = state.lastCarry, airborne = state.airborne}
end

function golf.distanceToCup(state) return hypot(state.ball.x - CUP.x, state.ball.z - CUP.z) end
function golf.aimToCup(state) return atan2(CUP.x - state.ball.x, CUP.z - state.ball.z) * 180 / PI end

-- shot: {club, aim (degrees, 0 downrange, + right), power (0.5..100)}
function golf.strike(state, shot)
  if state.phase ~= "ready" or type(shot) ~= "table" or not golf.CLUBS[shot.club]
    or not finite(shot.power) or not finite(shot.aim) or shot.power < 0.5 or shot.power > 100 then return false end
  local club = golf.CLUBS[shot.club]
  local efficiency = state.lie == "rough" and 0.72 or state.lie == "sand" and (shot.club == "wedge" and 0.83 or 0.5) or 1
  local loft = club.loft * PI / 180
  local speed
  if shot.club == "putter" then
    speed = sqrt(2 * FRICTION.green * club.carry * shot.power / 100) * efficiency
  else
    speed = sqrt(club.carry * GRAVITY / sin(2 * loft) * shot.power / 100 * efficiency)
  end
  local angle = shot.aim * PI / 180
  state.previous = {x = state.ball.x, z = state.ball.z}
  state.ball.vx = sin(angle) * speed * cos(loft)
  state.ball.vz = cos(angle) * speed * cos(loft)
  state.ball.vy = speed * sin(loft)
  state.phase = "moving"
  state.strokes = state.strokes + 1
  state.ticks = 0
  state.lastCarry = 0
  state.airborne = shot.club ~= "putter"
  state.message = shot.club == "putter" and "Putting — ball rolling." or "Ball in flight."
  return true
end

local function settle(state)
  local b = state.ball
  b.y, b.vx, b.vy, b.vz = 0, 0, 0, 0
  if course.outside(b.x, b.z) then
    b.x = state.previous.x; b.z = state.previous.z
    state.strokes = state.strokes + 1; state.penalties = state.penalties + 1
    state.message = "Out of bounds. +1 penalty; replay from your previous lie."
  else
    state.message = ("Settled in %s. %.1f m to cup."):format(course.lieAt(b.x, b.z), golf.distanceToCup(state))
  end
  state.lie = course.lieAt(b.x, b.z)
  state.phase = "ready"
end

function golf.step(state)
  if state.phase ~= "moving" then return end
  local b = state.ball
  state.ticks = state.ticks + 1
  local oldX, oldZ = b.x, b.z
  if b.y > 0 or b.vy > 0 then
    b.vy = b.vy - GRAVITY * golf.STEP
    b.y = b.y + b.vy * golf.STEP
  end
  b.x = b.x + b.vx * golf.STEP; b.z = b.z + b.vz * golf.STEP
  for _, tree in ipairs(TREES) do
    if b.y < 8 and hypot(b.x - tree.x, b.z - tree.z) < tree.radius then
      b.x = oldX; b.z = oldZ; b.vx = b.vx * -0.35; b.vz = b.vz * -0.35
      state.message = "Tree trunk deflection."
      break
    end
  end
  if b.y <= 0 then
    b.y = 0
    state.lie = course.lieAt(b.x, b.z)
    if state.airborne then
      state.lastCarry = hypot(b.x - state.previous.x, b.z - state.previous.z)
      state.airborne = false
      state.message = ("Landed in %s; rolling."):format(state.lie)
    end
    local impactSpeed = b.vy
    if impactSpeed < 0 then
      local keep = state.lie == "sand" and 0.25 or 0.45
      b.vx = b.vx * keep; b.vz = b.vz * keep
    end
    if impactSpeed < -1.5 and state.lie ~= "sand" then
      b.vy = b.vy * -0.18
    else
      b.vy = 0
      local speed = hypot(b.vx, b.vz)
      local remaining = math.max(0, speed - FRICTION[state.lie] * golf.STEP)
      if speed > 0 then b.vx = b.vx * remaining / speed; b.vz = b.vz * remaining / speed end
      if golf.distanceToCup(state) <= HOLE.cupRadius and remaining <= CUP_SPEED then
        b.x = CUP.x; b.z = CUP.z; b.vx, b.vy, b.vz = 0, 0, 0
        state.phase = "finished"
        state.message = ("In the cup! Hole complete in %d %s."):format(state.strokes, state.strokes == 1 and "stroke" or "strokes")
        return
      end
      if remaining <= 0.025 then settle(state); return end
    end
  end
  -- A bounded shot cannot hang the turn. Out-of-bounds is decided at rest, not mid-flight.
  if state.ticks >= golf.MAX_TICKS then settle(state) end
end

-- Calm-weather prediction of a shot from a copy of the state; never touches the real state.
function golf.forecast(state, shot)
  local preview = golf.copy(state)
  local b = preview.ball
  local points = {{x = b.x, y = b.y, z = b.z}}
  if golf.strike(preview, shot) then
    while preview.phase == "moving" do
      golf.step(preview)
      if preview.ticks % 24 == 0 then points[#points + 1] = {x = b.x, y = b.y, z = b.z} end
    end
    points[#points + 1] = {x = b.x, y = b.y, z = b.z}
  end
  return points, preview
end

-- Furball's recovery choices after the ball settles: face the cup, putter on the green
-- with power scaled to distance, wedge from sand.
function golf.suggestion(state, current)
  local s = {club = current.club, aim = golf.aimToCup(state), power = current.power}
  if state.lie == "green" then
    s.club = "putter"
    s.power = math.max(0.5, math.min(100, math.floor(golf.distanceToCup(state) / 32 * 200 + 0.5) / 2))
  end
  if state.lie == "sand" then s.club = "wedge" end
  return s
end

function golf.scoreLabel(strokes)
  if strokes == 1 then return "Hole in one!" end
  if strokes == 2 then return "Birdie!" end
  if strokes == 3 then return "Par!" end
  return ("+%d over par"):format(strokes - 3)
end

return golf
