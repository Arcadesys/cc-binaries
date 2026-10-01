-- Exercise the actual migrated game paths. Only pacing, input and presentation
-- are stubbed; stakes, outcome branches and transaction calls run from source.
local assertions=0
local function check(v,msg) assert(v,msg); assertions=assertions+1 end
local function source(name,tail,credit,events)
 local f=fs.open('/arcade/'..name..'.lua','r'); local text=f.readAll(); f.close()
 text=text:gsub('main%(%)%s*$','')..'\n'..tail
 local noop=function() end
 local audio=setmetatable({}, {__index=function() return noop end})
 local env=setmetatable({sleep=noop,arcadeos={},require=function(name)
  if name=='credits' then return credit elseif name=='audio' then return audio elseif name=='input' then return {getButton=function(_,p) return p end} end
  return require(name)
 end}, {__index=_ENV})
 env.os=setmetatable({startTimer=function()return 77 end,pullEvent=function()
  local e=table.remove(events or {},1); assert(e,'Unexpected extra input'); return table.unpack(e)
 end},{__index=os})
 return assert(load(text,'@'..name,'t',env))()
end
local function wallet(reject)
 local calls={}; local credit={}
 function credit.get()return 100 end
 function credit.lock()end
 function credit.unlock()end
 function credit.findCards()return {{path='disk',name='Test'}} end
 function credit.beginRound(game,stake,maximum,path)
  calls[#calls+1]={op='reserve',game=game,stake=stake,maximum=maximum,path=path}
  if reject then return nil,'Bank unavailable' end
  return {account='bound-account',maximum=maximum}
 end
 function credit.settleRound(round,amount)
  check(round.account=='bound-account','Settles captured account')
  check(amount<=round.maximum,'Return inside reservation')
  calls[#calls+1]={op='settle',amount=amount}
 end
 function credit.refundRound()calls[#calls+1]={op='refund'} end
 function credit.increaseRound(round,stake,maximum)round.maximum=maximum;calls[#calls+1]={op='increase',stake=stake,maximum=maximum};return true end
 return credit,calls
end
-- Slots runs real reel movement and payout calculation, including a forced 3-line jackpot.
for _,reject in ipairs({false,true}) do
 local c,calls=wallet(reject)
 local run=source('slots',[[
 drawMachine=function()end
 for i=1,3 do for j=1,#REELS[i] do REELS[i][j]='7' end end
 return function() return spin({bet=3,mountPath='disk',name='Test'}) end
 ]],c)
 run()
 check(calls[1].maximum==1500,'Slots reserves all three paylines')
 if reject then check(#calls==1,'Failed reservation cannot spin or pay') else check(calls[2].amount==1500,'Actual slots jackpot settles once') end
end
-- Blackjack: surrender, normal stand, double down and refused initial stake.
for _,scenario in ipairs({'surrender','stand','double','reject'}) do
 local c,calls=wallet(scenario=='reject')
 local actions=scenario=='surrender' and {'RIGHT','CENTER','RIGHT'} or scenario=='double' and {'RIGHT','LEFT','RIGHT'} or {'CENTER','RIGHT'}
 local tail=[[
 drawCenter=function()end; drawTable=function()end; animateChips=function()end; animateSparkles=function()end
 local sequence=TEST_ACTIONS
 waitKey=function() return table.remove(sequence,1) or 'RIGHT' end
 createDeck=function() return {{rank='8'},{rank='10'},{rank='6'},{rank='7'},{rank='3'}} end
 return main
 ]]
 tail=tail:gsub('TEST_ACTIONS',textutils.serialize(actions))
 local main=source('blackjack',tail,c,{{'disk','drive'},{'button','CENTER'}})
 local ok=pcall(main)
 if scenario=='reject' then check(not ok and #calls==1,'Blackjack refuses unfunded play')
 else
  check(ok,'Blackjack '..scenario..' completes')
  check(calls[#calls].op=='settle','Blackjack settles result')
  if scenario=='surrender' then check(calls[#calls].amount==5,'Surrender returns half stake') end
  if scenario=='double' then check(calls[2].op=='increase' and calls[2].maximum==40,'Double down reserves increased return') end
 end
end
-- Track: real main-loop money path for win, loss and refused stake.
for _,scenario in ipairs({'win','loss','reject'}) do
 local c,calls=wallet(scenario=='reject')
 local main=source('track',([[
 local count=0
 runAttractMode=function() count=count+1; return {type=count==1 and 'disk' or 'exit'} end
 runRace=function() return TEST_WIN end
 showWinScreen=function()end; drawHeader=function()end
 return main
 ]]):gsub('TEST_WIN',scenario=='win' and 'true' or 'false'),c)
 local ok=pcall(main)
 if scenario=='reject' then check(not ok and #calls==1,'Track rejects failed reservation')
 else check(ok,'Track completes'); check(calls[2].amount==(scenario=='win' and 15 or 0),'Track win/loss settlement') end
end
-- RPS reserves each future reward before another floor and settles death as zero.
local c,calls=wallet(false)
local main=source('rps_rogue',[[
 generateEnemy=function() enemy={hp=0} end
 drawUpgradeMenu=function()end; drawUI=function()end
 waitKey=function() player.hp=0; return 'RIGHT' end
 return main
]],c)
main()
check(calls[1].stake==5 and calls[2].amount==5,'RPS first floor costs and pays five')
check(calls[3].stake==0 and calls[3].maximum==5,'Next floor reserves its reward')
check(calls[4].amount==0,'Death releases unused floor reserve')
print('PASS '..assertions..' actual game-path assertions')
