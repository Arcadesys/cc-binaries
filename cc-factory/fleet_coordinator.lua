-- Run on a normal CC computer or turtle: fleet_coordinator <approved-config.txt>
local coordinator=require('lib_fleet_coordinator')
local PROTOCOL='cc-safe-mining-fleet-v1'
local function loadConfig(path)
    if not fs or not fs.exists(path) then return nil,'Approved fleet configuration file not found' end
    local file=fs.open(path,'r');if not file then return nil,'Configuration cannot be opened' end
    local data=file.readAll();file.close()
    local config=textutils.unserialize(data)
    if type(config)~='table' then return nil,'Config must be a serialized data table, not executable Lua' end
    return config
end
local function render(server,message,stopped)
    local help=stopped=='help'
    local ended=stopped and not help
    local w,h=term.getSize()
    if colors and term.setBackgroundColor then term.setBackgroundColor(colors.black);term.setTextColor(colors.white) end
    term.clear()
    local state=server:snapshot();local totals={AVAILABLE=0,ASSIGNED=0,QUARANTINED=0,RETIRED=0}
    for _,job in pairs(state.jobs) do totals[job.status]=totals[job.status]+1 end
    local lines={'FLEET: '..server.config.fleet,'AVAILABLE: '..totals.AVAILABLE,
        'WORKING: '..totals.ASSIGNED,'NEEDS HELP: '..totals.QUARANTINED,'COMPLETE: '..totals.RETIRED,
        'Reservations survive coordinator stops.'}
    if message then lines[#lines+1]='STATUS: '..message end
    local wrapped={}
    for _,text in ipairs(lines) do
        text=text:gsub('[\r\n]+',' ')
        while #text>w do
            local cut=text:sub(1,w):match('^.*() ')
            if cut and cut>1 then wrapped[#wrapped+1]=text:sub(1,cut-1);text=text:sub(cut+1)
            else wrapped[#wrapped+1]=text:sub(1,w);text=text:sub(w+1) end
        end
        wrapped[#wrapped+1]=text
    end
    local capacity=math.max(1,h-4);local pages=math.max(1,math.ceil(#wrapped/capacity))
    server.statusPage=math.max(1,math.min(server.statusPage or 1,pages));server.statusPages=pages
    term.setCursorPos(1,1);term.write((help and 'NEEDS HELP' or ended and 'COORDINATOR STOPPED' or 'FLEET COORDINATOR'):sub(1,w))
    for row=1,capacity do
        local text=wrapped[(server.statusPage-1)*capacity+row]
        if text then term.setCursorPos(1,row+1);term.write(text) end
    end
    term.setCursorPos(1,math.max(1,h-2));term.write(('PAGE '..server.statusPage..'/'..pages..(ended and '' or ' LEFT/RIGHT: DETAILS')):sub(1,w))
    term.setCursorPos(1,math.max(1,h-1));term.write((ended and 'Returned to shell.' or help and 'Q: EXIT' or 'Q: STOP COORDINATOR'):sub(1,w))
    term.setCursorPos(1,h);term.write(('Workers stop by their lease expiry.'):sub(1,w))
    return pages
end

local function helpAndExit(server,message)
    render(server,message,'help')
    while true do
        local event,key=os.pullEvent()
        if event=='key' and keys and key==keys.q then return end
        if event=='key' and keys and (key==keys.left or key==keys.pageUp or key==keys.right or key==keys.pageDown) then
            server.statusPage=(server.statusPage or 1)+((key==keys.left or key==keys.pageUp) and -1 or 1)
            render(server,message,'help')
        end
    end
end
local function run(argv)
    local config,err=loadConfig(argv[1] or '')
    if not config then print('NEEDS HELP: '..tostring(err));return false,err end
    local server;server,err=coordinator.new(config)
    if not server then print('NEEDS HELP: '..tostring(err));return false,err end
    local modem=false
    for _,side in ipairs(peripheral.getNames()) do
        if peripheral.hasType(side,'modem') then rednet.open(side);modem=true end
    end
    if not modem then print('NEEDS HELP: Attach a modem. Reservations retained.');return false,'No modem' end
    render(server,'READY - only approved workers/jobs')
    local lastMessage='READY - only approved workers/jobs'
    local timer=os.startTimer(1)
    while true do
        local event,a,b,protocol=os.pullEvent()
        if event=='key' and keys and a==keys.q then render(server,'STOPPED - workers stop by lease expiry',true);return true end
        if event=='key' and keys and (a==keys.left or a==keys.pageUp or a==keys.right or a==keys.pageDown) then
            server.statusPage=(server.statusPage or 1)+((a==keys.left or a==keys.pageUp) and -1 or 1)
            render(server,lastMessage)
        elseif event=='rednet_message' and protocol==PROTOCOL then
            local response=server:handle(a,b)
            rednet.send(a,response,PROTOCOL)
            lastMessage=response.type..': '..tostring(response.job or '')..' '..tostring(response.reason or '')
            render(server,lastMessage)
        elseif event=='timer' and a==timer then
            local ok,why=server:tick()
            if not ok then helpAndExit(server,tostring(why));return false,why end
            for name,job in pairs(server:snapshot().jobs) do if job.status=='QUARANTINED' then lastMessage=name..': '..tostring(job.reason);break end end
            render(server,lastMessage)
            timer=os.startTimer(1)
        end
    end
end
local M={run=run,render=render,protocol=PROTOCOL}
if not _G.__FLEET_EMBED__ then run({...}) end
return M
