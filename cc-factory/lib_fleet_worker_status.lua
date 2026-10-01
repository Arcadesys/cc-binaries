-- High contrast, wrapped text and keyboard pages on native turtle terminals.
local M={}
local function wrap(lines,text,width)
    text=tostring(text)
    for paragraph in (text..'\n'):gmatch('(.-)\n') do
        if paragraph=='' then lines[#lines+1]='' end
        while #paragraph>width do
            local part=paragraph:sub(1,width)
            local cut=part:match('^.*()%s') or width
            if cut<1 then cut=width end
            lines[#lines+1]=paragraph:sub(1,cut):gsub('%s+$','')
            paragraph=paragraph:sub(cut+1):gsub('^%s+','')
        end
        if paragraph~='' then lines[#lines+1]=paragraph end
    end
end
local function location(home)
    return string.format('%s, %s, %s / %s',tostring(home.x),tostring(home.y),tostring(home.z),tostring(home.facing))
end
function M.render(worker,page)
    local width,height=term.getSize();width=math.max(1,width);height=math.max(1,height)
    local s=worker:state();local lines={}
    local function add(t) wrap(lines,t,width) end
    add('MINING FLEET WORKER');add('STATE: '..s.status)
    add('FLEET: '..worker.config.fleet);add('COORDINATOR: '..worker.config.coordinatorId)
    add('DIMENSION: '..worker.config.dimension)
    add('CONFIGURED HOME: '..location(worker.config.home))
    add('SAVED HOME POSE: '..location(s.home or worker.config.home))
    if s.status=='AWAITING_PREFLIGHT' then
        add('Confirm physical saved HOME pose and dimension before starting.')
        add('A saved HOME pose does not prove the turtle is physically home.')
        add('Check storage, supplies, backup and authorized work area.')
    end
    add('JOB: '..tostring(s.job or 'none'))
    if s.phase then add('PHASE: '..s.phase) end
    if s.pose then add('WORK POSE: '..location(s.pose)) end
    if s.reason then add('REASON: '..s.reason) end
    local body=math.max(1,height-2);local pages=math.max(1,math.ceil(#lines/body))
    page=math.min(pages,math.max(1,page or 1))
    term.setBackgroundColor(colors.black);term.setTextColor(colors.white);term.clear()
    for row=1,body do term.setCursorPos(1,row);term.write(lines[(page-1)*body+row] or '') end
    local ended=s.status=='STOPPED' or s.status=='NEEDS_HELP'
    local control=ended and 'Q close' or s.status=='AWAITING_PREFLIGHT' and 'ENTER start / Q stop' or 'Q stop'
    if height>=2 then term.setCursorPos(1,height-1);term.write(('PAGE '..page..'/'..pages..'  UP/DOWN pages'):sub(1,width)) end
    term.setCursorPos(1,height);term.write(control:sub(1,width))
    return page,pages
end
return M
