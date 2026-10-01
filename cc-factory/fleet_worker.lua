-- Native adapter. Configuration is data-only; local preflight precedes mining.
local client=require('lib_fleet_worker')
local renderer=require('lib_fleet_worker_status')
local function clock() return os.clock() end
local function loadConfig(path)
    local file=fs.open(path,'r');if not file then return nil,'Cannot read local fleet worker configuration' end
    local text=file.readAll();file.close()
    local config=textutils.unserialize(text)
    if type(config)~='table' then return nil,'Configuration must be a serialized table, not Lua code' end
    return config
end
local function run(args)
    local config,err=loadConfig(args[1] or 'fleet-worker.config')
    if not config then print('NEEDS HELP: '..err);return nil,err end
    if config.workerId~=os.getComputerID() then print('NEEDS HELP: local turtle identity mismatch');return nil,'Local turtle identity mismatch' end
    if type(config.modemSide)~='string' or not peripheral.hasType(config.modemSide,'modem') then print('NEEDS HELP: configured modem unavailable');return nil,'Configured modem unavailable' end
    rednet.open(config.modemSide)
    local protocol='cc-safe-mining-fleet-v1'
    config.requestIdSeed=config.requestIdSeed or os.epoch('utc')
    local transport={exchange=function(target,message,timeout)
        rednet.send(target,message,protocol)
        local deadline=clock()+timeout
        while clock()<deadline do
            local sender,reply=rednet.receive(protocol,math.max(0,deadline-clock()))
            if sender==target and type(reply)=='table' and reply.fleet==message.fleet and reply.requestId==message.requestId then return sender,reply end
        end
        return nil,nil
    end}
    local worker;worker,err=client.new(config,{clock=clock,transport=transport})
    if not worker then rednet.close(config.modemSide);print('NEEDS HELP: '..tostring(err));return nil,err end
    local timer,page=nil,1
    while true do
        page=renderer.render(worker,page)
        local s=worker:state();local ended=s.status=='STOPPED' or s.status=='NEEDS_HELP'
        -- Keep the pending timer across page/key events; navigation cannot starve work.
        if not ended and worker.confirmed and not timer then timer=os.startTimer(config.pollSeconds or 0.25) end
        local event,value=os.pullEvent()
        if event=='key' and value==keys.q then
            if ended then break
            elseif worker.ctx then worker:stop()
            else worker.status='STOPPED';worker.reason='Local stop before assignment' end
        elseif event=='key' and (value==keys.up or value==keys.pageUp) then page=math.max(1,page-1)
        elseif event=='key' and (value==keys.down or value==keys.pageDown) then page=page+1
        elseif event=='key' and value==keys.enter and not worker.confirmed and not ended then worker:confirmHome(true)
        elseif event=='timer' and value==timer then
            timer=nil
            if not ended then
                local ran,reason=pcall(function() return worker:tick() end)
                if not ran then worker.status='NEEDS_HELP';worker.reason=tostring(reason) end
            end
        end
    end
    rednet.close(config.modemSide)
    return worker
end
local M={run=run,render=renderer.render}
if not _G.__FLEET_WORKER_EMBED__ then run({...}) end
return M
