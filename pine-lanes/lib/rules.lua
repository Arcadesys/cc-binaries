-- Standard ten-pin scoring and frame-by-frame local match progression.
local rules = {}

local function finite(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function integer(n)
  return finite(n) and n == math.floor(n)
end

local function copyPose(p)
  return {id=p.id,x=p.x,z=p.z,angle=p.angle,tilt=p.tilt,down=false}
end

local function copyRack(rack)
  local out = {}
  for i, p in ipairs(rack) do out[i] = copyPose(p) end
  return out
end

local function validateRack(rack, expectedCount)
  if type(rack) ~= "table" or #rack ~= expectedCount then return false, "invalid rack size" end
  local seen = {}
  for _, p in ipairs(rack) do
    if type(p) ~= "table" or not integer(p.id) or p.id < 1 or p.id > 10 or seen[p.id]
      or not finite(p.x) or not finite(p.z) or not finite(p.angle) or not finite(p.tilt)
      or (p.down ~= nil and type(p.down) ~= "boolean") then
      return false, "invalid pin pose"
    end
    seen[p.id] = true
  end
  return true
end

local function newRack()
  local ok, lane = pcall(require, "lib.lane")
  if not ok or type(lane) ~= "table" or type(lane.newRack) ~= "function" then
    return nil, "lib.lane.newRack is unavailable"
  end
  local called, rack = pcall(lane.newRack)
  if not called then return nil, "could not reset pins: " .. tostring(rack) end
  local valid, err = validateRack(rack, 10)
  if not valid then return nil, "invalid fresh rack: " .. err end
  return copyRack(rack)
end

local function playerComplete(player)
  return player.complete == true
end

function rules.new(playerCount)
  if not integer(playerCount) or playerCount < 1 or playerCount > 4 then
    return nil, "playerCount must be an integer from 1 to 4"
  end
  local rack, err = newRack()
  if not rack then return nil, err end
  local players = {}
  for i = 1, playerCount do
    local rolls = {}
    for frame = 1, 10 do rolls[frame] = {} end
    players[i] = {id=i,rolls=rolls,complete=false}
  end
  return {
    playerCount=playerCount,currentPlayer=1,frame=1,ballNumber=1,
    rack=rack,complete=false,players=players,lastDeliveryId=0
  }
end

local function flatten(player)
  local out = {}
  for frame = 1, 10 do
    for _, pins in ipairs(player.rolls[frame]) do out[#out+1] = pins end
  end
  return out
end

local function tenthComplete(rolls)
  if #rolls < 2 then return false end
  if rolls[1] == 10 or rolls[1] + rolls[2] == 10 then return #rolls >= 3 end
  return true
end

local function marksFor(frame, rolls)
  local marks = {}
  for i, pins in ipairs(rolls) do
    if frame < 10 then
      if i == 1 and pins == 10 then marks[i] = "X"
      elseif i == 2 and rolls[1] + pins == 10 then marks[i] = "/"
      elseif pins == 0 then marks[i] = "-"
      else marks[i] = pins end
    elseif i == 1 then
      marks[i] = pins == 10 and "X" or (pins == 0 and "-" or pins)
    elseif i == 2 then
      if rolls[1] == 10 then marks[i] = pins == 10 and "X" or (pins == 0 and "-" or pins)
      elseif rolls[1] + pins == 10 then marks[i] = "/"
      elseif pins == 0 then marks[i] = "-"
      else marks[i] = pins end
    elseif i == 3 then
      if rolls[1] == 10 and rolls[2] < 10 and rolls[2] + pins == 10 then marks[i] = "/"
      elseif pins == 10 then marks[i] = "X"
      elseif pins == 0 then marks[i] = "-"
      else marks[i] = pins end
    end
  end
  return marks
end

function rules.score(player)
  if type(player) ~= "table" or type(player.rolls) ~= "table" then return nil, "invalid player" end
  local allRolls = flatten(player)
  local frames = {}
  local cursor = 1
  local subtotal, pending, cumulative, cumulativeResolved = 0, false, 0, true
  for frame = 1, 10 do
    local rolls = player.rolls[frame] or {}
    local score
    if frame < 10 then
      if #rolls > 0 then
        if rolls[1] == 10 then
          if allRolls[cursor+1] ~= nil and allRolls[cursor+2] ~= nil then
            score = 10 + allRolls[cursor+1] + allRolls[cursor+2]
          end
        elseif #rolls >= 2 then
          if rolls[1] + rolls[2] == 10 then
            if allRolls[cursor+2] ~= nil then score = 10 + allRolls[cursor+2] end
          else score = rolls[1] + rolls[2] end
        end
      end
    elseif tenthComplete(rolls) then
      score = rolls[1] + rolls[2] + (rolls[3] or 0)
    end
    local marks = marksFor(frame, rolls)
    local frameRolls = {}
    for i, pins in ipairs(rolls) do frameRolls[i] = pins end
    frames[frame] = {rolls=frameRolls,marks=marks,score=score,cumulative=nil}
    if score == nil then
      pending = true
      cumulativeResolved = false
    else
      subtotal = subtotal + score
      if cumulativeResolved then
        cumulative = cumulative + score
        frames[frame].cumulative = cumulative
      end
    end
    cursor = cursor + #rolls
  end
  return {frames=frames,total=subtotal,pending=pending}
end

local function expectedRoll(player, frame, ball)
  local rolls = player.rolls[frame]
  if frame < 10 then
    if ball == 1 then return 10 end
    return 10 - rolls[1]
  end
  if ball == 1 then return 10 end
  if ball == 2 then return rolls[1] == 10 and 10 or (10-rolls[1]) end
  if rolls[1] == 10 and rolls[2] < 10 then return 10-rolls[2] end
  return 10
end

local function tenthNeedsBonus(rolls)
  return rolls[1] == 10 or (rolls[1] ~= nil and rolls[2] ~= nil and rolls[1] + rolls[2] == 10)
end

local function validResult(match, deliveryId, result)
  if not integer(match.playerCount) or match.playerCount < 1 or match.playerCount > 4
    or #match.players ~= match.playerCount
    or not integer(match.currentPlayer) or match.currentPlayer < 1 or match.currentPlayer > match.playerCount
    or not integer(match.frame) or match.frame < 1 or match.frame > 10
    or not integer(match.ballNumber) or match.ballNumber < 1 or match.ballNumber > 3 then
    return nil, "invalid match turn state"
  end
  if not integer(deliveryId) or deliveryId < 1 then return nil, "deliveryId must be a positive integer" end
  if deliveryId <= match.lastDeliveryId then return nil, "duplicate or stale delivery" end
  if match.complete then return nil, "match is complete" end
  if type(result) ~= "table" or result.deliveryId ~= deliveryId then return nil, "result deliveryId mismatch" end
  if result.status ~= "ok" then return nil, "result is not successful" end
  if not finite(result.duration) or result.duration < 0 then return nil, "invalid result duration" end
  if type(result.knocked) ~= "table" or type(result.standing) ~= "table" then return nil, "missing pin partition" end
  local ok, err = validateRack(match.rack, #match.rack)
  if not ok then return nil, "invalid current rack: " .. err end
  local current = {}
  for _, p in ipairs(match.rack) do current[p.id] = true end
  local knocked, knockedCount = {}, 0
  for _, id in ipairs(result.knocked) do
    if not integer(id) or not current[id] or knocked[id] then return nil, "invalid knocked pin id" end
    knocked[id], knockedCount = true, knockedCount + 1
  end
  local standing, standingCount = {}, 0
  for _, p in ipairs(result.standing) do
    if type(p) ~= "table" or not integer(p.id) or not current[p.id] or knocked[p.id] or standing[p.id]
      or not finite(p.x) or not finite(p.z) or not finite(p.angle) or not finite(p.tilt)
      or (p.down ~= nil and p.down ~= false) then return nil, "invalid standing pin pose" end
    standing[p.id], standingCount = true, standingCount + 1
  end
  if knockedCount + standingCount ~= #match.rack then return nil, "knocked and standing pins do not partition the rack" end
  for id in pairs(current) do
    if not knocked[id] and not standing[id] then return nil, "pin missing from result partition" end
  end
  local player, frame, ball = match.players[match.currentPlayer], match.frame, match.ballNumber
  if not player or player.complete or type(player.rolls) ~= "table" or type(player.rolls[frame]) ~= "table" then return nil, "invalid current turn" end
  local expectedCount = frame < 10 and (ball == 1 and 0 or 1) or (ball - 1)
  if #player.rolls[frame] ~= expectedCount then return nil, "roll does not match current turn" end
  if frame == 10 and ball == 3 and not tenthNeedsBonus(player.rolls[10]) then return nil, "unexpected tenth-frame bonus" end
  local pins = expectedRoll(player, frame, ball)
  if #match.rack ~= pins then return nil, "current rack does not match the legal pin count for this ball" end
  if knockedCount > pins then return nil, "roll exceeds remaining pins" end
  return {player=player,frame=frame,ball=ball,pins=knockedCount,standing=result.standing}
end

local function shouldResetRack(frame, ball, rolls, pins)
  if frame < 10 then return ball == 1 and pins == 10 or ball == 2 end
  if ball == 1 then return pins == 10 end
  if ball == 2 then
    if rolls[1] == 10 then return pins == 10 end
    return rolls[1] + pins == 10
  end
  return false
end

function rules.apply(match, deliveryId, result)
  if type(match) ~= "table" or type(match.players) ~= "table" or type(match.currentPlayer) ~= "number"
    or type(match.lastDeliveryId) ~= "number" then return false, "invalid match" end
  local accepted, err = validResult(match, deliveryId, result)
  if not accepted then return false, err end
  local player, frame, ball = accepted.player, accepted.frame, accepted.ball
  local nextRolls = {}
  for i, pins in ipairs(player.rolls[frame]) do nextRolls[i] = pins end
  nextRolls[#nextRolls+1] = accepted.pins

  local turnEnds = false
  if frame < 10 then
    turnEnds = ball == 1 and accepted.pins == 10 or ball == 2
  elseif ball == 1 then turnEnds = false
  elseif ball == 2 then turnEnds = not (nextRolls[1] == 10 or nextRolls[1] + nextRolls[2] == 10)
  else turnEnds = true end

  local nextRack
  local finalMatchBall = turnEnds and frame == 10 and match.currentPlayer == match.playerCount
  if shouldResetRack(frame, ball, nextRolls, accepted.pins) or (turnEnds and not finalMatchBall) then
    nextRack, err = newRack()
    if not nextRack then return false, err end
  else
    nextRack = {}
    for _, p in ipairs(accepted.standing) do nextRack[#nextRack+1] = copyPose(p) end
  end

  -- All potentially failing validation and rack creation is complete; commit together.
  player.rolls[frame] = nextRolls
  match.rack = nextRack
  match.lastDeliveryId = deliveryId
  if frame == 10 and turnEnds then player.complete = true end
  if turnEnds then
    local nextPlayer = match.currentPlayer + 1
    local nextFrame = frame
    if nextPlayer > match.playerCount then nextPlayer, nextFrame = 1, frame + 1 end
    if nextFrame > 10 then
      match.complete = true
      -- Keep the final player/frame visible for the final scorecard.
    else
      match.currentPlayer, match.frame, match.ballNumber = nextPlayer, nextFrame, 1
    end
  else
    match.ballNumber = ball + 1
  end
  return true
end

function rules.rankings(match)
  local out = {}
  if type(match) ~= "table" or type(match.players) ~= "table" then return out end
  for i, player in ipairs(match.players) do
    local score = rules.score(player)
    if not score.pending then out[#out+1] = {player=i,total=score.total} end
  end
  table.sort(out, function(a,b)
    if a.total == b.total then return a.player < b.player end
    return a.total > b.total
  end)
  local place = 0
  for i, entry in ipairs(out) do
    if i == 1 or entry.total ~= out[i-1].total then place = i end
    entry.place = place
  end
  return out
end

return rules
