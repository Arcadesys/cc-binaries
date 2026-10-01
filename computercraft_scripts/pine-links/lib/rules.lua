-- Hole scoring. Strokes and the out-of-bounds penalty are counted by the furball kernel
-- (lib/golf.lua); this module commits a finished shot exactly once and names the score.
local golf = require("lib.golf")
local rules = {}

function rules.new()
  return {hole = golf.newHole(), lastShotId = 0}
end

-- Idempotent: a shot id is applied once, in order. The result's state replaces the hole state.
function rules.apply(round, shotId, result)
  if type(round) ~= "table" or type(result) ~= "table" then return false, "round and result are required" end
  if round.hole.phase == "finished" then return false, "hole is already complete" end
  if type(shotId) ~= "number" or shotId < 1 or shotId % 1 ~= 0 then return false, "shot id must be a positive integer" end
  if shotId <= round.lastShotId then return false, "shot already applied or out of order" end
  if type(result.state) ~= "table" or (result.state.phase ~= "ready" and result.state.phase ~= "finished") then
    return false, "shot has not come to rest"
  end
  round.lastShotId = shotId
  round.hole = golf.copy(result.state)
  return true
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
