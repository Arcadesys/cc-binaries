-- Install each program with get.lua from this checkout into a fresh folder, then load
-- its modules from there: proves the manifest carries every file the program needs.
local manifest=textutils.unserializeJSON(fs.open('/arcade/manifest.json','r').readAll())
for _,name in ipairs({'pineslots','pinejack','pinebox','race'}) do
 local dir='/results/install-'..name
 local ok,err=pcall(shell.run,'/arcade/get.lua',name,'--local','/arcade','--dir',dir,'--startup')
 assert(ok,err)
 for _,f in ipairs(manifest.programs[name].files) do assert(fs.exists(fs.combine(dir,f.path)),name..' missing '..f.path) end
 for _,tool in ipairs({'house.lua','config.lua','get.lua'}) do assert(fs.exists(fs.combine(dir,tool)),name..' missing '..tool) end
 local env=setmetatable({shell=shell},{__index=_ENV}); env.require,env.package=require('cc.require').make(env,dir)
 local main={pineslots='pineslots.machine',pinejack='pinejack.game',pinebox='pinebox.game',race='derby.render'}
 env.require(main[name]); env.require('derby.app'); if name~='race' then env.require('credits') end
 local s=fs.open('/startup.lua','r').readAll()
 assert(s:find(dir,1,true) and s:find(manifest.programs[name].entry,1,true),'Startup runs the program')
 print('installed '..name..' ('..#manifest.programs[name].files..' files)')
end
local state=textutils.unserializeJSON(fs.open('/results/install-race/.get.json','r').readAll())
assert(state.programs[1]=='race' and state.startup,'Install remembered for get update')
-- Update re-downloads from the remembered source, using the installed copy of get.lua.
fs.delete('/results/install-race/derby/render.lua')
assert(pcall(shell.run,'/results/install-race/get.lua','update','--dir','/results/install-race'))
assert(fs.exists('/results/install-race/derby/render.lua'),'Update restores files')
print('PASS installer')
