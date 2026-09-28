-- Clock: analog face when there's room, digital otherwise. Iconized, it shows the time.
local ui = arcadeos.lib("ui")
local canvas = arcadeos.lib("canvas")
local R = ui.roles()

local source = arcadeos.getSetting("clock.source", "game")
local h24 = arcadeos.getSetting("clock.24h", false)

local function setMenus()
    arcadeos.setMenus({
        { label = "Settings", items = {
            { id = "game", label = "Game Time", checked = source == "game" },
            { id = "real", label = "Real Time", checked = source == "real" },
            "-",
            { id = "24h", label = "24 Hour", checked = h24 },
        } },
    })
end

local function now()
    if source == "real" then
        local ms = os.epoch("local") % 86400000
        return ms / 3600000, math.floor(ms / 1000) % 60
    end
    return os.time("ingame"), nil
end

local function fmt(hours)
    return textutils.formatTime(hours, h24):gsub("^%s+", "")
end

local function draw()
    local w, h = term.getSize()
    local hours, secs = now()
    local label = fmt(hours)
    arcadeos.setIcon(label:gsub(" ", ""):sub(1, 7))
    ui.fill(1, 1, w, h, R.window)
    if w >= 12 and h >= 6 then
        local c = canvas.new(w, h - 1)
        local cx, cy = (c.pw + 1) / 2, (c.ph + 1) / 2
        local r = math.min(c.pw, c.ph) / 2 - 1
        c:circle(cx, cy, r, colors.black)
        for i = 0, 11 do
            local a = i * math.pi / 6
            local len = (i % 3 == 0) and 0.8 or 0.88
            c:line(cx + r * len * math.sin(a), cy - r * len * math.cos(a),
                cx + r * 0.95 * math.sin(a), cy - r * 0.95 * math.cos(a), colors.blue)
        end
        local hh, mm = hours % 12, (hours * 60) % 60
        local ha = (hh + mm / 60) * math.pi / 6
        local ma = mm * math.pi / 30
        c:line(cx, cy, cx + r * 0.5 * math.sin(ha), cy - r * 0.5 * math.cos(ha), colors.black)
        c:line(cx, cy, cx + r * 0.78 * math.sin(ma), cy - r * 0.78 * math.cos(ma), colors.black)
        if secs then
            local sa = secs * math.pi / 30
            c:line(cx, cy, cx + r * 0.85 * math.sin(sa), cy - r * 0.85 * math.cos(sa), colors.red)
        end
        c:draw(1, 1, R.window)
        ui.center(h, label, R.text, R.window)
    else
        ui.center(math.max(1, math.ceil(h / 2)), label, R.text, R.window)
    end
end

setMenus()
local timer = os.startTimer(0)
while true do
    local ev, a = os.pullEvent()
    if ev == "timer" and a == timer then
        draw()
        timer = os.startTimer(1)
    elseif ev == "arcadeos_menu" then
        if a == "game" or a == "real" then source = a; arcadeos.setSetting("clock.source", a)
        elseif a == "24h" then h24 = not h24; arcadeos.setSetting("clock.24h", h24) end
        setMenus()
        draw()
    elseif ev == "term_resize" then
        draw()
    end
end
