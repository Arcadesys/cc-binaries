-- Native terminal dumps of the actual fleet renderers. No Minecraft or turtle calls.
local realFS,realTerm=fs,term
local sources,cache={},{}
for _,name in ipairs(realFS.list('/src')) do
    if name:match('%.lua$') then
        local f=assert(realFS.open('/src/'..name,'r'));sources[name:gsub('%.lua$','')]=f.readAll();f.close()
    end
end
function require(name)
    if cache[name] then return cache[name] end
    cache[name]=assert(load(assert(sources[name],'Missing source '..name),'@'..name,'t',_ENV))()
    return cache[name]
end
_G.__FLEET_EMBED__=true
local workerStatus=require('lib_fleet_worker_status')
local coordinator=require('fleet_coordinator')
local hex='0123456789abcdef'
local count=0
local reason='Lease renewal was refused after a coordinator restart. The reserved mining area remains quarantined and must not be reassigned. Confirm the physical turtle position, saved heading, dimension, inventory transfer and both journals before manual reconciliation. No return movement or new excavation is authorized. FINAL CHECK: RECONCILE BEFORE ANY NEW MUTATION.'
local function squash(text) return text:gsub('%s+','') end
local function dump(screen,name,width,height)
    local palette,lines={},{}
    for i=0,15 do palette[hex:sub(i+1,i+1)]=colors.packRGB(screen.getPaletteColor(2^i)) end
    local text={}
    for y=1,height do
        local line,fg,bg=screen.getLine(y)
        assert(#line==width and #fg==width and #bg==width,'Incorrect native line dimensions')
        assert(not fg:find('[^0]') and not bg:find('[^f]'),'Screen must use white text on black')
        lines[y]={text={line:byte(1,-1)},fg=fg,bg=bg}
        text[#text+1]=line
    end
    local file=assert(realFS.open('/results/'..name..'.screen.json','w'))
    file.write(textutils.serializeJSON({w=width,h=height,palette=palette,lines=lines}));file.close()
    count=count+1
    return table.concat(text,'\n')
end
for _,dims in ipairs({{39,13},{39,19},{51,19}}) do
    local width,height=dims[1],dims[2]
    for _,scenario in ipairs({'worker-preflight','worker-needs-help','coordinator-ready','coordinator-help'}) do
        local screen=window.create(realTerm.current(),1,1,width,height,false)
        local worker={config={fleet='supervised-pilot',coordinatorId=42,dimension='minecraft:overworld',home={x=-12,y=64,z=103,facing='north'}}}
        local state={status=scenario=='worker-preflight' and 'AWAITING_PREFLIGHT' or 'NEEDS_HELP',home={x=-12,y=64,z=103,facing='south'}}
        if scenario=='worker-needs-help' then
            state.job='pilot-south';state.phase='NEEDS_HELP';state.pose={x=-10,y=65,z=107,facing='east'};state.reason=reason
        end
        function worker:state() return state end
        local server={config={fleet='supervised-pilot'},statusPage=1}
        function server:snapshot() return {jobs={north={status='AVAILABLE'},south={status='ASSIGNED'},east={status='QUARANTINED'},west={status='RETIRED'}}} end
        local isWorker=scenario:find('^worker')
        local function render(page)
            local prior=term.redirect(screen)
            local pages
            if isWorker then local _,total=workerStatus.render(worker,page);pages=total
            else server.statusPage=page;pages=coordinator.render(server,scenario=='coordinator-help' and reason or 'READY - only approved workers/jobs',scenario=='coordinator-help' and 'help' or nil) end
            term.redirect(prior)
            return pages
        end
        local pages=render(1)
        local texts,bodies={},{}
        for page=1,pages do
            assert(render(page)==pages,'Page count changed between native renders')
            local name='fleet-'..scenario..'-'..width..'x'..height..'-page'..page
            texts[#texts+1]=dump(screen,name,width,height)
            for row=isWorker and 1 or 2,isWorker and height-2 or height-3 do bodies[#bodies+1]=screen.getLine(row) end
        end
        local all=table.concat(texts,'\n')
        -- Ignore repeated page footers, but require every message word in order.
        local normalized=squash(table.concat(bodies,'\n'))
        if scenario=='worker-preflight' then
            assert(normalized:find(squash('CONFIGURED HOME: -12, 64, 103 / north'),1,true),'Configured home is missing')
            assert(normalized:find(squash('SAVED HOME POSE: -12, 64, 103 / south'),1,true),'Saved home heading is missing')
            assert(normalized:find(squash('DIMENSION: minecraft:overworld'),1,true),'Dimension is missing')
            assert(squash(all):find(squash('ENTER start / Q stop'),1,true),'Preflight keyboard controls missing')
        elseif scenario=='worker-needs-help' or scenario=='coordinator-help' then
            for word in reason:gmatch('%S+') do assert(all:find(word,1,true),'Reason word missing across pages: '..word) end
            assert(normalized:find(squash('RECONCILE BEFORE ANY NEW MUTATION.'),1,true),'Final reason sentence missing')
            assert(squash(all):find('NEEDSHELP',1,true) or squash(all):find('NEEDS_HELP',1,true),'Failure label missing')
        else assert(normalized:find(squash('READY - only approved workers/jobs'),1,true),'READY message missing') end
    end
end
local file=assert(realFS.open('/results/tests.txt','w'))
file.write('PASS all '..count..' native fleet rendered screen pages at 39x13, 39x19, 51x19\n');file.close()
