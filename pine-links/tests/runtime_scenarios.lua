local runtime=require('tests.runtime')
local reports={}
for _,mode in ipairs({'keyboard','monitor'}) do
  local steps={
    {action='start'}, {wait='AIM',strokes=0},
    {action='help'}, {wait='HELP'}, {action=mode=='monitor' and 'start' or 'help'},
    {action='view'}, {action='view'},
    {control={club='wedge',power=0.73}}, {action='swing'},
    {wait='SHOT_PLAYBACK'}, {action='skip'}, {wait='AIM',strokes=1},
    {control={club='putter',power=0.61}}, {action='swing'},
    {wait='SHOT_PLAYBACK'}, {action='skip'}, {wait='SCORECARD',strokes=2,penalties=0},
    {check=function(app) assert(app.state.complete,'hole must be complete') end},
    {action='restart'}, {wait='AIM',strokes=0,penalties=0},
    {control={club='wedge',power=0.73,aim=math.rad(12)}}, {action='swing'},
    {wait='SHOT_PLAYBACK'}, {action='skip'}, {wait='AIM',strokes=2,penalties=1},
    {check=function(app)
      assert(app.state.ball.x==app.course.hole.tee.x and app.state.ball.z==app.course.hole.tee.z,'hazard must restore lie')
    end},
    {action='pause'}, {wait='PAUSED'}, {action='restart'}, {wait='AIM',strokes=0,penalties=0},
    {control={club='wedge',power=0.70,aim=math.rad(-3)}}, {action='swing'},
    {wait='SHOT_PLAYBACK'}, {action='skip'}, {wait='AIM',strokes=1},
    {check=function(app)
      local p=app.state.ball
      assert(app.course.sample(p.x,p.z).material=='bunker','shot must land in visible bunker')
    end},
    {control={club='wedge',power=0.21}}, {action='swing'},
    {wait='SHOT_PLAYBACK'}, {action='skip'}, {wait='AIM',strokes=2,penalties=0},
    {check=function(app)
      local p,cup=app.state.ball,app.course.hole.cup
      assert(app.course.sample(p.x,p.z).material~='bunker','recover out of bunker')
      assert((p.x-cup.x)^2+(p.z-cup.z)^2<36,'recovery should approach cup')
    end},
  }
  if mode=='monitor' then
    steps[#steps+1]={resize=0.5}; steps[#steps+1]={wait='PAUSED',strokes=2}
    steps[#steps+1]={action='start'}; steps[#steps+1]={wait='AIM'}
    steps[#steps+1]={detach=true}; steps[#steps+1]={wait='PAUSED',strokes=2}
    steps[#steps+1]={action='pause'}; steps[#steps+1]={wait='AIM'}
  end
  steps[#steps+1]={action='pause'}; steps[#steps+1]={wait='PAUSED'}
  local report=runtime.run(mode,steps)
  assert(report.events[1].outcome=='rest' and report.events[2].outcome=='holed')
  assert(report.events[3].outcome=='water','water acceptance shot must contact water')
  reports[#reports+1]=report
  print('PASS runtime '..mode..': Birdie, help/view, restart, water +1, restored lie, sand recovery, quit, terminal/palette restoration'..(mode=='monitor' and ', actual resize/detach pause' or ''))
end
if fs then
  local h=assert(fs.open('/results/runtime.json','w'))
  h.write(textutils.serializeJSON(reports)); h.close()
end
require('tests.diagnostic')
require('tests.display')
return true
