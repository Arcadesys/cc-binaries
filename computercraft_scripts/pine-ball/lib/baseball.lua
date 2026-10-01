-- Furball baseball kernel, ported line-for-line from furball-simulator src/sim/
-- (constants.ts, batting.ts, gameState.ts, fielding.ts, pitching.ts). Outcome first;
-- the renderer animates it afterward. Pure Lua: no terminal, peripheral or clock.
local rng = require("lib.rng")
local bb = {}

-- constants.ts --------------------------------------------------------------
bb.DEFAULT_INNINGS = 3
bb.OUTS_PER_HALF = 3
bb.BALLS_FOR_WALK = 4
bb.STRIKES_FOR_STRIKEOUT = 3
bb.PITCH_TYPES = {"fastball", "changeup", "curve_left", "curve_right"}
bb.PITCH_TRAVEL_MS = {fastball = 620, changeup = 860, curve_left = 760, curve_right = 760}
bb.PITCH_BREAK = {fastball = 0, changeup = 0, curve_left = -0.9, curve_right = 0.9}
bb.PERFECT_WINDOW_MS = 25
bb.GOOD_WINDOW_MS = 60
bb.CONTACT_WINDOW_MS = 110
bb.OUT_OF_ZONE_WINDOW_SCALE = 0.6
bb.MAX_REACH = 1.6
bb.FULL_PULL_OFFSET_MS = 80
-- swingPresentation.ts: quality is judged at input + 80 ms, when the bat crosses the plate.
bb.SWING_DRIVE_MS = 80
bb.SWING_DURATION_MS = 80 + 240
-- pitching.ts
bb.PITCH_LOCATION_LIMIT = 1.5
bb.PITCH_AIM_STEP = 0.25

local abs, max, min, floor = math.abs, math.max, math.min, math.floor
local function finite(n) return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge end
local function copy(v)
  if type(v) ~= "table" then return v end
  local o = {}; for k, x in pairs(v) do o[k] = copy(x) end; return o
end
bb.copy = copy

-- batting.ts ----------------------------------------------------------------
function bb.isStrike(loc) return abs(loc.x) <= 1 and abs(loc.y) <= 1 end

-- Keep borderline pitches forgiving, tapering to the chase penalty at maximum reach.
function bb.contactWindowScale(loc)
  local reach = max(abs(loc.x), abs(loc.y))
  if reach > bb.MAX_REACH then return 0 end
  local outside = max(0, (reach - 1) / (bb.MAX_REACH - 1))
  return 1 - outside * (1 - bb.OUT_OF_ZONE_WINDOW_SCALE)
end

function bb.contactTier(loc, timingOffsetMs)
  local scale = bb.contactWindowScale(loc)
  if scale == 0 then return nil end
  local off = abs(timingOffsetMs)
  if off <= bb.PERFECT_WINDOW_MS * scale then return "perfect" end
  if off <= bb.GOOD_WINDOW_MS * scale then return "good" end
  if off <= bb.CONTACT_WINDOW_MS * scale then return "weak" end
  return nil
end

local OUTCOMES = {"GROUND_OUT", "FLY_OUT", "SINGLE", "DOUBLE", "TRIPLE", "HOME_RUN"}
local OUTCOME_WEIGHTS = {
  perfect = {GROUND_OUT = 8, FLY_OUT = 14, SINGLE = 26, DOUBLE = 20, TRIPLE = 4, HOME_RUN = 28},
  good = {GROUND_OUT = 24, FLY_OUT = 24, SINGLE = 32, DOUBLE = 12, TRIPLE = 2, HOME_RUN = 6},
  weak = {GROUND_OUT = 44, FLY_OUT = 32, SINGLE = 20, DOUBLE = 3, TRIPLE = 0.5, HOME_RUN = 0.5},
}
local LIFT_BIAS = 0.5

-- Early swings pull, late swings go the other way; aim adds a nudge.
function bb.sprayDirection(swing, next)
  local offset = swing.timingOffsetMs or 0
  local pullSide = swing.bats == "R" and -1 or 1 -- righties pull to left field (-x)
  local timingPush = max(-1, min(1, -offset / bb.FULL_PULL_OFFSET_MS)) * pullSide
  local value = timingPush * 0.7 + swing.aim.x * 0.6 + (next() - 0.5) * 0.6
  if value < -0.33 then return "LEFT" end
  if value > 0.33 then return "RIGHT" end
  return "CENTER"
end

function bb.resolveBallInPlay(tier, swing, next)
  local base = OUTCOME_WEIGHTS[tier]
  local lift = swing.aim.y * LIFT_BIAS
  local weights = {
    {"GROUND_OUT", base.GROUND_OUT * (1 - lift)},
    {"FLY_OUT", base.FLY_OUT * (1 + lift)},
    {"SINGLE", base.SINGLE * (1 - lift * 0.5)},
    {"DOUBLE", base.DOUBLE * (1 + lift * 0.5)},
    {"TRIPLE", base.TRIPLE},
    {"HOME_RUN", base.HOME_RUN * (1 + lift)},
  }
  local outcome = rng.weighted(next, weights)
  local field = bb.sprayDirection(swing, next)
  if outcome == "GROUND_OUT" then
    if field == "LEFT" then return "GROUND_OUT_LEFT" elseif field == "RIGHT" then return "GROUND_OUT_RIGHT" end
    return rng.pick(next, {"GROUND_OUT_LEFT", "GROUND_OUT_RIGHT"})
  elseif outcome == "DOUBLE" then
    if field == "LEFT" then return "DOUBLE_LEFT_CENTER" elseif field == "RIGHT" then return "DOUBLE_RIGHT_CENTER" end
    return rng.pick(next, {"DOUBLE_LEFT_CENTER", "DOUBLE_RIGHT_CENTER"})
  end
  return outcome .. "_" .. field
end

-- swing: {timingOffsetMs = number|nil (nil = took the pitch), aim = {x, y}, bats = "L"|"R"}
function bb.resolvePitch(pitch, swing, next)
  if swing.timingOffsetMs == nil then
    return bb.isStrike(pitch.location) and {kind = "CALLED_STRIKE"} or {kind = "BALL"}
  end
  local tier = bb.contactTier(pitch.location, swing.timingOffsetMs)
  if not tier then return {kind = "SWINGING_STRIKE"} end
  -- Weak contact is frequently fouled off.
  if tier == "weak" and next() < 0.55 then return {kind = "FOUL"} end
  if tier == "good" and next() < 0.15 then return {kind = "FOUL"} end
  return {kind = "IN_PLAY", result = bb.resolveBallInPlay(tier, swing, next)}
end

local function sign1(v) if v < 0 then return -1 end return 1 end

-- Simple CPU pitcher: mostly strikes, sometimes chases.
function bb.cpuPitch(next)
  local kind = rng.pick(next, bb.PITCH_TYPES)
  local inZone = next() < 0.62
  local spread = inZone and 0.95 or 1.55
  local x = (next() * 2 - 1) * spread
  local y = (next() * 2 - 1) * spread
  if not inZone and abs(x) <= 1 and abs(y) <= 1 then
    -- Push a "ball" out of the zone on one axis.
    if next() < 0.5 then x = sign1(x) * (1.1 + next() * 0.4)
    else y = sign1(y) * (1.1 + next() * 0.4) end
  end
  return {type = kind, location = {x = x, y = y}}
end

-- Furball's miss coaching (game/battingFeedback.ts).
function bb.missFeedback(location, offsetMs)
  local reach = max(abs(location.x), abs(location.y))
  if reach > bb.MAX_REACH or (reach > 1 and abs(offsetMs) <= bb.CONTACT_WINDOW_MS) then
    return "Outside pitch - Let it pass"
  end
  return offsetMs < 0 and "Early - Wait a beat" or "Late - Swing sooner"
end

-- pitching.ts ---------------------------------------------------------------
function bb.copyPlayerPitch(pitch)
  if type(pitch) ~= "table" or not bb.PITCH_TRAVEL_MS[pitch.type] or type(pitch.location) ~= "table" then return nil end
  local x, y = pitch.location.x, pitch.location.y
  if not (finite(x) and finite(y) and abs(x) <= bb.PITCH_LOCATION_LIMIT and abs(y) <= bb.PITCH_LOCATION_LIMIT) then return nil end
  return {type = pitch.type, location = {x = x, y = y}}
end

-- gameState.ts --------------------------------------------------------------
function bb.battingTeam(state) return state.half == "top" and "light" or "dark" end
function bb.fieldingTeam(state) return state.half == "top" and "dark" or "light" end

function bb.currentBatter(state)
  local team = bb.battingTeam(state)
  local queue = state.battingQueue[team]
  if #queue == 0 then error(team .. " has no batters") end
  return queue[state.batterIndex[team] % #queue + 1]
end

function bb.createGame(battingQueue, totalInnings)
  return {totalInnings = totalInnings or bb.DEFAULT_INNINGS, inning = 1, half = "top", outs = 0, balls = 0, strikes = 0,
    score = {light = 0, dark = 0}, bases = {}, battingQueue = {light = copy(battingQueue.light), dark = copy(battingQueue.dark)},
    batterIndex = {light = 0, dark = 0}, status = "playing"}
end

local function push(t, callout) t.callouts[#t.callouts + 1] = callout end
local function has(t, callout) for _, c in ipairs(t.callouts) do if c == callout then return true end end return false end

local function score(t, runner)
  t.state.score[bb.battingTeam(t.state)] = t.state.score[bb.battingTeam(t.state)] + 1
  t.scored[#t.scored + 1] = runner
  push(t, "RUN_SCORED")
end

local function recordOut(t) t.state.outs = t.state.outs + 1 end

-- Batter takes first; only forced runners move (walks, fielder's choice).
local function forceAdvance(t, batter)
  local b = t.state.bases
  if b.first then
    if b.second then
      if b.third then score(t, b.third) end
      b.third = b.second
    end
    b.second = b.first
  end
  b.first = batter
end

local function placeRunner(t, bases, runner, base)
  if base >= 4 then score(t, runner)
  elseif base == 3 then bases.third = runner
  elseif base == 2 then bases.second = runner
  else bases.first = runner end
end

-- Arcade rule: every runner advances exactly as many bases as the hit.
local function advanceAll(t, batter, count)
  local b = t.state.bases
  local order = {b.third, b.second, b.first}
  local startBase = {3, 2, 1}
  local nextBases = {}
  for i = 1, 3 do
    if order[i] then placeRunner(t, nextBases, order[i], startBase[i] + count) end
  end
  placeRunner(t, nextBases, batter, count)
  t.state.bases = nextBases
end

local function startsWith(s, prefix) return s:sub(1, #prefix) == prefix end

local function applyBallInPlay(t, result)
  local batter = bb.currentBatter(t.state)
  if startsWith(result, "ERROR") then
    -- Simple arcade error: batter and every existing runner advance one base.
    push(t, "ERROR"); advanceAll(t, batter, 1); return
  end
  if startsWith(result, "GROUND_OUT") then
    -- Basic force play at second with a runner on first and fewer than two outs.
    if t.state.bases.first and t.state.outs < bb.OUTS_PER_HALF - 1 then
      push(t, "FORCE_OUT"); forceAdvance(t, batter); t.state.bases.second = nil; recordOut(t)
    else
      push(t, "OUT"); recordOut(t)
    end
    return
  end
  if startsWith(result, "FLY_OUT") then push(t, "OUT"); recordOut(t); return end
  local hitBases = startsWith(result, "SINGLE") and 1 or startsWith(result, "DOUBLE") and 2 or startsWith(result, "TRIPLE") and 3 or 4
  push(t, ({"SINGLE", "DOUBLE", "TRIPLE", "HOME_RUN"})[hitBases])
  advanceAll(t, batter, hitBases)
end

local function endPlateAppearance(t)
  local s = t.state
  local team = bb.battingTeam(s)
  t.plateAppearanceOver = true
  s.batterIndex[team] = (s.batterIndex[team] + 1) % max(1, #s.battingQueue[team])
  s.balls = 0; s.strikes = 0
  if s.outs >= bb.OUTS_PER_HALF then
    push(t, "SIDE_RETIRED")
    s.outs = 0; s.bases = {}
    if s.half == "top" then s.half = "bottom" else s.half = "top"; s.inning = s.inning + 1 end
  end
end

local function checkGameOver(t)
  local s = t.state
  local light, dark = s.score.light, s.score.dark
  local inFinalInnings = s.inning >= s.totalInnings
  -- Walk-off: home team takes the lead in the bottom of the final (or extra) inning.
  if s.half == "bottom" and inFinalInnings and dark > light and #t.scored > 0 then
    s.status = "final"; push(t, "WALK_OFF"); push(t, "GAME_OVER"); return
  end
  -- Just flipped to the bottom of the final inning with the home team already ahead.
  if s.half == "bottom" and inFinalInnings and s.outs == 0 and has(t, "SIDE_RETIRED") and dark > light then
    s.status = "final"; push(t, "GAME_OVER"); return
  end
  -- Completed a full final (or extra) inning without a tie.
  if s.half == "top" and s.inning > s.totalInnings and has(t, "SIDE_RETIRED") and light ~= dark then
    s.inning = s.inning - 1; s.half = "bottom"; s.status = "final"; push(t, "GAME_OVER")
  end
end

-- Pure reducer: apply one pitch outcome. Returns {state, callouts, scored, plateAppearanceOver}.
function bb.applyPitchEvent(prev, event)
  if prev.status == "final" then return {state = prev, callouts = {}, scored = {}, plateAppearanceOver = false} end
  local t = {state = copy(prev), callouts = {}, scored = {}, plateAppearanceOver = false}
  local s = t.state
  local kind = event.kind
  if kind == "BALL" then
    s.balls = s.balls + 1
    if s.balls >= bb.BALLS_FOR_WALK then
      push(t, "WALK"); forceAdvance(t, bb.currentBatter(s)); endPlateAppearance(t)
    else push(t, "BALL") end
  elseif kind == "CALLED_STRIKE" or kind == "SWINGING_STRIKE" then
    s.strikes = s.strikes + 1
    if s.strikes >= bb.STRIKES_FOR_STRIKEOUT then
      push(t, "STRIKEOUT"); recordOut(t); endPlateAppearance(t)
    else push(t, "STRIKE") end
  elseif kind == "FOUL" then
    push(t, "FOUL")
    if s.strikes < bb.STRIKES_FOR_STRIKEOUT - 1 then s.strikes = s.strikes + 1 end
  elseif kind == "IN_PLAY" then
    applyBallInPlay(t, event.result); endPlateAppearance(t)
  end
  checkGameOver(t)
  return t
end

-- fielding.ts ---------------------------------------------------------------
bb.DEFAULT_FIELDING = {reactionMs = 180, runSpeed = 9, catchChance = 0.94}
bb.CATCH_ATTEMPT_MS = 200

-- Resolve once, then animate this plan. No frame-rate-dependent catch rolls.
function bb.planCatch(distance, flightMs, settings, roll)
  local arrivalMs
  if distance == 0 then arrivalMs = settings.reactionMs
  elseif settings.runSpeed == 0 then arrivalMs = nil
  else arrivalMs = settings.reactionMs + distance / settings.runSpeed * 1000 end
  local outcome = (arrivalMs == nil or arrivalMs > flightMs) and "late" or roll < settings.catchChance and "caught" or "dropped"
  return {settings = settings, distance = distance, flightMs = flightMs, arrivalMs = arrivalMs, roll = roll, outcome = outcome}
end

function bb.pursuitProgress(plan, elapsedMs)
  if elapsedMs < plan.settings.reactionMs then return 0 end
  if plan.distance == 0 then return 1 end
  return min(1, (elapsedMs - plan.settings.reactionMs) / 1000 * plan.settings.runSpeed / plan.distance)
end

return bb
