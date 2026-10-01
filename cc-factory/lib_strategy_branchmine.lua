-- Local x is right, z is forward; headings are clockwise from home.
local strategy = {}
local function positive(v, default)
    v = tonumber(v)
    if v and (v~=v or v==math.huge or v==-math.huge or v>4096) then error('strategy parameter must be finite and at most 4096') end
    return v and v >= 1 and math.floor(v) or default
end
function strategy.localToWorld(origin, p)
    local f = origin.facing
    local dx, dz
    if f == 'north' then dx, dz = p.x, -p.z
    elseif f == 'east' then dx, dz = p.z, p.x
    elseif f == 'south' then dx, dz = -p.x, p.z
    elseif f == 'west' then dx, dz = -p.z, -p.x
    else error('invalid origin heading') end
    return {x=origin.x+dx,y=origin.y+p.y,z=origin.z+dz}
end
function strategy.generate(length, interval, branchLength, torchInterval)
    length, interval = positive(length,60), positive(interval,3)
    branchLength, torchInterval = positive(branchLength,16), positive(torchInterval,6)
    if length>256 or branchLength>64 then error('strategy exceeds bounded pilot size') end
    local steps, x,y,z,f = {},0,0,0,0
    local function add(kind,data)
        steps[#steps+1]={type=kind,x=x,y=y,z=z,facing=f,data=data}
    end
    local function turn(right)
        f=(f+(right and 1 or 3))%4; add('turn',right and 'right' or 'left')
    end
    local function move()
        if f==0 then z=z+1 elseif f==1 then x=x+1 elseif f==2 then z=z-1 else x=x-1 end
        add('move')
    end
    local function branch(right)
        turn(right)
        for j=1,branchLength do move(); add('mine_neighbors') end
        y=1; add('move')
        turn(true); turn(true)
        for j=branchLength,1,-1 do
            -- Lower corridor is known clear; torches stand on its solid floor.
            move()
        end
        y=0; add('move')
        -- Left return faces right: left restores forward. Right does the reverse.
        turn(right)
    end
    for i=1,length do
        move(); add('mine_neighbors')
        if i%interval==0 then branch(false); branch(true) end
    end
    y=1; add('move'); turn(true); turn(true)
    for i=length,2,-1 do
        move()
    end
    y=0; add('move'); move(); turn(true); turn(true); add('done')
    -- Select niches only after the whole route is known, so lights never occupy it.
    local route = {}
    local function key(a,b,c) return a..','..b..','..c end
    route[key(0,0,0)] = true
    for _,s in ipairs(steps) do if s.type=='move' then route[key(s.x,s.y,s.z)] = true end end
    local lit, count = {}, 0
    local delta={{0,1},{1,0},{0,-1},{-1,0}}
    for _,s in ipairs(steps) do
        lit[#lit+1]=s
        if s.type=='mine_neighbors' then
            count=count+1
            if count%torchInterval==0 or math.abs(s.x)==branchLength or s.z==length then
                for _,facing in ipairs({(s.facing+1)%4,(s.facing+3)%4}) do
                    local d=delta[facing+1]
                    local tx,tz=s.x+d[1],s.z+d[2]
                    if tz>=1 and not route[key(tx,s.y,tz)] then
                        local turns=(facing-s.facing)%4
                        local f=s.facing
                        for i=1,turns do f=(f+1)%4; lit[#lit+1]={type='turn',x=s.x,y=s.y,z=s.z,facing=f,data='right'} end
                        lit[#lit+1]={type='place_torch',x=s.x,y=s.y,z=s.z,facing=f,data='front',torchTarget={x=tx,y=s.y,z=tz}}
                        for i=1,(4-turns)%4 do f=(f+1)%4; lit[#lit+1]={type='turn',x=s.x,y=s.y,z=s.z,facing=f,data='right'} end
                        break
                    end
                end
            end
        end
    end
    steps=lit
    local bounds={min={x=0,y=0,z=0},max={x=0,y=0,z=0}}
    local function include(p)
        for _,axis in ipairs({'x','y','z'}) do bounds.min[axis]=math.min(bounds.min[axis],p[axis]); bounds.max[axis]=math.max(bounds.max[axis],p[axis]) end
    end
    for _,s in ipairs(steps) do
        include(s)
        if s.torchTarget then include(s.torchTarget) end
        if s.type=='mine_neighbors' then
            for _,d in ipairs({{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}) do
                local p={x=s.x+d[1],y=s.y+d[2],z=s.z+d[3]}
                if p.z>=1 then include(p) end
            end
        end
    end
    steps.bounds=bounds
    return steps
end
return strategy
