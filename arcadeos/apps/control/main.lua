-- Control Panel: desktop color, screen saver, arcade free play, clock format.
local ui = arcadeos.lib("ui")
local R = ui.roles()
local theme = arcadeos.theme()

local function screensaverChoices()
    local list = { { label = "None", value = "none" }, { label = "Random", value = "random" } }
    for _, name in ipairs(arcadeos.screensavers and arcadeos.screensavers() or {}) do
        list[#list + 1] = { label = name, value = name }
    end
    return list
end

local function choices(list, current)
    for i, c in ipairs(list) do if c.value == current then return i end end
    return 1
end

local desktopList = {}
for _, d in ipairs(theme.desktops) do desktopList[#desktopList + 1] = { label = d.name, value = d.color } end

local ROWS = {
    { label = "Desktop", key = "desktop", list = desktopList, default = colors.cyan },
    { label = "Saver", key = "screensaver", list = screensaverChoices(), default = "random" },
    { label = "Wait", key = "screensaver.delay", default = 5, list = {
        { label = "1 min", value = 1 }, { label = "2 min", value = 2 }, { label = "5 min", value = 5 },
        { label = "10 min", value = 10 }, { label = "30 min", value = 30 } } },
    { label = "Arcade", key = "freeplay", default = true, list = {
        { label = "Free play", value = true }, { label = "Credits", value = false } } },
    { label = "Clock", key = "clock.24h", default = false, list = {
        { label = "12 hour", value = false }, { label = "24 hour", value = true } } },
}

local sel = 1
local hits = {}

local function draw()
    local w, h = term.getSize()
    term.setCursorBlink(false)
    ui.fill(1, 1, w, h, R.window)
    hits = {}
    local labelW = 9
    local valueW = math.max(4, math.min(16, w - labelW - 3))
    for i, row in ipairs(ROWS) do
        local y = i * 2 - (h < 12 and i - 1 or 0)
        local idx = choices(row.list, arcadeos.getSetting(row.key, row.default))
        local hi = i == sel
        ui.text(2, y, ui.pad(row.label, labelW - 1), hi and R.titleActive or R.text, R.window)
        local vx = labelW + 1
        ui.text(vx, y, "\17", R.text, R.scroll)
        ui.text(vx + 1, y, ui.pad(" " .. row.list[idx].label, valueW), hi and R.selectText or R.text, hi and R.select or R.window)
        ui.text(vx + 1 + valueW, y, "\16", R.text, R.scroll)
        hits[#hits + 1] = { row = i, dir = -1, x = vx, y = y, w = 1 }
        hits[#hits + 1] = { row = i, dir = 1, x = vx + 1, y = y, w = valueW + 1 }
    end
    if arcadeos.previewScreensaver then
        local by = math.min(h, #ROWS * 2 + 2)
        local r = ui.button(math.max(1, math.floor((w - 13) / 2) + 1), by, "Test Saver", false)
        r.test = true
        hits[#hits + 1] = r
    end
end

local function change(i, dir)
    local row = ROWS[i]
    local idx = choices(row.list, arcadeos.getSetting(row.key, row.default))
    idx = (idx - 1 + dir) % #row.list + 1
    arcadeos.setSetting(row.key, row.list[idx].value)
end

while true do
    draw()
    local ev = { os.pullEvent() }
    if ev[1] == "key" then
        if ev[2] == keys.up then sel = (sel - 2) % #ROWS + 1
        elseif ev[2] == keys.down or ev[2] == keys.tab then sel = sel % #ROWS + 1
        elseif ev[2] == keys.left then change(sel, -1)
        elseif ev[2] == keys.right or ev[2] == keys.enter or ev[2] == keys.space then change(sel, 1)
        end
    elseif ev[1] == "mouse_click" then
        for _, hit in ipairs(hits) do
            if ui.inRect(hit, ev[3], ev[4]) then
                if hit.test then arcadeos.previewScreensaver()
                else sel = hit.row; change(hit.row, hit.dir) end
            end
        end
    end
end
