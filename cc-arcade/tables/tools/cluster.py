#!/usr/bin/env python3
"""Boot a table and its seats as separate CraftOS-PC computers on one wired network.

  python3 cc-arcade/tables/tools/cluster.py            scripted two-hand test, headless
  python3 cc-arcade/tables/tools/cluster.py --gui 3    play: table + 3 seat windows

Every computer gets the same startup, which runs tables/tests/cluster.lua; computer 0
(the table) spawns the seats. Uses a fresh emulator data directory each run.
"""
import argparse, json, pathlib, subprocess, sys, tempfile, time
root=pathlib.Path(__file__).resolve().parents[2]
craftos='/Applications/CraftOS-PC.app/Contents/MacOS/craftos'
ap=argparse.ArgumentParser()
ap.add_argument('--gui',type=int,metavar='SEATS',help='open windows and play with this many seats (1-4)')
ap.add_argument('--timeout',type=int,default=120)
args=ap.parse_args()
seats=args.gui or 3
assert 1<=seats<=4,'A table has 1 to 4 seats'
out=pathlib.Path(tempfile.mkdtemp(prefix='pine-tables-'))
emu=out/'emulator'
startup='''_G.TABLES_CLUSTER=%s
shell.setDir('/arcade')
local env=setmetatable({}, {__index=_ENV})
env.require,env.package=require('cc.require').make(env,'/arcade')
local ok,err=xpcall(function() env.require('tables.tests.cluster') end,debug.traceback)
if not ok then
 local f=fs.open('/results/crash-'..os.getComputerID()..'.txt','w'); f.write(tostring(err)); f.close()
 printError(err)
end
''' % ('{mode=%s,seats=%d}' % (json.dumps('gui' if args.gui else 'test'),seats))
for i in range(seats+1):
 (emu/'computer'/str(i)).mkdir(parents=True)
 (emu/'computer'/str(i)/'startup.lua').write_text(startup)
(emu/'config').mkdir(parents=True)
mode=[] if args.gui else ['--headless']
cmd=[craftos,*mode,'--directory',str(emu),'--mount-ro',f'/arcade={root}','--mount-rw',f'/results={out}']
print(out)
if args.gui:
 print('Table is computer 0 (its monitor shows the public view); seats are computers 1-%d.'%seats)
 print('Click buttons or press 1-9 in a seat window. Close the windows to stop.')
 sys.exit(subprocess.run(cmd).returncode)
proc=subprocess.Popen(cmd,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
deadline=time.time()+args.timeout
while proc.poll() is None and time.time()<deadline and not (out/'result.txt').exists(): time.sleep(.5)
time.sleep(1)
if proc.poll() is None: proc.kill()
for f in sorted(out.glob('*.txt')):
 print('==',f.name); print(f.read_text())
result=(out/'result.txt').read_text() if (out/'result.txt').exists() else 'FAIL no result (timeout or emulator crash)'
sys.exit(0 if result.endswith('PASS') else 1)
