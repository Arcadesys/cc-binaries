local App=require('lib.app')
local function finish(app,skip)
  local budget=1000
  while app.phase=='SIMULATE' and budget>0 do app:tick(.1);budget=budget-1 end
  assert(budget>0 and app.phase=='PLAYBACK','simulation failed: '..tostring(app.message))
  if skip then app:action('skip') else
    while app.phase=='PLAYBACK' and budget>0 do app:tick(.1);budget=budget-1 end
  end
  assert(app.phase=='RESULT','result missing: '..app.phase)
end
local function equal(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~='table' then return a==b end
 for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
local small=App.new();small.smallDisplay=true;small:action('primary');assert(small.phase=='SETUP');small:action('quit');assert(not small.running)
local a=App.new();assert(a.phase=='SETUP')
a:action('players_up');assert(a.playerCount==2)
a:action('players_up');a:action('players_up');a:action('players_up');assert(a.playerCount==4)
a:action('players_down');a:action('players_down');a:action('players_down');a:action('players_down');assert(a.playerCount==1)
a:action('primary');assert(a.phase=='AIM')
a:action('select_hook');for i=1,30 do a:action('adjust_up') end;assert(a:currentSettings().hook==1)
for i=1,50 do a:action('adjust_down') end;assert(a:currentSettings().hook==-1)
a:action('fine');a:action('adjust_up');assert(math.abs(a:currentSettings().hook+.98)<1e-9)
a:action('select_position');for i=1,100 do a:action('adjust_up') end;assert(a:currentSettings().position==.38)
a:action('select_aim');for i=1,100 do a:action('adjust_down') end;assert(a:currentSettings().aim==-math.rad(8))
a:action('select_power');for i=1,100 do a:action('adjust_down') end;assert(a:currentSettings().power==.25)
a:action('help');assert(a.phase=='HELP');a:tick(10);a:action('start');assert(a.phase=='AIM')
a:action('quit');assert(a.running,'quit must require menu')
a:action('pause');a:action('restart');assert(a.phase=='AIM' and a:currentSettings().power==.75)
a:action('help');a:action('restart');assert(a.phase=='AIM' and a.match.frame==1,'help restart button failed')
local b=App.new();b:action('start')
a:action('roll');local id=a.deliveryId;a:action('roll');assert(a.deliveryId==id,'double roll')
a:action('pause');local n=#a.sim.trajectory;a:tick(10);assert(#a.sim.trajectory==n);a:action('start')
finish(a,false);b:action('roll');finish(b,true)
assert(equal(a.match,b.match),'skip changed result')
a:action('select_next');assert(a.camera=='score','result player button must open scorecard')
local summary=a.rollSummary; local resultRack=a.match.rack
for _,overlay in ipairs({'pause','help'}) do
 a:action(overlay);a:tick(100);a:action('start')
 assert(a.phase=='RESULT' and a.rollSummary==summary and a.match.rack==resultRack,'result overlay changed delivery')
end
local early=App.new();early:action('start');early:action('roll');early:action('skip')
local budget=1000
while early.phase=='SIMULATE' and budget>0 do early:tick(.1);budget=budget-1 end
assert(early.phase=='RESULT' and equal(early.match,b.match),'skip during simulation changed result')
local paused=App.new();paused:action('start');paused:action('roll')
while paused.phase=='SIMULATE' do paused:tick(.1) end
paused:tick(.3);local elapsed=paused.playback.elapsed;local image=paused.displaySnapshot
paused:action('help');paused:tick(100);paused:action('pause');paused:action('start')
assert(paused.phase=='PLAYBACK' and paused.playback.elapsed==elapsed and paused.displaySnapshot==image,'playback overlay advanced time')
paused:action('skip');assert(equal(paused.match,b.match))
a:action('roll');assert(a.phase=='RESULT' and a.deliveryId==id,'result must require continue')
a:action('continue');assert(a.phase=='AIM')
-- Failed simulation does not advance the turn or mutate the standing rack.
local snapshot={};for k,v in pairs(a.match) do snapshot[k]=v end
local oldRack=a.match.rack;local oldId=a.match.lastDeliveryId
a.sim={result={status='error',error='injected failure'}};a.phase='PLAYBACK';a:resolve()
assert(a.phase=='AIM' and a.match.rack==oldRack and a.match.lastDeliveryId==oldId)
-- Settings follow players, not the shared screen.
local multi=App.new();multi:action('players_up');multi:action('start')
multi:action('select_power');multi:action('adjust_down');local power=multi:currentSettings().power
for i=1,2 do if multi.match.currentPlayer==1 then multi:action('roll');finish(multi,true);multi:action('continue') end end
assert(multi.match.currentPlayer==2 and multi:currentSettings().power==.75)
assert(multi.playerSettings[1].power==power)
multi:action('view');multi:action('view');assert(multi.camera=='score')
multi:action('select_prev');assert(multi.scorePlayer==1)
multi:action('pause');multi:action('quit');assert(not multi.running)
return true
