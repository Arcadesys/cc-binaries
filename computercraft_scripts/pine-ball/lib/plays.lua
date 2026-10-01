-- Furball match rules that sit above the pure kernel (src/game/match.ts and field.ts):
-- where each hit lands, which fielder chases it, whether a fly ball is caught, dropped
-- or reached late, runner paths, and the headline/detail callouts. Pure Lua, no clock.
local bb = require("lib.baseball")
local plays = {}

-- field.ts: metres, home at the origin, centre field toward -Z, first base toward +X.
plays.BASE_DISTANCE = 27.4
plays.MOUND_DISTANCE = 18.4
plays.WALL_DISTANCE = 95
plays.WALL_HEIGHT = 3.5
local DIAG = plays.BASE_DISTANCE / math.sqrt(2)
plays.BASES = {{x = 0, z = 0}, {x = DIAG, z = -DIAG}, {x = 0, z = -2 * DIAG}, {x = -DIAG, z = -DIAG}}

-- Named defensive spots, filled in this priority order.
plays.FIELDING_SPOTS = {
  {pos = "P", x = 0, z = -plays.MOUND_DISTANCE}, {pos = "C", x = 0, z = 1.4},
  {pos = "SS", x = -9, z = -33}, {pos = "1B", x = 18, z = -22}, {pos = "CF", x = 0, z = -78},
  {pos = "2B", x = 9, z = -33}, {pos = "3B", x = -18, z = -22}, {pos = "LF", x = -36, z = -64},
  {pos = "RF", x = 36, z = -64},
}

-- Where each result lands: spray angle (rad, - = left field), distance (m), apex (m).
plays.LANDING = {
  GROUND_OUT_LEFT = {angle = -0.4, dist = 32, apex = 0.6}, GROUND_OUT_RIGHT = {angle = 0.4, dist = 32, apex = 0.6},
  FLY_OUT_LEFT = {angle = -0.5, dist = 64, apex = 24}, FLY_OUT_CENTER = {angle = 0, dist = 76, apex = 26},
  FLY_OUT_RIGHT = {angle = 0.5, dist = 64, apex = 24},
  SINGLE_LEFT = {angle = -0.45, dist = 50, apex = 5}, SINGLE_CENTER = {angle = 0.05, dist = 52, apex = 5},
  SINGLE_RIGHT = {angle = 0.45, dist = 50, apex = 5},
  DOUBLE_LEFT_CENTER = {angle = -0.3, dist = 84, apex = 12}, DOUBLE_RIGHT_CENTER = {angle = 0.3, dist = 84, apex = 12},
  TRIPLE = {angle = 0.6, dist = 92, apex = 10}, TRIPLE_LEFT = {angle = -0.6, dist = 92, apex = 10},
  TRIPLE_CENTER = {angle = 0, dist = 92, apex = 10}, TRIPLE_RIGHT = {angle = 0.6, dist = 92, apex = 10},
  HOME_RUN_LEFT = {angle = -0.55, dist = 118, apex = 32}, HOME_RUN_CENTER = {angle = 0, dist = 125, apex = 34},
  HOME_RUN_RIGHT = {angle = 0.55, dist = 118, apex = 32},
  ERROR_LEFT = {angle = -0.5, dist = 64, apex = 24}, ERROR_CENTER = {angle = 0, dist = 76, apex = 26},
  ERROR_RIGHT = {angle = 0.5, dist = 64, apex = 24},
}

-- match.ts presentation timings (ms).
plays.INTRO_MS = 3200
plays.WINDUP_MS = 800
plays.PITCH_RESULT_MS = 900
plays.MISS_FEEDBACK_MS = 1400
plays.FLIGHT_MS = 1800
plays.IN_PLAY_HOLD_MS = 1300
plays.FOUL_FLIGHT_MS = 600
plays.FIELDING_SEED_SALT = 0x9e3779b9
plays.GROUND_GATHER_MS = 260
plays.GROUND_THROW_MS = 520

function plays.landingSpot(result)
  local land = plays.LANDING[result]
  return {x = math.sin(land.angle) * land.dist, z = -math.cos(land.angle) * land.dist}, land
end

local function side(result)
  if result:sub(-4) == "LEFT" then return "LEFT" elseif result:sub(-5) == "RIGHT" then return "RIGHT" end
  return "CENTER"
end
local function contains(s, part) return s:find(part, 1, true) ~= nil end

-- Fielders of the defending team, in spot order: {id, pos, x, z}.
function plays.fielders(state, roster)
  local out = {}
  for i, id in ipairs(roster[bb.fieldingTeam(state)]) do
    local spot = plays.FIELDING_SPOTS[i]
    if not spot then break end
    out[#out + 1] = {id = id, pos = spot.pos, x = spot.x, z = spot.z}
  end
  return out
end

-- match.ts aimFielder: nearest fielder (never pitcher or catcher) chases; fly outs roll a catch plan.
function plays.aimFielder(state, roster, result, settings, fieldingNext)
  local spot = plays.landingSpot(result)
  local defense = plays.fielders(state, roster)
  local best
  for i, f in ipairs(defense) do
    if i > 2 then
      local d = math.sqrt((f.x - spot.x) ^ 2 + (f.z - spot.z) ^ 2)
      if not best or d < best.d then best = {fielder = f, d = d} end
    end
  end
  if not best then return nil end
  local from = best.fielder
  -- Outs: the fielder gets there. Hits: they come up short.
  local reach = contains(result, "OUT") and 1 or result:sub(1, 8) == "HOME_RUN" and 0.35 or 0.6
  local to = {x = from.x + (spot.x - from.x) * reach, z = from.z + (spot.z - from.z) * reach}
  local len = math.sqrt(spot.x ^ 2 + spot.z ^ 2)
  if len > 95 then
    local tl = math.sqrt(to.x ^ 2 + to.z ^ 2)
    if tl > 92 then to.x, to.z = to.x / tl * 92, to.z / tl * 92 end
  end
  local plan = result:sub(1, 7) == "FLY_OUT" and bb.planCatch(best.d, plays.FLIGHT_MS, settings, fieldingNext()) or nil
  return {id = from.id, pos = from.pos, from = {x = from.x, z = from.z}, to = to, plan = plan}
end

-- match.ts beginInPlay: the fielding outcome may convert the kernel's result
-- (late -> single, dropped -> error) before the reducer applies it.
function plays.resolveInPlay(state, roster, result, settings, fieldingNext)
  local fielder = plays.aimFielder(state, roster, result, settings, fieldingNext)
  local outcome = fielder and fielder.plan and fielder.plan.outcome
  local s = side(result)
  local missingFielder = contains(result, "OUT") and not fielder
  local resolved = (missingFielder or outcome == "late") and ("SINGLE_" .. s) or outcome == "dropped" and ("ERROR_" .. s) or result
  local pending = bb.applyPitchEvent(state, {kind = "IN_PLAY", result = resolved})
  local groundThrow
  if not missingFielder and result:sub(1, 10) == "GROUND_OUT" then
    local base = 1
    for _, c in ipairs(pending.callouts) do if c == "FORCE_OUT" then base = 2 end end
    local defense = plays.fielders(state, roster)
    local want = base == 1 and "1B" or "2B"
    local receiver
    for _, f in ipairs(defense) do if f.pos == want and f.id ~= fielder.id then receiver = f end end
    if not receiver then for _, f in ipairs(defense) do if f.id ~= fielder.id then receiver = f; break end end end
    if receiver then
      groundThrow = {base = base, receiverId = receiver.id, receiverFrom = {x = receiver.x, z = receiver.z},
        releaseMs = plays.FLIGHT_MS + plays.GROUND_GATHER_MS, arrivalMs = plays.FLIGHT_MS + plays.GROUND_GATHER_MS + plays.GROUND_THROW_MS}
    end
  end
  if missingFielder or (result:sub(1, 10) == "GROUND_OUT" and not groundThrow) then
    -- An out needs a visible defender and, for a ground ball, a receiver.
    resolved = "SINGLE_" .. s
    pending = bb.applyPitchEvent(state, {kind = "IN_PLAY", result = resolved})
    result = resolved
    fielder = plays.aimFielder(state, roster, result, settings, fieldingNext)
  end
  return {result = result, resolved = resolved, pending = pending, fielder = fielder, groundThrow = groundThrow}
end

-- Diff two states into runner paths for animation. 0 = home ... 4 = scored.
function plays.runnerMoves(prev, t, batterId)
  local function where(s, id)
    return s.bases.first == id and 1 or s.bases.second == id and 2 or s.bases.third == id and 3 or nil
  end
  local ids = {batterId}
  for _, k in ipairs({"first", "second", "third"}) do if prev.bases[k] then ids[#ids + 1] = prev.bases[k] end end
  local sideRetired, scored = false, {}
  for _, c in ipairs(t.callouts) do if c == "SIDE_RETIRED" then sideRetired = true end end
  for _, id in ipairs(t.scored) do scored[id] = true end
  local moves = {}
  for _, id in ipairs(ids) do
    local from = id == batterId and 0 or where(prev, id)
    local move
    -- Clearing the bases at the third out does not mean every runner was put out.
    if sideRetired and id ~= batterId then move = {id = id, from = from, to = from, out = false}
    elseif scored[id] then move = {id = id, from = from, to = 4, out = false}
    else
      local to = not sideRetired and where(t.state, id) or nil
      move = to == nil and {id = id, from = from, to = from, out = true} or {id = id, from = from, to = to, out = false}
    end
    moves[#moves + 1] = move
  end
  return moves
end

-- Point along the basepath. 0 = home, 1 = first, ... 4 = home again.
function plays.basepathPoint(t)
  local c = math.max(0, math.min(4, t))
  local i = math.min(3, math.floor(c))
  local a, b = plays.BASES[i + 1], plays.BASES[(i + 1) % 4 + 1]
  return {x = a.x + (b.x - a.x) * (c - i), z = a.z + (b.z - a.z) * (c - i)}
end

function plays.headline(callouts, runsScored)
  local set = {}
  for _, c in ipairs(callouts) do set[c] = true end
  if set.WALK_OFF then return "WALK-OFF!!", true end
  if set.ERROR then return set.RUN_SCORED and "ERROR - RUN SCORES!" or "ERROR - SAFE!", true end
  if set.HOME_RUN then return runsScored == 4 and "GRAND SLAM!" or "HOME RUN!!", true end
  if set.TRIPLE then return "TRIPLE!", true end
  if set.DOUBLE then return "DOUBLE!", true end
  if set.SINGLE then return set.RUN_SCORED and "RBI SINGLE!" or "SINGLE!", false end
  if set.STRIKEOUT then return "STRIKE THREE!", true end
  if set.WALK then return "BALL FOUR", false end
  if set.FORCE_OUT then return "FORCE OUT", false end
  if set.OUT then return "OUT!", false end
  if set.STRIKE then return "STRIKE", false end
  if set.BALL then return "BALL", false end
  if set.FOUL then return "FOUL", false end
  return nil
end

-- match.ts commit(): the secondary line under the headline.
function plays.detail(t, prev, info)
  local runs = t.state.score.light + t.state.score.dark - prev.score.light - prev.score.dark
  local set = {}
  for _, c in ipairs(t.callouts) do set[c] = true end
  local playDetail
  if info.groundThrow then playDetail = "Throw to " .. (info.groundThrow.base == 1 and "first" or "second") .. " - Runner out"
  elseif info.miss and (set.STRIKE or set.STRIKEOUT) then playDetail = bb.missFeedback(info.miss.location, info.miss.offset)
  elseif info.fielding == "dropped" then playDetail = "Dropped catch - Safe at first"
  elseif info.fielding == "late" then playDetail = "Fielder arrived late" end
  local scoringOut = runs > 0 and (set.OUT or set.FORCE_OUT) and (runs .. (runs == 1 and " run scores" or " runs score")) or nil
  if playDetail and scoringOut then return playDetail .. " - " .. scoringOut end
  return playDetail or scoringOut, runs
end

return plays
