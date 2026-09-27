local rules = require("lib.rules")

local function check(value, message)
  if not value then error(message or "assertion failed", 2) end
end

local function makeResult(match, id, count)
  local knocked, standing = {}, {}
  for i, pin in ipairs(match.rack) do
    if i <= count then knocked[#knocked+1] = pin.id
    else standing[#standing+1] = {id=pin.id,x=pin.x,z=pin.z,angle=pin.angle,tilt=pin.tilt,down=false} end
  end
  return {deliveryId=id,status="ok",knocked=knocked,standing=standing,duration=0.25}
end

local function deliver(match, id, count)
  local ok, err = rules.apply(match,id,makeResult(match,id,count))
  check(ok, "delivery rejected: "..tostring(err))
end

local function playGame(rolls)
  local match, err = rules.new(1)
  check(match, err)
  local id=0
  for _, pins in ipairs(rolls) do id=id+1; deliver(match,id,pins) end
  check(match.complete, "scripted game did not complete")
  return match, rules.score(match.players[1])
end

local function zeros()
  local rolls={}
  for _=1,20 do rolls[#rolls+1]=0 end
  return rolls
end

local function nines()
  local rolls={}
  for _=1,20 do rolls[#rolls+1]=4 end
  for i=2,20,2 do rolls[i]=5 end
  return rolls
end

local function spares150()
  local rolls={}
  for _=1,9 do rolls[#rolls+1]=5; rolls[#rolls+1]=5 end
  rolls[#rolls+1]=5; rolls[#rolls+1]=5; rolls[#rolls+1]=5
  return rolls
end

local function perfect()
  local rolls={}
  for _=1,12 do rolls[#rolls+1]=10 end
  return rolls
end

local function mixed150()
  return {10,8,1,6,4,5,4,10,10,6,0,7,3,4,4,10,10,8}
end

local zeroMatch, zeroScore = playGame(zeros())
check(zeroScore.total==0 and not zeroScore.pending,"all-gutter game must score 0")
check(zeroScore.frames[1].marks[1]=="-" and #zeroScore.frames==10,"zero marks and ten frames")
local _, ninety = playGame(nines())
check(ninety.total==90,"open game must score 90")
local _, oneFifty = playGame(spares150())
check(oneFifty.total==150,"all-spare game must score 150")
local _, threeHundred = playGame(perfect())
check(threeHundred.total==300,"perfect game must score 300")
local mixedMatch, mixed = playGame(mixed150())
check(mixed.total==150,"mixed game must score 150, got "..tostring(mixed.total))
check(mixed.frames[10].rolls[1]==10 and mixed.frames[10].rolls[2]==10 and mixed.frames[10].rolls[3]==8,"tenth strike bonuses retained")
check(mixed.frames[10].marks[1]=="X" and mixed.frames[10].marks[2]=="X" and mixed.frames[10].marks[3]==8,"tenth strike marks")

local function prefixThroughNine(firstTenth)
  local m=assert(rules.new(1)); local id=0
  for _=1,9 do id=id+1; deliver(m,id,0); id=id+1; deliver(m,id,0) end
  id=id+1; deliver(m,id,firstTenth)
  return m,id
end

local tenthXX7,idXX7=prefixThroughNine(10)
idXX7=idXX7+1; deliver(tenthXX7,idXX7,10)
idXX7=idXX7+1; deliver(tenthXX7,idXX7,7)
local sx=rules.score(tenthXX7.players[1])
check(sx.frames[10].rolls[1]==10 and sx.frames[10].rolls[2]==10 and sx.frames[10].rolls[3]==7 and sx.frames[10].score==27,"10th X/X/7")

local tenthX73,idX73=prefixThroughNine(10)
idX73=idX73+1; deliver(tenthX73,idX73,7)
idX73=idX73+1; deliver(tenthX73,idX73,3)
local x73=rules.score(tenthX73.players[1])
check(x73.frames[10].marks[3]=="/" and x73.frames[10].score==20,"10th X/7/3")

local tenthSpare,idSpare=prefixThroughNine(7)
idSpare=idSpare+1; deliver(tenthSpare,idSpare,3)
idSpare=idSpare+1; deliver(tenthSpare,idSpare,10)
local spareX=rules.score(tenthSpare.players[1])
check(spareX.frames[10].marks[2]=="/" and spareX.frames[10].marks[3]=="X" and spareX.frames[10].score==20,"10th spare plus strike bonus")

-- Pending strikes/spares keep nil frame scores and cumulative totals.
local pending=assert(rules.new(1)); deliver(pending,1,10)
local pendingScore=rules.score(pending.players[1])
check(pendingScore.pending and pendingScore.frames[1].score==nil and pendingScore.frames[1].cumulative==nil,"unresolved strike remains nil")
check(pendingScore.frames[10] and pendingScore.total==0,"score always exposes ten frames and resolved subtotal")

-- Rejections are atomic; the same accepted delivery cannot be applied twice.
local atomic=assert(rules.new(1)); local accepted=makeResult(atomic,1,4)
check(rules.apply(atomic,1,accepted),"valid atomic fixture")
local rackRef,rollCount,frame,ball=atomic.rack,#atomic.players[1].rolls[1],atomic.frame,atomic.ballNumber
local ok=rules.apply(atomic,1,accepted)
check(not ok and atomic.rack==rackRef and #atomic.players[1].rolls[1]==rollCount and atomic.frame==frame and atomic.ballNumber==ball,"duplicate delivery must not mutate match")
local errored=makeResult(atomic,2,1); errored.status="error"
check(not rules.apply(atomic,2,errored) and atomic.lastDeliveryId==1,"error result rejected atomically")
local nonfinite=makeResult(atomic,2,1); nonfinite.standing[1].x=math.huge
check(not rules.apply(atomic,2,nonfinite) and atomic.lastDeliveryId==1,"nonfinite pin pose rejected atomically")

-- Tenth-frame spare bonus requires a complete fresh rack, including on player handoff.
local bonusMatch,bonusId=prefixThroughNine(7)
bonusId=bonusId+1; deliver(bonusMatch,bonusId,3)
check(#bonusMatch.rack==10 and bonusMatch.ballNumber==3,"bonus ball after tenth spare gets a full rack")
local badRack=makeResult(bonusMatch,bonusId+1,1); bonusMatch.rack={bonusMatch.rack[1]}
local oldRolls=#bonusMatch.players[1].rolls[10]
check(not rules.apply(bonusMatch,bonusId+1,badRack) and #bonusMatch.players[1].rolls[10]==oldRolls,"invalid bonus rack rejected atomically")

local function multiPlayerProgress(count)
  local m=assert(rules.new(count)); local id=0
  for frame=1,10 do
    for player=1,count do
      check(m.frame==frame and m.currentPlayer==player and m.ballNumber==1,"turn-by-frame order before first ball")
      id=id+1; deliver(m,id,0)
      check(m.currentPlayer==player and m.ballNumber==2,"first ball stays with current player")
      id=id+1; deliver(m,id,0)
      if player<count then check(m.currentPlayer==player+1 and m.frame==frame and #m.rack==10,"player handoff uses fresh rack")
      elseif frame<10 then check(m.currentPlayer==1 and m.frame==frame+1 and #m.rack==10,"frame handoff uses fresh rack") end
    end
  end
  check(m.complete and m.currentPlayer>=1 and m.currentPlayer<=count and m.frame==10,"completed match retains valid final player")
  check(not rules.score(m.players[1]).pending,"finished player scores resolve")
  return m
end
multiPlayerProgress(1)
multiPlayerProgress(2)
multiPlayerProgress(3)
multiPlayerProgress(4)

local function tenthFrameHandoffs(count)
  local m=assert(rules.new(count)); local id=0
  for frame=1,9 do
    for _=1,count do id=id+1; deliver(m,id,0); id=id+1; deliver(m,id,0) end
  end
  for player=1,count do
    check(m.frame==10 and m.currentPlayer==player,"tenth frame player order")
    id=id+1; deliver(m,id,7)
    id=id+1; deliver(m,id,3)
    check(m.ballNumber==3 and #m.rack==10,"tenth spare bonus rack reset")
    id=id+1; deliver(m,id,10)
    if player<count then check(m.currentPlayer==player+1 and #m.rack==10,"tenth-frame player handoff resets rack") end
  end
  check(m.complete and m.currentPlayer>=1 and m.currentPlayer<=count,"tenth-frame match completion preserves valid player")
  for _,p in ipairs(m.players) do check(not rules.score(p).pending,"tenth-frame handoff resolves all player scores") end
end
tenthFrameHandoffs(2)
tenthFrameHandoffs(4)

local tie=assert(rules.new(2)); local tieId=0
for _=1,10 do
  for _=1,2 do tieId=tieId+1; deliver(tie,tieId,0); tieId=tieId+1; deliver(tie,tieId,0) end
end
local ranking=rules.rankings(tie)
check(#ranking==2 and ranking[1].place==1 and ranking[2].place==1 and ranking[1].total==ranking[2].total,"final tie shares rank")

print("PASS rules scoring, atomicity, rack resets, and 1–4 player progression")
