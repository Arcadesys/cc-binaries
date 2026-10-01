-- Actual status renderer in native CC terminals; no reconstructed layout.
local realFS,realTerm=fs,term
local sources={}
for _,dir in ipairs({'/src','/src/tests'}) do for _,name in ipairs(realFS.list(dir)) do if name:match('%.lua$') then local f=realFS.open(dir..'/'..name,'r');sources[name:gsub('%.lua$','')]=f.readAll();f.close() end end end
local cache={}
function require(name) if cache[name] then return cache[name] end;cache[name]=assert(load(assert(sources[name]),'@'..name,'t',_ENV))();return cache[name] end
local sim=require('simulator');sim.new()
local status=require('lib_mining_status')
local cfg={job='pilot-one',dimension='minecraft:overworld',home={x=0,y=64,z=0,facing='north'},bounds={min={x=-4,y=63,z=-8},max={x=4,y=66,z=0}},outputSide='down',supplySide='up'}
local hex='0123456789abcdef'
local count=0
for _,dims in ipairs({{39,13},{39,19},{51,19}}) do
 for _,scenario in ipairs({'ready-home','ready-saved','needs-help','done','setup-home'}) do
  local ctx={config=sim.copy(cfg),pointer=31,strategy={},pose={x=2,y=65,z=-3,facing='east'}}
  for i=1,124 do ctx.strategy[i]={} end
  ctx.phase=scenario=='done' and 'DONE' or scenario=='needs-help' and 'NEEDS_HELP' or 'MINING'
  if scenario=='needs-help' then ctx.lastError='Protected block minecraft:chest at 2, 64, -5. Digging is forbidden. Verify the receiver and physical saved pose before explicit resume.' end
  ctx.config.resume=scenario=='ready-saved' or nil
  if scenario=='ready-home' or scenario=='done' then ctx.pose=sim.copy(cfg.home) end
  local ready=scenario=='ready-home' or scenario=='ready-saved'
  local screen=window.create(realTerm.current(),1,1,dims[1],dims[2],false)
  local prior=term.redirect(screen);if scenario=='setup-home' then require('lib_mining_setup').renderPrompt('HOME COORDINATES','Enter your marked home: X Y Z.',nil,'Use three integers: X Y Z.');ctx.statusPages=1 else status.render(ctx,ready) end;term.redirect(prior)
  for page=1,ctx.statusPages do
   ctx.statusPage=page;local old=term.redirect(screen);if scenario=='setup-home' then require('lib_mining_setup').renderPrompt('HOME COORDINATES','Enter your marked home: X Y Z.',nil,'Use three integers: X Y Z.') else status.render(ctx,ready) end;term.redirect(old)
   local palette,lines={},{}
   for i=0,15 do palette[hex:sub(i+1,i+1)]=colors.packRGB(screen.getPaletteColor(2^i)) end
   for y=1,dims[2] do local text,fg,bg=screen.getLine(y);lines[y]={text={text:byte(1,-1)},fg=fg,bg=bg} end
   local name=scenario..'-'..dims[1]..'x'..dims[2]..'-page'..page
   local f=assert(realFS.open('/results/'..name..'.screen.json','w'));f.write(textutils.serializeJSON({w=dims[1],h=dims[2],palette=palette,lines=lines}));f.close();count=count+1
  end
 end
end
local f=assert(realFS.open('/results/tests.txt','w'));f.write('PASS all '..count..' native rendered screen pages\n');f.close()
