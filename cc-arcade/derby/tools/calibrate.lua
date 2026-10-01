local sim=require('derby.sim')
local wins={0,0,0}; local totalTime=0; local count=100000
for seed=1,count do
 local race=sim.run(seed); wins[race.order[1]]=wins[race.order[1]]+1
 totalTime=totalTime+race.horses[race.order[1]].finish
 if seed%500==0 then os.queueEvent('calibration_yield'); os.pullEvent('calibration_yield') end
end
local odds={version='sim-1-calibration-100000-v1',simulation=sim.version,samples=count,wins=wins,meanSeconds=totalTime/count,payouts={}}
for i=1,3 do
 odds.payouts[i]={}
 for _,stake in ipairs({5,10,20}) do odds.payouts[i][tostring(stake)]=math.floor(stake*.9/(wins[i]/count)) end
end
local f=assert(fs.open('/results/odds.json','w')); f.write(textutils.serializeJSON(odds)); f.close()
print(textutils.serializeJSON(odds))
