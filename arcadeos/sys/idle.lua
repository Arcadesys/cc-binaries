-- Screen saver: after the configured idle time, run a cc-screensaver plugin fullscreen.
-- Any key press or click ends it (and is swallowed).
local idle = {}

idle.DIR = "/pkg/screensavers"
idle.CHECK_SECONDS = 10
idle.ROTATE_SECONDS = 60
idle.WAKE = { key = true, char = true, paste = true, mouse_click = true, mouse_scroll = true }

function idle.list(dir)
    dir = dir or idle.DIR
    local names = {}
    if fs.isDir(dir) then
        for _, f in ipairs(fs.list(dir)) do
            local name = f:match("^(.+)%.lua$")
            if name then names[#names + 1] = name end
        end
    end
    table.sort(names)
    return names
end

local function pick(k, name)
    local list = idle.list(k.saverDir)
    if #list == 0 then return nil end
    local want = name or settings.get("arcadeos.screensaver", "random")
    for _, n in ipairs(list) do
        if n == want then return n, false end
    end
    return list[math.random(#list)], true
end

function idle.start(k, name)
    if k.saver then return true end
    local choice, random = pick(k, name)
    if not choice then return false end
    k.menu = nil
    k.saverPrevFocus = k.focus
    local p = k:spawn({
        raw = true, env = {}, path = fs.combine(k.saverDir, choice .. ".lua"),
        title = "Screen Saver", icon = "SAVE", display = "full",
    })
    p.saver = true
    k.saver = p
    if random then
        local function rotate()
            if k.saver == p and not p.dead then
                idle.stop(k, true)
                idle.start(k)
            end
        end
        k:after(idle.ROTATE_SECONDS, rotate)
    end
    return true
end

function idle.stop(k, keepPrev)
    local p = k.saver
    if not p then return end
    k.saver = nil
    k:kill(p)
    k:reap()
    local prev = k.saverPrevFocus
    if not keepPrev then k.saverPrevFocus = nil end
    if prev and not prev.dead then k:focusProc(prev) end
end

function idle.attach(k)
    k.saverDir = k.saverDir or idle.DIR
    local function check()
        if k.exiting then return end
        k:after(idle.CHECK_SECONDS, check)
        if k.saver or k.modals[1] then return end
        if settings.get("arcadeos.screensaver", "random") == "none" then return end
        local delay = settings.get("arcadeos.screensaver.delay", 5) * 60000
        if os.epoch("utc") - k.lastInput >= delay then idle.start(k) end
    end
    k:after(idle.CHECK_SECONDS, check)
end

return idle
