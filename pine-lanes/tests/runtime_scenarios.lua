local runtime=require('tests.runtime')
local shots={
 {position=0,aim=0,power=.75,hook=0},
 {position=-.10,aim=0,power=.75,hook=.30},
 {position=.10,aim=0,power=.75,hook=-.30},
 {position=0,aim=math.rad(8),power=1,hook=0},
}
local reports={runtime.run('keyboard',1,shots),runtime.run('monitor',2,shots),
 runtime.run('keyboard-perfect',1,{{position=-.08,aim=0,power=1,hook=0}})}
assert(reports[3].scores[1]==300 and #reports[3].events==12,'perfect-game dispatcher regression')
runtime.playbackRecovery()
runtime.errorRestoration()
local h=assert(fs.open('/results/runtime.json','w'));h.write(textutils.serializeJSON(reports));h.close()
assert(require('tests.display')==true)
return true
