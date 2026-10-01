-- Checked mining primitives; every failure is returned to the caller.
local mining = {}
local inventory = require('lib_inventory')
local movement = require('lib_movement')
local policy = require('lib_mine_policy')
mining.TRASH_BLOCKS = inventory.DEFAULT_TRASH
mining.FILL_BLACKLIST={['minecraft:sand']=true,['minecraft:red_sand']=true,['minecraft:gravel']=true}
function mining.isOre(name) return policy.classify(name)=='ore' end
local vectors={north={0,0,-1},east={1,0,0},south={0,0,1},west={-1,0,0}}
function mining.target(ctx,dir)
    local p=movement.getPosition(ctx)
    local d=dir=='up' and {0,1,0} or dir=='down' and {0,-1,0} or vectors[movement.getFacing(ctx)]
    return {x=p.x+d[1],y=p.y+d[2],z=p.z+d[3]}
end
local function apis(dir)
    if dir=='front' then return turtle.inspect,turtle.dig,turtle.place
    elseif dir=='up' then return turtle.inspectUp,turtle.digUp,turtle.placeUp
    elseif dir=='down' then return turtle.inspectDown,turtle.digDown,turtle.placeDown end
end
local function fill(ctx,dir,pos)
    local inspect,_,place=apis(dir)
    for slot=1,16 do
        local item=turtle.getItemDetail(slot)
        if item and policy.classify(item.name)=='terrain' and not mining.FILL_BLACKLIST[item.name] then
            if not turtle.select(slot) then return false,'fill selection failed' end
            local ok,err=place(); if not ok then return false,'sealing failed: '..tostring(err) end
            local present,block=inspect()
            if not present or block.name~=item.name then return false,'seal verification failed' end
            ctx.miningPolicy.knownAir[policy.key(pos)]=nil
            return true
        end
    end
    return false,'no permitted solid fill blocks'
end
function mining.prepareMove(ctx,dir)
    local inspect,dig=apis(dir); if not inspect then return false,'invalid direction' end
    local pos=mining.target(ctx,dir)
    local ok,err=policy.checkTarget(ctx,pos); if not ok then return false,err end
    local limit=ctx.miningPolicy.maxFallingBlocks or 8
    if type(limit)~='number' or limit%1~=0 or limit<1 or limit>32 then return false,'invalid falling block limit' end
    for count=0,limit do
        local present,block=inspect()
        if not present then
            if ctx.miningPolicy.knownAir[policy.key(pos)] then return true end
            return false,'unknown opening at '..policy.key(pos)
        end
        ok,err=policy.checkDig(ctx,block,pos); if not ok then return false,err end
        if count==limit then return false,'falling block limit exceeded' end
        -- One instruction may collect several different drops. Recheck before
        -- each physical dig so a long scan/falling stack cannot spill inventory.
        local empty=0
        for slot=1,16 do if turtle.getItemCount(slot)==0 then empty=empty+1 end end
        if empty<2 then return false,'inventory_capacity' end
        ok,err=dig(); if not ok then return false,'dig failed: '..tostring(err) end
        policy.markAir(ctx,pos)
    end
    return false,'falling block limit exceeded'
end
function mining.mineAndFill(ctx,dir)
    if not ctx.miningPolicy then return false,'mining policy missing' end
    local inspect=apis(dir); if not inspect then return false,'invalid direction' end
    local pos=mining.target(ctx,dir)
    local allowed=policy.checkTarget(ctx,pos)
    if not allowed then return true end -- preserve bay and anything beyond bounds
    local present,block=inspect()
    if not present then
        if ctx.miningPolicy.knownAir[policy.key(pos)] then return true end
        return false,'unknown opening at '..policy.key(pos)
    end
    if ctx.miningPolicy.placedTorches and ctx.miningPolicy.placedTorches[policy.key(pos)] and (block.name=='minecraft:torch' or block.name=='minecraft:wall_torch') then return true end
    local kind=policy.classify(block,ctx.miningPolicy.config)
    if kind=='terrain' then return true end
    if kind~='ore' then return false,kind..' block: '..tostring(block.name) end
    local ok,err=mining.prepareMove(ctx,dir); if not ok then return false,err end
    return fill(ctx,dir,pos)
end
function mining.scanAndMineNeighbors(ctx)
    for _,dir in ipairs({'up','down'}) do
        local ok,err=mining.mineAndFill(ctx,dir); if not ok then return false,err end
    end
    for i=1,4 do
        local ok,err=mining.mineAndFill(ctx,'front'); if not ok then return false,err end
        ok,err=movement.turnRight(ctx); if not ok then return false,err end
    end
    return true
end
function mining.placeTorch(ctx,dir)
    if not ctx.miningPolicy then return false,'mining policy missing' end
    dir=dir or 'down'
    local inspect,_,place=apis(dir)
    if not inspect then return false,'invalid torch direction' end
    local pos=mining.target(ctx,dir)
    local seen,existing=inspect()
    if seen and ctx.miningPolicy.placedTorches and ctx.miningPolicy.placedTorches[policy.key(pos)] and (existing.name=='minecraft:torch' or existing.name=='minecraft:wall_torch') then return true end
    local ok,err=mining.prepareMove(ctx,dir)
    if not ok then return false,err end
    local present=inspect(); if present then return false,'torch target obstructed' end
    local name=(ctx.config or {}).torchItem or 'minecraft:torch'
    -- Lifecycle service changes turtle slots directly; cached slot assignments
    -- cannot identify the item that will actually be placed after resupply.
    ok=inventory.selectMaterial(ctx,name,{force=true})
    if not ok then ctx.missingMaterial=name; return false,'missing torches' end
    local selected=turtle.getItemDetail(turtle.getSelectedSlot())
    if not selected or selected.name~=name then return false,'selected torch item changed; placement stopped' end
    ok,err=place(); if not ok then return false,'torch placement failed: '..tostring(err) end
    local seen,block=inspect()
    if not seen or (block.name~='minecraft:torch' and block.name~='minecraft:wall_torch') then return false,'torch verification failed' end
    ctx.miningPolicy.knownAir[policy.key(pos)]=nil
    ctx.miningPolicy.placedTorches=ctx.miningPolicy.placedTorches or {}
    ctx.miningPolicy.placedTorches[policy.key(pos)]=true
    return true
end
return mining
