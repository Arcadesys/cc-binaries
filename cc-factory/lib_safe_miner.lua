-- Branch-mining lifecycle. Legacy builders and excavators do not use this engine.
local strategy = require('lib_strategy_branchmine')
local mining = require('lib_mining')
local policy = require('lib_mine_policy')
local journal = require('lib_mining_checkpoint')
local inventory = require('lib_inventory')
local M = {}
local headings = { north=0, east=1, south=2, west=3 }
local names = { [0]='north', [1]='east', [2]='south', [3]='west' }
local vectors = { north={0,-1}, east={1,0}, south={0,1}, west={-1,0} }
local function copy(t)
    if type(t) ~= 'table' then return t end
    local r = {}; for k,v in pairs(t) do r[k]=copy(v) end; return r
end
local function equal(a,b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function samePosition(a,b) return a.x==b.x and a.y==b.y and a.z==b.z end
local function fail(ctx, reason)
    ctx.lastError=tostring(reason); ctx.failedPhase=ctx.phase; ctx.phase='NEEDS_HELP'
    if ctx.pose and ctx.path and not ctx.intent then journal.save(ctx) end
    return 'ERROR'
end
local function save(ctx)
    local ok,err=journal.save(ctx)
    if not ok then return false, 'Checkpoint failed: '..tostring(err) end
    return true
end
local function transact(ctx, name, fn)
    ctx.intent={ action=name, pointer=ctx.pointer, phase=ctx.phase, pose=copy(ctx.pose) }
    local ok,err=save(ctx); if not ok then return false,err end
    inventory.invalidate(ctx)
    local ran,result,detail=pcall(fn)
    inventory.invalidate(ctx)
    if not ran then return false,'Interrupted/failed action: '..tostring(result)..'; manual reconciliation required' end
    ctx.intent=nil
    ok,err=save(ctx); if not ok then return false,err end
    return result,detail
end
local function stock(ctx,name)
    local n=0; for slot=1,16 do local item=turtle.getItemDetail(slot); if item and item.name==name then n=n+turtle.getItemCount(slot) end end
    return n
end
local function emptySlots()
    local n=0; for slot=1,16 do if turtle.getItemCount(slot)==0 then n=n+1 end end; return n
end
local function fuel(ctx,need)
    local level=turtle.getFuelLevel()
    if level=='unlimited' then return true end
    if type(level)~='number' then return false,'Invalid fuel reading' end
    if level>=need then return true end
    for slot=1,16 do
        local item=turtle.getItemDetail(slot)
        if item and item.name==ctx.config.fuelItem then
            turtle.select(slot)
            while turtle.getItemCount(slot)>0 and turtle.getFuelLevel()<need do
                if not turtle.refuel(1) then break end
            end
        end
    end
    return turtle.getFuelLevel()>=need, 'Insufficient fuel for recorded return route and reserve'
end
local function routeMoves(path,first,last)
    local count=0
    for i=first or 2,last or #path do if not samePosition(path[i-1],path[i]) then count=count+1 end end
    return count
end
local function sync(ctx)
    ctx.movement={ position={x=ctx.pose.x,y=ctx.pose.y,z=ctx.pose.z}, facing=ctx.pose.facing }
end
local function syncBack(ctx)
    local p=ctx.movement.position
    ctx.pose={x=p.x,y=p.y,z=p.z,facing=ctx.movement.facing}
end
local function turn(ctx,direction)
    local ok,err=turtle[direction=='left' and 'turnLeft' or 'turnRight']()
    if not ok then return false,'Turn failed: '..tostring(err) end
    ctx.pose.facing=names[(headings[ctx.pose.facing]+(direction=='left' and 3 or 1))%4]
    sync(ctx); return true
end
-- One checked primitive per return/resume step. No digging or attacking here.
local function approach(ctx,target,excavate)
    if type(target)~='table' then return false,'Invalid recorded target' end
    if not samePosition(ctx.pose,target) then
        local dx,dy,dz=target.x-ctx.pose.x,target.y-ctx.pose.y,target.z-ctx.pose.z
        if math.abs(dx)+math.abs(dy)+math.abs(dz)~=1 then return false,'Recorded path is not adjacent' end
        local action
        if dy==1 then action='up' elseif dy==-1 then action='down'
        else
            local vector=vectors[ctx.pose.facing]
            if dx==vector[1] and dz==vector[2] then action='forward'
            elseif dx==-vector[1] and dz==-vector[2] and not excavate then action='back'
            else
                local required=dx==1 and 'east' or dx==-1 and 'west' or dz==1 and 'south' or 'north'
                local delta=(headings[required]-headings[ctx.pose.facing])%4
                return turn(ctx,delta==3 and 'left' or 'right')
            end
        end
        if excavate then
            local ok,err=mining.prepareMove(ctx,action=='forward' and 'front' or action)
            if not ok then syncBack(ctx); return false,err end
        end
        local ok,err=turtle[action]()
        if not ok then return false,'Movement failed on '..action..': '..tostring(err) end
        ctx.pose.x,ctx.pose.y,ctx.pose.z=target.x,target.y,target.z
        sync(ctx)
        if ctx.miningPolicy and ctx.miningPolicy.knownAir then
            ctx.miningPolicy.knownAir[target.x..','..target.y..','..target.z]=true
        end
        return true
    end
    if ctx.pose.facing~=target.facing then
        local delta=(headings[target.facing]-headings[ctx.pose.facing])%4
        return turn(ctx,delta==3 and 'left' or 'right')
    end
    return true
end
local function receiver(side)
    if not peripheral or not peripheral.wrap then return nil,'Inventory receiver unavailable on '..side end
    if peripheral.hasType and not peripheral.hasType(side,'inventory') then return nil,'No inventory on '..side end
    local wrapped=peripheral.wrap(side)
    if not wrapped or type(wrapped.list)~='function' then return nil,'Receiver is not a verified inventory on '..side end
    local ok,items=pcall(wrapped.list)
    if not ok or type(items)~='table' then return nil,'Cannot read receiver on '..side end
    return wrapped
end
local function countListed(items,name)
    local n=0; for _,item in pairs(items) do if item.name==name then n=n+item.count end end; return n
end
local dropMethods={front='drop',up='dropUp',down='dropDown'}
local suckMethods={front='suck',up='suckUp',down='suckDown'}
local function service(ctx)
    if not equal(ctx.pose,ctx.origin) then return false,'Service requires exact home position and heading' end
    local output,err=receiver(ctx.config.outputSide); if not output then return false,err end
    local keep = {}
    if ctx.returnReason~='complete' and ctx.returnReason~='manual' then
        keep[ctx.config.fuelItem]=16
        keep[ctx.config.torchItem]=ctx.config.torchReserve
        keep[ctx.config.fillItem]=ctx.config.fillReserve
    end
    for slot=1,16 do
        local item=turtle.getItemDetail(slot)
        if item then
            local before=turtle.getItemCount(slot)
            local retained=math.min(before,keep[item.name] or 0)
            keep[item.name]=math.max(0,(keep[item.name] or 0)-retained)
            local amount=before-retained
            if amount>0 then
                local receivedBefore=countListed(output.list(),item.name)
                turtle.select(slot)
                local dropped=turtle[dropMethods[ctx.config.outputSide]](amount)
                local transferred=before-turtle.getItemCount(slot)
                local receivedAfter=countListed(output.list(),item.name)
                if not dropped or transferred~=amount or receivedAfter-receivedBefore~=transferred then
                    return false,'Output transfer failed or receiver full; remaining items retained'
                end
            end
        end
    end
    if ctx.returnReason=='complete' then ctx.phase='DONE'; return true end
    if ctx.returnReason=='manual' then ctx.phase='STOPPED'; ctx.stoppedPhase='SERVICE'; return true end
    local supply; supply,err=receiver(ctx.config.supplySide); if not supply then return false,err end
    local need=routeMoves(ctx.workPath)*2+ctx.config.fuelMargin+2
    for _=1,16 do
        local fuelOK=fuel(ctx,need)
        if fuelOK and stock(ctx,ctx.config.torchItem)>=ctx.config.torchReserve and stock(ctx,ctx.config.fillItem)>=ctx.config.fillReserve then
            ctx.phase='RESUMING'; ctx.travelIndex=2; return true
        end
        local slot
        for i=1,16 do if turtle.getItemCount(i)==0 then slot=i; break end end
        if not slot then return false,'Supply inventory has no free slot' end
        turtle.select(slot)
        if not turtle[suckMethods[ctx.config.supplySide]](64) then return false,'Missing fuel, torches or fill blocks in supply' end
        local item=turtle.getItemDetail(slot)
        if not item or (item.name~=ctx.config.fuelItem and item.name~=ctx.config.torchItem and item.name~=ctx.config.fillItem) then
            return false,'Unexpected supply item; correct supply and reconcile before resume'
        end
    end
    return false,'Required supplies unavailable after bounded restock'
end
local function recordPose(ctx)
    if equal(ctx.path[#ctx.path],ctx.pose) then return end
    -- Remove completed loops while retaining the checked route and home heading.
    local previous
    for i=#ctx.path,1,-1 do if samePosition(ctx.path[i],ctx.pose) then previous=i; break end end
    if previous then for i=#ctx.path,previous+1,-1 do ctx.path[i]=nil end end
    if not equal(ctx.path[#ctx.path],ctx.pose) then ctx.path[#ctx.path+1]=copy(ctx.pose) end
end
local function beginReturn(ctx,reason)
    ctx.workPath=copy(ctx.path); ctx.workPose=copy(ctx.pose)
    ctx.travelIndex=#ctx.path-1; ctx.returnReason=reason; ctx.phase='RETURNING'
    local ok,err=save(ctx); if not ok then return fail(ctx,err) end
    return 'MINE'
end
function M.initialize(ctx)
    local c=ctx.config or {}; ctx.config=c
    if type(c.job)~='string' or not c.job:match('^[%w_-]+$') then return fail(ctx,'Supply a unique --job name (letters, numbers, dash, underscore)') end
    if type(c.dimension)~='string' or c.dimension=='' then return fail(ctx,'Explicit dimension required') end
    if type(c.home)~='table' or not headings[c.home.facing] then return fail(ctx,'Explicit home coordinates and heading required') end
    for _,axis in ipairs({'x','y','z'}) do if type(c.home[axis])~='number' or c.home[axis]%1~=0 then return fail(ctx,'Home coordinates must be integers') end end
    if type(c.bounds)~='table' or type(c.bounds.min)~='table' or type(c.bounds.max)~='table' then return fail(ctx,'Explicit excavation bounds required') end
    for _,axis in ipairs({'x','y','z'}) do
        local a,b=c.bounds.min[axis],c.bounds.max[axis]
        if type(a)~='number' or type(b)~='number' or a%1~=0 or b%1~=0 or a>b then return fail(ctx,'Invalid excavation bounds') end
    end
    local defaults={length=6,branchInterval=3,branchLength=2,torchInterval=3,fuelMargin=8,torchReserve=1,fillReserve=8}
    for key,value in pairs(defaults) do
        if c[key]==nil then c[key]=value end
        if type(c[key])~='number' or c[key]%1~=0 or c[key]<1 or c[key]>4096 then return fail(ctx,'Invalid '..key..' (integer 1..4096 required)') end
    end
    if c.length>256 or c.branchLength>64 then return fail(ctx,'Job exceeds bounded pilot size (length 256, branch length 64)') end
    if c.torchReserve>64 or c.fillReserve>64 then return fail(ctx,'Supply reserves must fit one stack each (1..64)') end
    c.fuelItem=c.fuelItem or 'minecraft:coal'; c.torchItem=c.torchItem or 'minecraft:torch'; c.fillItem=c.fillItem or 'minecraft:cobblestone'
    if c.torchItem~='minecraft:torch' then return fail(ctx,'Supported torch item is minecraft:torch') end
    if type(c.fuelItem)~='string' or not c.fuelItem:match('^[%w_]+:[%w_]+$') or type(c.fillItem)~='string' or policy.classify(c.fillItem,c)~='terrain' or mining.FILL_BLACKLIST[c.fillItem] then return fail(ctx,'Configure a valid fuel item and permitted solid fill item') end
    c.outputSide=c.outputSide or 'down'; c.supplySide=c.supplySide or 'up'
    if not dropMethods[c.outputSide] or not suckMethods[c.supplySide] or c.outputSide==c.supplySide then return fail(ctx,'Choose separate output/supply sides: front, up or down') end
    ctx.identity={ computerId=os and os.getComputerID and os.getComputerID() or 'unavailable', label=os and os.getComputerLabel and os.getComputerLabel() or '' }
    ctx.origin=copy(c.home)
    local ok,steps=pcall(strategy.generate,c.length,c.branchInterval,c.branchLength,c.torchInterval)
    if not ok or type(steps)~='table' or #steps==0 then return fail(ctx,'Invalid mining strategy: '..tostring(steps)) end
    ctx.strategy=steps
    local createOK,p,err=pcall(policy.create,ctx.origin,steps,c)
    if not createOK or not p then return fail(ctx,'Unsafe job bounds: '..tostring(err or p)) end
    ctx.miningPolicy=p
    local stored; stored,err=journal.load(ctx)
    if stored==nil then return fail(ctx,err) end
    if stored then
        if not c.resume then return fail(ctx,'Existing job checkpoint; use explicit --resume after verifying physical pose') end
        if not equal(ctx.identity,stored.identity) then return fail(ctx,'Saved job belongs to a different turtle identity') end
        if type(stored.config)~='table' then return fail(ctx,'Corrupt saved configuration') end
        local config=copy(c); config.resume=nil
        local oldConfig=copy(stored.config); oldConfig.resume=nil
        if not equal(config,oldConfig) then return fail(ctx,'Resume configuration differs from saved job') end
        if type(stored.config)~='table' or not equal(stored.origin,ctx.origin) then return fail(ctx,'Corrupt saved job identity or home') end
        if type(stored.pose)~='table' or not headings[stored.pose.facing] or type(stored.path)~='table' or #stored.path<1 or type(stored.pointer)~='number' or stored.pointer<1 or stored.pointer>#steps+1 then return fail(ctx,'Corrupt saved job state') end
        for _,axis in ipairs({'x','y','z'}) do if type(stored.pose[axis])~='number' then return fail(ctx,'Corrupt saved pose') end end
        local phases={MINING=true,RETURNING=true,SERVICE=true,RESUMING=true,DONE=true,STOPPED=true,NEEDS_HELP=true}
        if not phases[stored.phase] then return fail(ctx,'Corrupt saved phase') end
        local function validPose(pose)
            if type(pose)~='table' or not headings[pose.facing] then return false end
            for _,axis in ipairs({'x','y','z'}) do if type(pose[axis])~='number' or pose[axis]%1~=0 then return false end end
            return equal(pose,ctx.origin) or p.allowed[policy.key(pose)] or samePosition(pose,ctx.origin)
        end
        local function validPath(path)
            if type(path)~='table' or #path<1 or #path>50000 or not equal(path[1],ctx.origin) then return false end
            local entries=0
            for key in pairs(path) do if type(key)~='number' or key%1~=0 or key<1 or key>#path then return false end; entries=entries+1 end
            if entries~=#path then return false end
            for i,pose in ipairs(path) do
                if not validPose(pose) then return false end
                if i>1 then
                    local last=path[i-1]
                    if math.abs(last.x-pose.x)+math.abs(last.y-pose.y)+math.abs(last.z-pose.z)>1 then return false end
                end
            end
            return true
        end
        if stored.pointer%1~=0 or not validPose(stored.pose) or not validPath(stored.path) then return fail(ctx,'Corrupt saved pose or return path') end
        local recoveryPhase=stored.phase=='STOPPED' and stored.stoppedPhase or stored.phase=='NEEDS_HELP' and stored.failedPhase or stored.phase
        if not phases[recoveryPhase] or recoveryPhase=='NEEDS_HELP' or recoveryPhase=='STOPPED' then return fail(ctx,'Corrupt saved recovery phase') end
        if recoveryPhase=='RETURNING' or recoveryPhase=='RESUMING' or recoveryPhase=='SERVICE' then
            if not validPath(stored.workPath) or not validPose(stored.workPose) or not equal(stored.workPath[#stored.workPath],stored.workPose) or type(stored.travelIndex)~='number' or stored.travelIndex%1~=0 or stored.travelIndex<0 or stored.travelIndex>#stored.workPath+1 then return fail(ctx,'Corrupt saved service route') end
        end
        if recoveryPhase=='MINING' and not equal(stored.path[#stored.path],stored.pose) then return fail(ctx,'Saved mining pose differs from return path') end
        if (recoveryPhase=='DONE' or recoveryPhase=='SERVICE') and not equal(stored.pose,ctx.origin) then return fail(ctx,'Saved home phase is away from home') end
        if recoveryPhase=='RETURNING' or recoveryPhase=='RESUMING' then
            local at=stored.travelIndex
            local a=stored.workPath[at]
            local b=stored.workPath[recoveryPhase=='RETURNING' and at+1 or at-1]
            if not ((a and samePosition(stored.pose,a)) or (b and samePosition(stored.pose,b))) then return fail(ctx,'Saved travel pose differs from route cursor') end
        end
        for _,map in ipairs({stored.knownAir,stored.placedTorches}) do
            if type(map)~='table' then return fail(ctx,'Corrupt saved policy') end
            for key,value in pairs(map) do
                if type(key)~='string' or value~=true or (not p.allowed[key] and key~=policy.key(ctx.origin)) then return fail(ctx,'Corrupt saved excavation permissions') end
            end
        end
        for _,k in ipairs(journal.fields) do if k~='config' then ctx[k]=stored[k] end end
        if ctx.phase=='NEEDS_HELP' then ctx.phase=ctx.failedPhase; ctx.lastError=nil; ctx.failedPhase=nil end
        if ctx.phase=='STOPPED' then
            ctx.phase=ctx.stoppedPhase or 'MINING'; ctx.stoppedPhase=nil
            if ctx.returnReason=='manual' then ctx.returnReason='inventory' end
        end
        if type(ctx.knownAir)~='table' or type(ctx.placedTorches)~='table' then return fail(ctx,'Corrupt saved policy state') end
        ctx.miningPolicy.knownAir=ctx.knownAir
        ctx.miningPolicy.placedTorches=ctx.placedTorches
    else
        if c.resume then return fail(ctx,'No saved job to resume') end
        ctx.pose=copy(ctx.origin); ctx.path={copy(ctx.pose)}; ctx.pointer=1; ctx.phase='MINING'
    end
    sync(ctx)
    if equal(ctx.pose,ctx.origin) and ctx.phase~='DONE' then
        local output,why=receiver(c.outputSide); if not output then return fail(ctx,why) end
        local supply; supply,why=receiver(c.supplySide); if not supply then return fail(ctx,why) end
    end
    local saved; saved,err=save(ctx); if not saved then return fail(ctx,err) end
    return (ctx.phase=='DONE' or ctx.phase=='STOPPED') and 'EXIT' or 'MINE'
end
function M.requestStop(ctx)
    if ctx.intent then return fail(ctx,'Cannot checkpoint stop during uncertain action') end
    ctx.stoppedPhase=ctx.phase; ctx.phase='STOPPED'
    local ok,err=save(ctx); if not ok then return fail(ctx,err) end
    return 'EXIT'
end
function M.requestReturn(ctx)
    if ctx.phase=='MINING' then return beginReturn(ctx,'manual') end
    if ctx.phase=='RETURNING' or ctx.phase=='SERVICE' then
        ctx.returnReason='manual'
        local ok,err=save(ctx); if not ok then return fail(ctx,err) end
        return 'MINE'
    end
    if ctx.phase=='RESUMING' then
        local prefix={}
        for i=1,math.min(#ctx.workPath,ctx.travelIndex-1) do prefix[i]=copy(ctx.workPath[i]) end
        ctx.path=prefix; recordPose(ctx)
        return beginReturn(ctx,'manual')
    end
    return 'MINE'
end
function M.step(ctx)
    if ctx.phase=='DONE' or ctx.phase=='STOPPED' then return 'EXIT' end
    if ctx.phase=='NEEDS_HELP' or ctx.intent then return fail(ctx,ctx.lastError or 'Uncertain action requires reconciliation') end
    if ctx.phase=='RETURNING' or ctx.phase=='RESUMING' then
        local returning=ctx.phase=='RETURNING'
        local path=ctx.workPath
        if not path or not ctx.travelIndex then return fail(ctx,'Missing persisted travel path') end
        if (returning and ctx.travelIndex<1) or (not returning and ctx.travelIndex>#path) then
            if returning then
                if not equal(ctx.pose,ctx.origin) then return fail(ctx,'Home pose verification failed') end
                ctx.phase='SERVICE'
            else
                if not equal(ctx.pose,ctx.workPose) then return fail(ctx,'Work pose restoration failed') end
                ctx.path=copy(path); ctx.phase='MINING'
            end
            local ok,err=save(ctx); if not ok then return fail(ctx,err) end; return 'MINE'
        end
        local target=path[ctx.travelIndex]
        local ok,err=transact(ctx,'cleared route',function()
            local enough,why=fuel(ctx,routeMoves(path,2,returning and ctx.travelIndex+1 or #path)+ctx.config.fuelMargin+1)
            if not enough then return false,why end
            local moved,reason=approach(ctx,target,false)
            if moved and equal(ctx.pose,target) then ctx.travelIndex=ctx.travelIndex+(returning and -1 or 1) end
            return moved,reason
        end)
        if not ok then return fail(ctx,err) end; return 'MINE'
    end
    if ctx.phase=='SERVICE' then
        local ok,err=transact(ctx,'checked unload and resupply',function() return service(ctx) end)
        if not ok then return fail(ctx,err) end
        return (ctx.phase=='DONE' or ctx.phase=='STOPPED') and 'EXIT' or 'MINE'
    end
    if ctx.phase~='MINING' then return fail(ctx,'Unknown mining phase') end
    local instruction=ctx.strategy[ctx.pointer]
    if not instruction or instruction.type=='done' then return beginReturn(ctx,'complete') end
    if emptySlots()<2 then return beginReturn(ctx,'inventory') end
    if stock(ctx,ctx.config.torchItem)<ctx.config.torchReserve or stock(ctx,ctx.config.fillItem)<ctx.config.fillReserve then return beginReturn(ctx,'supplies') end
    local enough,why=transact(ctx,'fuel reserve',function() return fuel(ctx,routeMoves(ctx.path)+ctx.config.fuelMargin+2) end)
    if not enough then
        if turtle.getFuelLevel()~='unlimited' and turtle.getFuelLevel()<routeMoves(ctx.path)+ctx.config.fuelMargin then return fail(ctx,why) end
        return beginReturn(ctx,'fuel')
    end
    local expected=(headings[ctx.origin.facing]+instruction.facing)%4
    if instruction.type=='turn' then expected=(expected+(instruction.data=='left' and 1 or 3))%4 end
    if ctx.pose.facing~=names[expected] then
        local aligned,reason=transact(ctx,'restore instruction heading',function()
            local delta=(expected-headings[ctx.pose.facing])%4
            local moved,detail=turn(ctx,delta==3 and 'left' or 'right')
            recordPose(ctx); return moved,detail
        end)
        if not aligned then return fail(ctx,reason) end
        return 'MINE'
    end
    local ok,err=transact(ctx,instruction.type,function()
        local success,reason=true
        if instruction.type=='move' then
            local target=strategy.localToWorld(ctx.origin,instruction)
            target.facing=ctx.pose.facing
            success,reason=approach(ctx,target,true)
        elseif instruction.type=='turn' then success,reason=turn(ctx,instruction.data)
        elseif instruction.type=='mine_neighbors' then success,reason=mining.scanAndMineNeighbors(ctx); syncBack(ctx)
        elseif instruction.type=='place_torch' then success,reason=mining.placeTorch(ctx,instruction.data or 'down'); syncBack(ctx)
        elseif instruction.type=='dump_trash' then -- Keep items until a checked receiver is reached.
        else return false,'Unsupported mining instruction: '..tostring(instruction.type) end
        recordPose(ctx)
        if success and instruction.type=='move' then
            local destination=strategy.localToWorld(ctx.origin,instruction)
            if not samePosition(ctx.pose,destination) then return true end
        end
        if success then ctx.pointer=ctx.pointer+1 end
        return success,reason
    end)
    if not ok then
        if err=='inventory_capacity' and not ctx.intent then return beginReturn(ctx,'inventory') end
        return fail(ctx,err)
    end
    return 'MINE'
end
return M
