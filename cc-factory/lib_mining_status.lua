-- High contrast reflow and keyboard paging, including every error-reason line.
local M = {}
function M.render(ctx, ready)
    if not term or not term.getSize then return end
    local w,h=term.getSize()
    if term.setBackgroundColor and colors then term.setBackgroundColor(colors.black); term.setTextColor(colors.white) end
    term.clear()
    local title=ready and (ctx.config.resume and 'READY - VERIFY SAVED POSE' or 'READY - VERIFY HOME') or ctx.phase=='MINING' and 'MINING' or ctx.phase=='RETURNING' and 'RETURNING HOME' or ctx.phase=='RESUMING' and 'RETURNING TO WORK' or ctx.phase=='SERVICE' and 'HOME: UNLOAD / SUPPLY' or ctx.phase=='DONE' and 'DONE - HOME AND UNLOADED' or ctx.phase=='STOPPED' and 'STOPPED' or 'NEEDS HELP'
    local lines={'JOB: '..tostring(ctx.config.job or '(required)'), 'STEP: '..tostring(ctx.pointer or 1)..' / '..tostring(ctx.strategy and #ctx.strategy or '?')}
    local p=ctx.pose or ctx.config.home
    if p then lines[#lines+1]='POSE: '..tostring(p.x)..', '..tostring(p.y)..', '..tostring(p.z)..' '..tostring(p.facing) end
    lines[#lines+1]='WORLD: '..tostring(ctx.config.dimension or '(required)')
    local b=ctx.config.bounds
    if b and b.min and b.max then
        lines[#lines+1]='BOUNDS MIN: '..tostring(b.min.x)..', '..tostring(b.min.y)..', '..tostring(b.min.z)
        lines[#lines+1]='BOUNDS MAX: '..tostring(b.max.x)..', '..tostring(b.max.y)..', '..tostring(b.max.z)
    end
    lines[#lines+1]='OUTPUT: '..tostring(ctx.config.outputSide or 'down')..'  SUPPLY: '..tostring(ctx.config.supplySide or 'up')
    if turtle and turtle.getFuelLevel then lines[#lines+1]='FUEL: '..tostring(turtle.getFuelLevel()) end
    if ctx.lastError then lines[#lines+1]='REASON: '..ctx.lastError end
    if ready then lines[#lines+1]=ctx.config.resume and 'Verify saved pose, heading and world.' or 'Verify home, heading and world.' end
    local wrapped={}
    for _,line in ipairs(lines) do
        line=line:gsub('[\r\n]+',' ')
        while #line>w do
            local cut=line:sub(1,w):match('^.*() ')
            if cut and cut>1 then
                wrapped[#wrapped+1]=line:sub(1,cut-1); line=line:sub(cut+1)
            else
                wrapped[#wrapped+1]=line:sub(1,w); line=line:sub(w+1)
            end
        end
        if #line>0 then wrapped[#wrapped+1]=line end
    end
    local capacity=math.max(1,h-4); local pages=math.max(1,math.ceil(#wrapped/capacity))
    ctx.statusPage=math.min(math.max(1,ctx.statusPage or 1),pages); ctx.statusPages=pages
    term.setCursorPos(1,1); term.write(title:sub(1,w))
    for row=1,capacity do
        local line=wrapped[(ctx.statusPage-1)*capacity+row]
        if line then term.setCursorPos(1,row+1); term.write(line) end
    end
    term.setCursorPos(1,math.max(1,h-2)); term.write(('PAGE '..ctx.statusPage..'/'..pages..((ctx.phase=='DONE' or ctx.phase=='STOPPED') and not ready and '' or '  LEFT/RIGHT: DETAILS')):sub(1,w))
    local controls=ready and 'ENTER: START   Q: STOP' or ctx.phase=='NEEDS_HELP' and 'Q: EXIT   LEFT/RIGHT: DETAILS' or (ctx.phase=='DONE' or ctx.phase=='STOPPED') and 'Returned to shell.' or 'Q: STOP   R: RETURN HOME'
    term.setCursorPos(1,math.max(1,h-1)); term.write(controls:sub(1,w))
    term.setCursorPos(1,h); term.write((ctx.phase=='NEEDS_HELP' and 'Reconcile before explicit resume.' or ctx.phase=='DONE' and 'Job complete; no automatic restart.' or ctx.phase=='STOPPED' and 'Saved. Explicit --resume to continue.' or ready and 'No action before ENTER confirmation.' or 'Keyboard: stop, return, view details.'):sub(1,w))
end
function M.key(ctx,key)
    if not keys then return false end
    if key==keys.right or key==keys.pageDown then ctx.statusPage=(ctx.statusPage or 1)+1; return true end
    if key==keys.left or key==keys.pageUp then ctx.statusPage=math.max(1,(ctx.statusPage or 1)-1); return true end
    return false
end
return M
