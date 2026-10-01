-- Fail-closed mining policy. No tags or name fragments confer dig permission.
local policy = {}
local strategy = require('lib_strategy_branchmine')
local terrain, ores = {}, {}
for _,n in ipairs({'stone','deepslate','granite','diorite','andesite','tuff','calcite','dirt','grass_block','cobblestone','cobbled_deepslate','sand','red_sand','gravel','netherrack','basalt','blackstone','end_stone'}) do terrain['minecraft:'..n]=true end
for _,n in ipairs({'coal','iron','copper','gold','redstone','emerald','lapis','diamond'}) do ores['minecraft:'..n..'_ore']=true; ores['minecraft:deepslate_'..n..'_ore']=true end
for _,n in ipairs({'nether_gold_ore','nether_quartz_ore','ancient_debris'}) do ores['minecraft:'..n]=true end
policy.TERRAIN, policy.ORES = terrain, ores
function policy.key(p) return p.x..','..p.y..','..p.z end
local function protected(name)
    return type(name)~='string' or name:find('chest',1,true) or name:find('barrel',1,true) or name:find('shulker',1,true) or name:find('turtle',1,true) or name:find('computer',1,true) or name:find('machine',1,true) or name:find('furnace',1,true) or name:find('hopper',1,true) or name:find('spawner',1,true)
end
function policy.classify(block, config)
    local name=type(block)=='table' and block.name or block
    if protected(name) then return 'protected' end
    if name=='minecraft:water' or name=='minecraft:lava' then return 'fluid' end
    if ores[name] or (type(config)=='table' and type(config.mineableOres)=='table' and config.mineableOres[name]==true) then return 'ore' end
    if terrain[name] or (type(config)=='table' and type(config.mineableBlocks)=='table' and config.mineableBlocks[name]==true) then return 'terrain' end
    return 'unknown'
end
function policy.create(origin, steps, config)
    local p={allowed={},knownAir={},config=config or {},maxFallingBlocks=8,placedTorches={}}
    p.knownAir[policy.key(origin)]=true
    local failure
    local function allow(v)
        -- The bay and its floor/ceiling/storage are never neighbor excavation.
        if v.z<1 then return end
        local world=strategy.localToWorld(origin,v)
        local bounds=(config or {}).bounds
        if bounds then
            for _,axis in ipairs({'x','y','z'}) do
                if not bounds.min or not bounds.max or type(bounds.min[axis])~='number' or type(bounds.max[axis])~='number' or bounds.min[axis]~=bounds.min[axis] or bounds.max[axis]~=bounds.max[axis] or math.abs(bounds.min[axis])==math.huge or math.abs(bounds.max[axis])==math.huge or world[axis]<bounds.min[axis] or world[axis]>bounds.max[axis] then
                    failure='planned excavation outside configured bounds'; return
                end
            end
        end
        p.allowed[policy.key(world)]=true
    end
    for _,s in ipairs(steps) do
        if s.type=='move' then allow(s) end
        if s.torchTarget then allow(s.torchTarget) end
        if s.type=='mine_neighbors' then
            for _,d in ipairs({{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}) do allow({x=s.x+d[1],y=s.y+d[2],z=s.z+d[3]}) end
        end
    end
    if failure then return nil,failure end
    return p
end
function policy.checkTarget(ctx,pos)
    local p=ctx.miningPolicy
    if not p then return false,'mining policy missing' end
    if p.allowed[policy.key(pos)] or p.knownAir[policy.key(pos)] then return true end
    return false,'outside excavation bounds'
end
function policy.checkDig(ctx,block,pos)
    local ok,err=policy.checkTarget(ctx,pos); if not ok then return false,err end
    if not ctx.miningPolicy.allowed[policy.key(pos)] then return false,'protected home cell' end
    local kind=policy.classify(block,ctx.miningPolicy.config)
    if kind=='ore' or kind=='terrain' then return true end
    return false,kind..' block: '..tostring(block and block.name)
end
function policy.markAir(ctx,pos) ctx.miningPolicy.knownAir[policy.key(pos)]=true end
return policy
