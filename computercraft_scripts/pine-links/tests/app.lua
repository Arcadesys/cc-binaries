local App=require('lib.app')
local golf=require('lib.golf')
local function finished(app,dt,skip)
  local n=0
  while app.phase=='SIMULATE' or app.phase=='SHOT_PLAYBACK' do
    app:tick(dt); n=n+1
    if skip then app:action('skip') end
    assert(n<10000,'controller failed to finish shot')
  end
end
local a,b=App.new(),App.new()
a:action('start'); b:action('swing')
assert(a.phase=='AIM' and b.phase=='AIM')
assert(a:shot().club=='5i' and a.aim==0 and a.power==94,'furball default tee shot')
-- The forecast is the kernel's own calm-weather result for the current settings.
local forecast=a.forecast.finish
a:action('swing'); b:action('swing')
a:action('swing') -- Cannot execute a second shot during simulation.
assert(a.shotId==1)
finished(a,0.1,false); finished(b,1/3,true)
local sa,sb=a:state(),b:state()
assert(sa.strokes==1 and sb.strokes==1)
assert(sa.ball.x==sb.ball.x and sa.ball.z==sb.ball.z,'skip changed the shot')
assert(sa.ball.x==forecast.ball.x and sa.ball.z==forecast.ball.z,'forecast disagreed with the shot')
-- On the green: furball switches to the putter, aims at the cup and scales power to distance.
assert(sa.lie=='green' and a:shot().club=='putter')
assert(math.abs(a.aim-golf.aimToCup(sa))<1e-9)
assert(a.power==math.floor(golf.distanceToCup(sa)/32*200+.5)/2)
a:action('help'); a:action('swing'); assert(a.phase=='HELP' and a:state().strokes==1)
a:action('start'); assert(a.phase=='AIM')
a:action('swing'); a:pause('test resize')
local ticks=a.sim.state.ticks; a:tick(10); assert(a.sim.state.ticks==ticks,'paused shot advanced')
a:action('start'); assert(a.phase=='SIMULATE')
finished(a,0.1,true)
assert(a.phase=='SCORECARD' and a:state().strokes==2 and a:view().scoreLabel=='Birdie!')
a:action('restart'); assert(a.phase=='AIM' and a:state().strokes==0 and a:state().ball.z==0)
-- Aim wraps like furball's -180..180 slider; power is bounded 0.5..100.
a:action('fine'); local power=a.power; a:action('power_down'); assert(a.power==power-.5)
for _=1,400 do a:action('power_up') end; assert(a.power==100)
for _=1,400 do a:action('power_down') end; assert(a.power==.5)
a.aim=179.5; a:action('aim_right'); assert(a.aim==-180)
a:action('club_next'); assert(a:shot().club=='7i')
a:action('club_prev'); a:action('club_prev'); assert(a:shot().club=='putter')
a.aim=40; a:action('aim_cup'); assert(math.abs(a.aim)<1e-9)
-- Out of bounds: one stroke plus one penalty, replayed from the previous lie.
local ob=App.new(); ob:action('start'); ob.aim=-60; ob.power=100; ob:updateForecast()
assert(ob.forecast.penalty,'forecast should warn of out of bounds')
ob:action('swing'); finished(ob,0.1,true)
assert(ob:state().strokes==2 and ob:state().penalties==1 and ob:state().ball.z==0)
a:action('quit'); assert(not a.running)
return true
