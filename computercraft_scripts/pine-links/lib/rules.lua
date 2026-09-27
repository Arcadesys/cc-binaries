-- Small, idempotent arcade scoring rules for a single hole.
local rules = {}

local function position(p)
  if type(p) ~= "table" then return nil end
  return { x = p.x, y = p.y, z = p.z }
end

function rules.new(tee)
  local ball = position(tee)
  if not ball then ball = { x = 0, y = 0, z = 0 } end
  return { ball = ball, strokes = 0, penalties = 0, complete = false, lastShotId = 0 }
end

function rules.apply(state, shotId, result, preShot)
  if type(state) ~= "table" or type(result) ~= "table" then return false, "state and result are required" end
  if state.complete then return false, "hole is already complete" end
  if type(shotId) ~= "number" or shotId < 1 or shotId % 1 ~= 0 then return false, "shot id must be a positive integer" end
  if shotId <= (state.lastShotId or 0) then return false, "shot already applied or out of order" end
  if result.outcome == "error" then
    state.lastShotId = shotId
    return true, "error"
  end
  if result.outcome ~= "rest" and result.outcome ~= "holed" and result.outcome ~= "water" and result.outcome ~= "ob" then
    return false, "unknown shot outcome"
  end
  state.lastShotId = shotId

  state.strokes = (state.strokes or 0) + 1
  if result.outcome == "water" or result.outcome == "ob" then
    -- Arcade hazard rule: the shot counts, then one penalty stroke is added.
    state.strokes = state.strokes + 1
    state.penalties = (state.penalties or 0) + 1
    state.ball = position(preShot) or position(state.ball) or { x = 0, y = 0, z = 0 }
    state.complete = false
  else
    state.ball = position(result.position) or position(state.ball)
    state.complete = result.outcome == "holed"
  end
  return true, state
end

function rules.scoreName(strokes, par)
  if type(strokes) ~= "number" or type(par) ~= "number" or par < 1 then return "Unknown" end
  local delta = strokes - par
  if strokes == 1 and par > 1 then return "Hole in one" end
  if delta <= -3 then return "Albatross" end
  if delta == -2 then return "Eagle" end
  if delta == -1 then return "Birdie" end
  if delta == 0 then return "Par" end
  if delta == 1 then return "Bogey" end
  if delta == 2 then return "Double bogey" end
  return tostring(delta) .. " over par"
end

return rules
