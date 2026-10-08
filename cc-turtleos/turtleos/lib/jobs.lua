-- turtleos/lib/jobs.lua
-- Finds jobs (turtleos/strategies/<role>/<job>.lua), remembers their
-- options, and runs them with a status screen.
--
-- A job module returns:
--   {
--     title = "Crop farm",
--     summary = "One line for the job list",
--     description = "A paragraph for the job screen",
--     setup = { "Setup step", ... },          -- shown under "How to set up"
--     options = { { key=, label=, type="number"|"bool"|"choice",
--                   default=, min=, max=, step=, choices={...} }, ... },
--     estimateFuel = function(opts) return n end,   -- optional
--     run = function(opts, ctx) ... end,
--   }
-- Older strategies that only have execute(schema) still run, in a loop.

local ui = require("turtleos.lib.ui")
local nav = require("turtleos.lib.nav")

local jobs = {}

local DATA = "/.turtleos"
local base -- the installed turtleos/ folder

function jobs.setBase(dir)
    base = dir
end

local function readTable(path)
    if not fs.exists(path) then return nil end
    local h = fs.open(path, "r")
    if not h then return nil end
    local data = textutils.unserialize(h.readAll())
    h.close()
    return type(data) == "table" and data or nil
end

local function writeTable(path, data)
    if not fs.exists(fs.getDir(path)) then fs.makeDir(fs.getDir(path)) end
    local h = fs.open(path, "w")
    h.write(textutils.serialize(data))
    h.close()
end

local function title(name)
    return (name:gsub("_", " "):gsub("^%l", string.upper))
end

function jobs.roles()
    local dir = fs.combine(base, "strategies")
    local roles = {}
    for _, name in ipairs(fs.list(dir)) do
        if fs.isDir(fs.combine(dir, name)) then
            roles[#roles + 1] = { id = name, title = title(name), jobs = jobs.list(name) }
        end
    end
    table.sort(roles, function(a, b) return a.id < b.id end)
    return roles
end

function jobs.list(role)
    local dir = fs.combine(base, "strategies/" .. role)
    local out = {}
    for _, file in ipairs(fs.list(dir)) do
        if file:sub(-4) == ".lua" then
            local job = jobs.load(role, file:sub(1, -5))
            if job then out[#out + 1] = job end
        end
    end
    table.sort(out, function(a, b) return a.title < b.title end)
    return out
end

-- Loads a job module and fills in defaults. Returns nil if it won't load.
function jobs.load(role, id)
    local name = "turtleos.strategies." .. role .. "." .. id
    package.loaded[name] = nil
    local ok, mod = pcall(require, name)
    if not ok or type(mod) ~= "table" then
        return { role = role, id = id, title = title(id), summary = "(won't load)",
                 broken = tostring(mod), options = {} }
    end
    mod.role, mod.id = role, id
    mod.title = mod.title or title(id)
    mod.summary = mod.summary or ""
    mod.options = mod.options or {}
    return mod
end

-- Saved option values, with defaults for anything not saved yet.
function jobs.options(job)
    local saved = readTable(DATA .. "/options/" .. job.role .. "." .. job.id) or {}
    local opts = {}
    for _, o in ipairs(job.options) do
        if saved[o.key] ~= nil then opts[o.key] = saved[o.key] else opts[o.key] = o.default end
    end
    return opts
end

function jobs.saveOptions(job, opts)
    writeTable(DATA .. "/options/" .. job.role .. "." .. job.id, opts)
end

-- Progress a job saved for resuming (e.g. which branch the miner is on).
function jobs.progress(job)
    return readTable(DATA .. "/progress/" .. job.role .. "." .. job.id)
end

function jobs.autorun()
    return readTable(DATA .. "/autorun")
end

function jobs.setAutorun(job)
    if job then
        writeTable(DATA .. "/autorun", { role = job.role, id = job.id })
    elseif fs.exists(DATA .. "/autorun") then
        fs.delete(DATA .. "/autorun")
    end
end

-- Run a job with a live status screen. `resume` continues from the saved
-- position and progress; otherwise the turtle is taken to be at its start
-- spot. Returns when the job ends or the player stops it.
function jobs.run(job, opts, resume)
    local w, h = ui.size()
    local key = job.role .. "." .. job.id
    local progressFile = DATA .. "/progress/" .. key
    local state = { status = "Starting", stats = {}, statOrder = {}, log = {}, stop = 0 }

    local function draw()
        ui.clear()
        ui.bar(1, job.title, ui.fuelText())
        ui.write(2, 3, ui.fit(state.status, w - 2), ui.theme.accent)
        local y = 5
        for i = 1, #state.statOrder, 2 do
            local a, b = state.statOrder[i], state.statOrder[i + 1]
            ui.write(2, y, ui.fit(a .. " " .. state.stats[a], 18))
            if b then ui.write(21, y, ui.fit(b .. " " .. state.stats[b], w - 21)) end
            y = y + 1
        end
        local logTop = math.max(y + 1, h - 4)
        for i = 1, h - 1 - logTop do
            local line = state.log[#state.log - (h - 1 - logTop) + i]
            if line then ui.write(2, logTop + i - 1, ui.fit(line, w - 2), ui.theme.dim) end
        end
        if state.stop == 0 then
            ui.bar(h, "Q: stop and go home")
        else
            ui.bar(h, "Stopping... Q again: stop here")
        end
    end

    local ctx = { opts = opts, resume = resume }

    function ctx.status(text)
        state.status = text
        draw()
    end

    -- Count something on the status screen, e.g. ctx.count("Harvested").
    function ctx.count(name, n)
        if state.stats[name] == nil then
            state.stats[name] = 0
            state.statOrder[#state.statOrder + 1] = name
        end
        state.stats[name] = state.stats[name] + (n or 1)
    end

    function ctx.log(text)
        state.log[#state.log + 1] = text
        if #state.log > 20 then table.remove(state.log, 1) end
        draw()
    end

    -- True once the player has asked the job to stop. Jobs check this at
    -- safe points, then head home and return.
    function ctx.stopping()
        return state.stop > 0
    end

    function ctx.progress()
        return readTable(progressFile)
    end

    function ctx.saveProgress(data)
        writeTable(progressFile, data)
    end

    function ctx.clearProgress()
        if fs.exists(progressFile) then fs.delete(progressFile) end
    end

    -- Wait, showing a countdown; ends early if the player asks to stop.
    function ctx.wait(seconds, label)
        local deadline = os.clock() + seconds
        while os.clock() < deadline and not ctx.stopping() do
            local left = math.ceil(deadline - os.clock())
            ctx.status(string.format("%s %d:%02d", label or "Waiting", math.floor(left / 60), left % 60))
            sleep(math.min(1, deadline - os.clock()))
        end
    end

    local result
    local function work()
        if resume then
            if not nav.load() then nav.reset() end
        else
            nav.reset()
        end
        draw()
        if job.run then
            local ok, err = pcall(job.run, opts, ctx)
            result = ok and (err or "Done") or ("Error: " .. tostring(err))
        elseif job.execute then
            local ok, err = pcall(function()
                while not ctx.stopping() do
                    job.execute({ role = job.role, strategy = job.id })
                    sleep(1)
                end
            end)
            result = ok and "Stopped" or ("Error: " .. tostring(err))
        else
            result = "Error: " .. (job.broken or "job has no run function")
        end
    end

    local function listen()
        while true do
            local _, k = os.pullEvent("key")
            if k == keys.q then
                state.stop = state.stop + 1
                if state.stop >= 2 then
                    result = "Stopped where it stood"
                    return
                end
                draw()
            end
        end
    end

    parallel.waitForAny(work, listen)
    return result
end

return jobs
