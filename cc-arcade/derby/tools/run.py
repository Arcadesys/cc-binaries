#!/usr/bin/env python3
"""Run a Lua module in a separate CraftOS-PC instance, never Computer 0."""
import pathlib, tempfile, subprocess, sys, json
root=pathlib.Path(__file__).resolve().parents[2]
module=sys.argv[1] if len(sys.argv)>1 else 'derby.tests.run'
out=pathlib.Path(tempfile.mkdtemp(prefix='pine-derby-'))
(out/'emulator'/'config').mkdir(parents=True)
(out/'emulator'/'config'/'0.json').write_text(json.dumps({'isColor':True,'computerWidth':100,'computerHeight':40}))
code='''shell.setDir('/arcade'); local lines={}; print=function(...) local p={...}; for i=1,#p do p[i]=tostring(p[i]) end; lines[#lines+1]=table.concat(p,' ') end; local env=setmetatable({}, {__index=_ENV}); env.require,env.package=require('cc.require').make(env,'/arcade'); local ok,err=xpcall(function() env.require(%s) end,debug.traceback); lines[#lines+1]=ok and 'PASS' or ('FAIL '..tostring(err)); local f=fs.open('/results/result.txt','w'); f.write(table.concat(lines,'\\n')); f.close(); os.shutdown()''' % json.dumps(module)
r=subprocess.run(['/Applications/CraftOS-PC.app/Contents/MacOS/craftos','--headless','--directory',str(out/'emulator'),'--mount-ro',f'/arcade={root}','--mount-rw',f'/results={out}','--exec',code],capture_output=True,text=True,timeout=600)
print(out)
result=(out/'result.txt').read_text() if (out/'result.txt').exists() else r.stdout+r.stderr
print(result)
sys.exit(0 if result.endswith('PASS') else 1)
