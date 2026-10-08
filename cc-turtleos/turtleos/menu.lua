-- Resolve paths from wherever turtleos/ is installed ("/turtleos" or e.g. "/pkg/turtleos").
local base = fs.getDir(shell.getRunningProgram())
local pkgRoot = fs.getDir(base)
local rootPath = "/" .. fs.combine(pkgRoot, "?.lua")
if not (";" .. package.path .. ";"):find(";" .. rootPath .. ";", 1, true) then
    package.path = rootPath .. ";/" .. fs.combine(pkgRoot, "?/init.lua") .. ";" .. package.path
end

local ui = require("turtleos.lib.ui")
local jobs = require("turtleos.lib.jobs")
local inv = require("turtleos.lib.inv")

jobs.setBase(base)

local T = ui.theme

-- Generic list screen. `build()` returns title, items, and optionally a
-- right-hand header. Each item may have: label, right, info (shown under
-- the list when selected), action(), left(), rightKey(), separator.
-- Returns when an action returns "back" (or Backspace/Q is pressed at a
-- screen that allows it).
local function screen(build, canBack)
    local selected = 1
    while true do
        local title, items, headerRight = build()
        if selected > #items then selected = #items end
        while items[selected] and items[selected].separator do selected = selected + 1 end
        local w, h = ui.size()
        ui.clear()
        ui.bar(1, title, headerRight or ui.fuelText())
        local rows = ui.list(items, selected, 2, h - 2)
        local cur = items[selected]
        ui.write(2, h - 1, ui.fit(cur and cur.info or "", w - 2), T.dim)
        local help = "Enter: choose"
        if cur and cur.left then help = "<>: change  Enter: edit" end
        if canBack then help = help .. "  Bksp: back" end
        ui.bar(h, help)

        local function move(d)
            repeat
                selected = (selected - 1 + d) % #items + 1
            until not items[selected].separator
        end

        local ev, a, _, y = os.pullEvent()
        local activate = false
        if ev == "key" then
            if a == keys.up then move(-1)
            elseif a == keys.down then move(1)
            elseif a == keys.enter or a == keys.space then activate = true
            elseif a == keys.left and cur and cur.left then cur.left()
            elseif a == keys.right and cur and cur.rightKey then cur.rightKey()
            elseif (a == keys.backspace or a == keys.q) and canBack then return
            end
        elseif ev == "mouse_click" and rows[y] then
            selected = rows[y]
            activate = true
        elseif ev == "mouse_scroll" then
            move(a)
        end
        if activate and items[selected].action then
            if items[selected].action() == "back" then return end
        end
    end
end

local function message(title, text)
    ui.page(title, type(text) == "table" and text or { text })
end

-- Display text for an option's current value.
local function showValue(o, v)
    if o.type == "bool" then return v and "[on]" or "[off]" end
    if o.type == "number" and o.key == "torches" and v == 0 then return "< off >" end
    return "< " .. tostring(v) .. " >"
end

local function optionItem(job, opts, o)
    local function set(v)
        opts[o.key] = v
        jobs.saveOptions(job, opts)
    end
    local function nudge(d)
        if o.type == "bool" then
            set(not opts[o.key])
        elseif o.type == "choice" then
            local i = 1
            for n, c in ipairs(o.choices) do if c == opts[o.key] then i = n end end
            set(o.choices[(i - 1 + d) % #o.choices + 1])
        else
            local v = (opts[o.key] or 0) + d * (o.step or 1)
            if o.min then v = math.max(o.min, v) end
            if o.max then v = math.min(o.max, v) end
            set(v)
        end
    end
    return {
        label = o.label,
        right = showValue(o, opts[o.key]),
        info = o.type == "number" and ("Type a number with Enter (" .. (o.min or 0) .. "-" .. (o.max or "") .. ")")
            or "Enter or <> to change",
        left = function() nudge(-1) end,
        rightKey = function() nudge(1) end,
        action = function()
            if o.type ~= "number" then return nudge(1) end
            local _, h = ui.size()
            local v = tonumber(ui.prompt(h - 1, o.label, opts[o.key]) or "")
            if v then
                v = math.floor(v)
                if o.min then v = math.max(o.min, v) end
                if o.max then v = math.min(o.max, v) end
                set(v)
            end
        end,
    }
end

local function runJob(job, opts, resume)
    local result = jobs.run(job, opts, resume)
    message(job.title, { result or "Done", "", "Fuel left: " .. tostring(turtle.getFuelLevel()) })
end

local function jobScreen(job)
    local opts = jobs.options(job)
    screen(function()
        local items = {}
        local fuelInfo = ""
        if job.estimateFuel then
            local need = job.estimateFuel(opts)
            fuelInfo = "Needs ~" .. need .. " fuel" .. (job.repeats and " a cycle" or "")
                .. ", has " .. tostring(turtle.getFuelLevel())
        end
        if job.broken then
            items[#items + 1] = { label = "This job failed to load", info = job.broken,
                action = function() message(job.title, { job.broken }) end }
        else
            items[#items + 1] = { label = "Start", right = "at start spot", info = fuelInfo,
                action = function() runJob(job, opts, false) end }
            local saved = jobs.progress(job)
            if saved and job.progressText then
                items[#items + 1] = { label = "Resume", right = job.progressText(saved, opts),
                    info = "Carry on from where it stopped",
                    action = function() runJob(job, opts, true) end }
            end
        end
        items[#items + 1] = { label = "How to set up", info = job.summary, action = function()
            local lines = { job.description or job.summary, "" }
            for _, l in ipairs(job.setup or {}) do lines[#lines + 1] = l end
            message(job.title, lines)
        end }
        if #job.options > 0 then items[#items + 1] = { separator = true, label = "Options" } end
        for _, o in ipairs(job.options) do
            items[#items + 1] = optionItem(job, opts, o)
        end
        local auto = jobs.autorun()
        local on = auto and auto.role == job.role and auto.id == job.id
        items[#items + 1] = { separator = true }
        items[#items + 1] = {
            label = "Start on boot", right = on and "[on]" or "[off]",
            info = "Keep working after a reboot or chunk reload",
            action = function() jobs.setAutorun(not on and job or nil) end,
            left = function() jobs.setAutorun(not on and job or nil) end,
            rightKey = function() jobs.setAutorun(not on and job or nil) end,
        }
        items[#items + 1] = { label = "< Back", action = function() return "back" end }
        return job.title, items
    end, true)
end

local function roleScreen(role)
    screen(function()
        local items = {}
        for _, job in ipairs(role.jobs) do
            items[#items + 1] = { label = job.title, info = job.summary, action = function() jobScreen(job) end }
        end
        items[#items + 1] = { label = "< Back", action = function() return "back" end }
        return role.title, items
    end, true)
end

local function refuelAll()
    local before = turtle.getFuelLevel()
    inv.refuel(turtle.getFuelLimit())
    local after = turtle.getFuelLevel()
    if after == before then
        message("Refuel", { "No fuel in the inventory.", "", "Put coal, charcoal or a lava bucket in the turtle and try again." })
    else
        message("Refuel", { "Fuel: " .. before .. " -> " .. after })
    end
end

local function findJob(roles, role, id)
    for _, r in ipairs(roles) do
        if r.id == role then
            for _, j in ipairs(r.jobs) do
                if j.id == id then return j end
            end
        end
    end
end

screen(function()
    local roles = jobs.roles()
    local items = {}
    for _, role in ipairs(roles) do
        local names = {}
        for _, j in ipairs(role.jobs) do names[#names + 1] = j.title end
        items[#items + 1] = {
            label = role.title, right = #role.jobs .. (#role.jobs == 1 and " job" or " jobs"),
            info = table.concat(names, ", "),
            action = function() roleScreen(role) end,
        }
    end
    items[#items + 1] = { separator = true }
    local auto = jobs.autorun()
    local autoJob = auto and findJob(roles, auto.role, auto.id)
    if autoJob then
        items[#items + 1] = { label = "On boot: " .. autoJob.title, info = "Open it to change or turn off",
            action = function() jobScreen(autoJob) end }
    end
    items[#items + 1] = { label = "Refuel", info = "Burn the fuel in my inventory", action = refuelAll }
    items[#items + 1] = { label = "Exit to shell", info = "Type 'startup' to come back", action = function() return "back" end }
    items[#items + 1] = { label = "Reboot", action = os.reboot }
    local label = os.getComputerLabel()
    return "TurtleOS" .. (label and (" - " .. label) or ""), items
end, false)

ui.clear()
