local App=require('lib.app')
local flat={hole={tee={x=0,y=0,z=0},cup={x=107,y=0,z=0},par=3,
  bounds={minX=-500,maxX=500,minZ=-500,maxZ=500},waterLevel=-100},
  sample=function() return {height=0,nx=0,ny=1,nz=0,material='fairway'} end}
local function finished(app,dt,skip)
  local n=0
  while app.phase=='SIMULATE' or app.phase=='SHOT_PLAYBACK' do
    app:tick(dt); n=n+1
    if skip then app:action('skip') end
    assert(n<10000,'controller failed to finish shot')
  end
end
local a,b=App.new(flat),App.new(flat)
a:action('start'); b:action('swing')
assert(a.phase=='AIM' and b.phase=='AIM')
a:action('swing'); b:action('swing')
a:action('swing') -- Cannot execute a second shot during simulation.
assert(a.shotId==1)
finished(a,0.1,false); finished(b,1/3,true)
assert(a.state.strokes==1 and b.state.strokes==1)
assert(a.state.ball.x==b.state.ball.x and a.state.ball.z==b.state.ball.z)
assert(a.phase=='AIM' and b.phase=='AIM')
a:action('help'); local before=a.state.strokes
a:action('swing'); assert(a.phase=='HELP' and a.state.strokes==before)
a:action('start'); assert(a.phase=='AIM')
a:action('swing'); a:pause('test resize')
local t=a.sim.time; a:tick(10); assert(a.sim.time==t)
a:action('start'); assert(a.phase=='SIMULATE')
finished(a,0.1,true); assert(a.state.strokes==2)
a:action('restart'); assert(a.phase=='AIM' and a.state.strokes==0 and a.state.ball.x==0)
a:action('fine'); local power=a.power; a:action('power_down')
assert(math.abs(a.power-(power-0.01))<1e-8)
for _=1,200 do a:action('power_up') end
assert(a.power==1)
for _=1,200 do a:action('power_down') end
assert(a.power==0.01)
a:action('quit'); assert(not a.running)
return true
