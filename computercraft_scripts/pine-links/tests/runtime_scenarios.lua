local runtime=require('tests.runtime')
local golf=require('lib.golf')
local reports={}
for _,mode in ipairs({'keyboard','monitor'}) do
  local steps={
    {action='start'}, {wait='AIM',strokes=0},
    {action='help'}, {wait='HELP'}, {action=mode=='monitor' and 'start' or 'help'},
    {action='view'}, {action='view'}, {action='view'},
    -- Furball's default tee shot finds the green; the suggested putt drops for a birdie.
    {action='swing'}, {wait='SHOT_PLAYBACK'}, {action='skip'}, {wait='AIM',strokes=1},
    {check=function(app) assert(app:state().lie=='green' and app:shot().club=='putter','putter suggested on the green') end},
    {action='swing'}, {wait='SHOT_PLAYBACK'}, {action='skip'}, {wait='SCORECARD',strokes=2,penalties=0},
    {check=function(app) assert(app:state().phase=='finished' and app:view().scoreLabel=='Birdie!') end},
    {action='restart'}, {wait='AIM',strokes=0,penalties=0},
    -- Out of bounds left: stroke plus penalty, replayed from the tee.
    {control={aim=-60,power=100}}, {action='swing'},
    {wait='SHOT_PLAYBACK'}, {action='skip'}, {wait='AIM',strokes=2,penalties=1},
    {check=function(app) local b=app:state().ball; assert(b.x==0 and b.z==0,'out of bounds must restore lie') end},
    {action='pause'}, {wait='PAUSED'}, {action='restart'}, {wait='AIM',strokes=0,penalties=0},
    -- Pulled 5 iron into the left greenside bunker; the wedge is suggested and recovers to the green.
    {control={aim=-6.5,power=90}}, {action='swing'},
    {wait='SHOT_PLAYBACK'}, {action='skip'}, {wait='AIM',strokes=1},
    {check=function(app) assert(app:state().lie=='sand' and app:shot().club=='wedge','wedge suggested from sand') end},
    {control={power=40}}, {action='swing'},
    {wait='SHOT_PLAYBACK'}, {action='skip'}, {wait='AIM',strokes=2,penalties=0},
    {check=function(app)
      assert(app:state().lie=='green' and golf.distanceToCup(app:state())<6,'sand recovery should reach the green')
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
  assert(report.events[3].outcome=='ob','out-of-bounds acceptance shot')
  reports[#reports+1]=report
  print('PASS runtime '..mode..': Birdie, help/view, restart, OB +1, restored lie, sand recovery, quit, terminal/palette restoration'..(mode=='monitor' and ', actual resize/detach pause' or ''))
end
if fs then
  local h=assert(fs.open('/results/runtime.json','w'))
  h.write(textutils.serializeJSON(reports)); h.close()
end
require('tests.diagnostic')
require('tests.display')
return true
