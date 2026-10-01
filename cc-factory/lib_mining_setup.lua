-- One labelled keyboard question per screen. No turtle actions in setup.
local strategy = require('lib_strategy_branchmine')
local M = {}
local function wrap(text,width)
    local lines={}
    while #text>width do
        local cut=text:sub(1,width):match('^.*() ')
        if cut and cut>1 then lines[#lines+1]=text:sub(1,cut-1);text=text:sub(cut+1)
        else lines[#lines+1]=text:sub(1,width);text=text:sub(width+1) end
    end
    lines[#lines+1]=text;return lines
end
function M.renderPrompt(label,help,default,errorMessage)
    if not term or not term.getSize then return end
    local w,h=term.getSize()
    if colors and term.setBackgroundColor then term.setBackgroundColor(colors.black);term.setTextColor(colors.white) end
    term.clear()
    local row=1
    local function show(text)
        for _,line in ipairs(wrap(text,w)) do
            if row<=h-3 then term.setCursorPos(1,row);term.write(line);row=row+1 end
        end
    end
    show('SAFE BRANCH MINE SETUP')
    row=row+1;show(label);show(help)
    if default then show('ENTER keeps: '..tostring(default)) end
    if errorMessage then show('CHECK: '..errorMessage) end
    term.setCursorPos(1,math.max(1,h-2));term.write(('Q + ENTER: CANCEL'):sub(1,w))
    term.setCursorPos(1,math.max(1,h-1));term.write('VALUE: ');term.setCursorPos(8,math.max(1,h-1))
end
local function ask(label,help,default,parse)
    local problem
    while true do
        M.renderPrompt(label,help,default,problem)
        local answer=read()
        if answer==nil or answer:lower()=='q' then return nil end
        if answer=='' and default~=nil then answer=tostring(default) end
        local value,err=parse(answer)
        if value~=nil then return value end
        problem=err or 'Enter a valid value.'
    end
end
local function text(answer)
    if answer=='' then return nil,'This field is required.' end
    return answer
end
local function point(answer)
    local x,y,z=answer:match('^%s*([+-]?%d+)[,%s]+([+-]?%d+)[,%s]+([+-]?%d+)%s*$')
    if not x then return nil,'Use three integers: X Y Z.' end
    return {x=tonumber(x),y=tonumber(y),z=tonumber(z)}
end
local function pointText(p) return p.x..' '..p.y..' '..p.z end
local function number(max)
    return function(answer)
        local n=tonumber(answer)
        if not n or n%1~=0 or n<1 or n>max then return nil,'Use an integer from 1 to '..max..'.' end
        return n
    end
end
local function choice(values)
    return function(answer)
        answer=answer:lower()
        if values[answer] then return answer end
        return nil,'Use '..table.concat(values,', ')..'.'
    end
end
local function choices(list)
    for _,value in ipairs(list) do list[value]=true end
    return list
end
function M.collect()
    local c={}
    c.job=ask('JOB NAME','Use a unique name for this turtle.',nil,function(a)
        if a:match('^[%w_-]+$') then return a end
        return nil,'Use letters, numbers, dash or underscore.'
    end);if not c.job then return nil end
    c.mode=ask('NEW OR RESUME','Resume requires the same saved settings.','new',choice(choices({'new','resume'})));if not c.mode then return nil end
    c.home=ask('HOME COORDINATES','Enter your marked home: X Y Z.',nil,point);if not c.home then return nil end
    c.heading=ask('HOME HEADING','Enter north, east, south or west.',nil,choice(choices({'north','east','south','west'})));if not c.heading then return nil end
    c.home.facing=c.heading
    c.dimension=ask('WORLD / DIMENSION','Enter its exact ID, e.g. minecraft:overworld.',nil,text);if not c.dimension then return nil end
    for _,field in ipairs({{'length','SPINE LENGTH',6,256},{'interval','BRANCH INTERVAL',3,4096},{'branch','BRANCH LENGTH',2,64},{'torch','TORCH INTERVAL',3,4096}}) do
        c[field[1]]=ask(field[2],'Tiny pilot defaults: 6 / 3 / 2 / 3.',field[3],number(field[4]));if not c[field[1]] then return nil end
    end
    c.output=ask('OUTPUT INVENTORY SIDE','Separate receiving inventory at home.','down',choice(choices({'front','up','down'})));if not c.output then return nil end
    c.supply=ask('SUPPLY INVENTORY SIDE','Fuel, torches and solid fill at home.','up',function(a)
        local side,err=choice(choices({'front','up','down'}))(a)
        if side==c.output then return nil,'Supply must differ from output.' end
        return side,err
    end);if not c.supply then return nil end
    local plan=strategy.generate(c.length,c.interval,c.branch,c.torch)
    local b=plan.bounds
    local min,max={x=math.huge,y=math.huge,z=math.huge},{x=-math.huge,y=-math.huge,z=-math.huge}
    for _,x in ipairs({b.min.x,b.max.x}) do
        for _,y in ipairs({b.min.y,b.max.y}) do
            for _,z in ipairs({b.min.z,b.max.z}) do
                local p=strategy.localToWorld(c.home,{x=x,y=y,z=z})
                for _,axis in ipairs({'x','y','z'}) do min[axis]=math.min(min[axis],p[axis]);max[axis]=math.max(max[axis],p[axis]) end
            end
        end
    end
    c.min=ask('EXCAVATION BOUNDS MIN','Review proposed world limits: X Y Z.',pointText(min),point);if not c.min then return nil end
    c.max=ask('EXCAVATION BOUNDS MAX','Include neighbours and torch niches.',pointText(max),point);if not c.max then return nil end
    local argv={'mine','--job',c.job,'--dimension',c.dimension,'--heading',c.heading,
        '--length',tostring(c.length),'--branch-interval',tostring(c.interval),'--branch-length',tostring(c.branch),
        '--torch-interval',tostring(c.torch),'--output-side',c.output,'--supply-side',c.supply}
    for _,field in ipairs({{'--home',c.home},{'--bounds-min',c.min},{'--bounds-max',c.max}}) do
        argv[#argv+1]=field[1]
        for _,axis in ipairs({'x','y','z'}) do argv[#argv+1]=tostring(field[2][axis]) end
    end
    if c.mode=='resume' then argv[#argv+1]='--resume' end
    return argv
end
return M
