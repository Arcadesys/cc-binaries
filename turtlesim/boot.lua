-- turtlesim boot: runs inside CraftOS-PC (launched by turtlesim/turtle).
-- Installs a simulated turtle/peripheral/gps, runs the requested script,
-- then prints a report. All output is mirrored to /results/output.txt.

local RESULTS = "/results"
local SIM_DIR = "/.turtlesim"

local function readFile(path)
    local h = fs.open(path, "r")
    if not h then
        return nil
    end
    local text = h.readAll()
    h.close()
    return text
end

local cfg = textutils.unserializeJSON(readFile(RESULTS .. "/config.json") or "{}") or {}
local sim = dofile(SIM_DIR .. "/sim.lua")

-- Output capture --------------------------------------------------------------

local logHandle = fs.open(RESULTS .. "/output.txt", "w")
local pending = ""

local sinceRead = ""  -- output since the last read(), for world prompt hooks

local lastActivity
local function logText(text)
    lastActivity = os.clock()
    sinceRead = (sinceRead .. text):sub(-2000)
    pending = pending .. text
    while true do
        local nl = pending:find("\n", 1, true)
        if not nl then
            break
        end
        logHandle.write(pending:sub(1, nl))
        pending = pending:sub(nl + 1)
    end
    logHandle.flush()
end

local function flushLog()
    if pending ~= "" then
        logHandle.write(pending .. "\n")
        pending = ""
    end
    logHandle.flush()
end

local nativeWrite = _G.write
_G.write = function(text)
    logText(tostring(text))
    return nativeWrite(text)
end

local function say(line)
    print(line)
end

-- World -----------------------------------------------------------------------

local worldOpts = {}
if cfg.world then
    local chunk, err = loadfile(RESULTS .. "/world.lua", nil, _ENV)
    if not chunk then
        error("turtlesim: bad world file: " .. tostring(err), 0)
    end
    worldOpts = chunk()
    if type(worldOpts) == "function" then
        worldOpts = worldOpts(sim)
    end
end
worldOpts.turtle = worldOpts.turtle or {}
if cfg.fuel then
    if cfg.fuel == "unlimited" then
        worldOpts.unlimitedFuel = true
    else
        worldOpts.turtle.fuel = tonumber(cfg.fuel)
    end
end
if cfg.facing then
    worldOpts.turtle.facing = cfg.facing
end
if cfg.maxActions then
    worldOpts.maxActions = cfg.maxActions
end

if cfg.seed then
    worldOpts.seed = tonumber(cfg.seed)
end
if cfg.offsetX and cfg.offsetX ~= 0 then
    -- Fleet runs: shift this turtle (and its placed blocks) sideways.
    worldOpts.turtle.x = (worldOpts.turtle.x or 0) + cfg.offsetX
    for _, b in ipairs(worldOpts.blocks or {}) do
        b[1] = b[1] + cfg.offsetX
    end
end

local world = sim.newWorld(worldOpts)
for _, spec in ipairs(cfg.give or {}) do
    world:give(spec)
end
if cfg.trace then
    world.trace = function(msg)
        say("  [turtle] " .. msg)
    end
end

_G.turtle = world:makeTurtle()
_G.peripheral = world:makePeripheral(peripheral)
_G.gps = world:makeGps()

-- Time and input --------------------------------------------------------------

if not cfg.interactive then
    -- Headless: there is no keyboard, so answer prompts from --answer values,
    -- then with Enter. Give up if the script keeps asking.
    local answers = cfg.answers or {}
    local asked = 0
    _G.read = function()
        asked = asked + 1
        if asked > (cfg.maxPrompts or 50) then
            world.abort("script kept waiting for input (" .. (asked - 1) .. " prompts answered). Pass --answer values or run with --ui.")
        end
        -- World files can act out the prompt, e.g. "Place a chest in front"
        -- -> prompts = { { "Place a chest", function(world) ... end } }.
        for _, hook in ipairs(worldOpts.prompts or {}) do
            if sinceRead:find(hook[1], 1, true) then
                say("  [world] " .. hook[1])
                hook[2](world)
            end
        end
        sinceRead = ""
        local answer = table.remove(answers, 1) or ""
        logText("> " .. answer .. "\n")
        nativeWrite("> " .. answer .. "\n")
        return answer
    end
end

local nativeStartTimer = os.startTimer
lastActivity = os.clock()
world.onAction = function()
    lastActivity = os.clock()
end

if not cfg.realTime then
    -- Fast-forward sleeps and timers: yield once so events still flow, but
    -- don't wait. Timer ids start high so they never match real timers.
    -- Unlike a real sleep, no time passes, so events that arrive meanwhile
    -- (like a fast timer queued just before) must be put back, not dropped.
    local function fastSleep()
        os.queueEvent("turtlesim_tick")
        local held = {}
        while true do
            local event = table.pack(os.pullEventRaw())
            if event[1] == "turtlesim_tick" then
                break
            elseif event[1] == "terminate" then
                error("Terminated", 0)
            end
            held[#held + 1] = event
        end
        for _, event in ipairs(held) do
            os.queueEvent(table.unpack(event, 1, event.n))
        end
    end
    _G.sleep = fastSleep
    os.sleep = fastSleep
    local nextTimer = 1000000
    os.startTimer = function()
        nextTimer = nextTimer + 1
        os.queueEvent("timer", nextTimer)
        return nextTimer
    end
    local nativeCancel = os.cancelTimer
    os.cancelTimer = function(id)
        if id < 1000000 then
            nativeCancel(id)
        end
    end
end

-- Finish ----------------------------------------------------------------------

local function writeJSON(name, value)
    local h = fs.open(RESULTS .. "/" .. name, "w")
    h.write(textutils.serializeJSON(value))
    h.close()
end

-- The script draws into a window so its last screen can be printed with the
-- report (full-screen UIs bypass print, so the log alone misses them).
local nativeTerm = term.current()
local w, h = nativeTerm.getSize()
local screen = window.create(nativeTerm, 1, 1, w, h, true)

local function screenLines()
    local lines = {}
    for y = 1, h do
        lines[y] = (screen.getLine(y)):gsub("%s+$", "")
    end
    while #lines > 0 and lines[#lines] == "" do
        lines[#lines] = nil
    end
    return lines
end

local function finish(status)
    term.redirect(nativeTerm)
    if cfg.showScreen ~= false then
        local lines = screenLines()
        if #lines > 0 then
            logText("\n== last screen ==\n")
            for _, line in ipairs(lines) do
                logText("  |" .. line .. "\n")
            end
        end
    end
    print("")
    for _, line in ipairs(world:report()) do
        say(line)
    end
    flushLog()
    writeJSON("status.json", status)

    local mined, missed = world:oreSummary()
    local summary = {
        ok = status.ok,
        fuelUsed = world.stats.fuelUsed,
        moves = world.stats.moves,
        dug = world.stats.dug,
        actions = world.stats.actions,
        mined = mined,
        missed = missed,
        failures = world.failures,
        finalPos = { world.turtle.x, world.turtle.y, world.turtle.z },
        visited = {},
    }
    -- Cells the turtle passed through, so fleet runs can check for overlap.
    for k in pairs(world.visited) do
        summary.visited[#summary.visited + 1] = k
    end
    writeJSON("summary.json", summary)

    local lh = fs.open(RESULTS .. "/actions.txt", "w")
    lh.write(table.concat(world.log, "\n") .. "\n")
    lh.close()

    if cfg.interactive then
        print("")
        print("Press any key to close turtlesim.")
        os.pullEvent("key")
    end
    logHandle.close()
    os.shutdown()
    while true do
        coroutine.yield()
    end
end

-- Stop the run from anywhere. Scripts often pcall their main loop, so an
-- error() would just be caught and retried; this ends the emulator instead.
local function abort(reason)
    term.redirect(nativeTerm)
    printError("turtlesim: " .. reason)
    finish({ ok = false, error = reason })
end
world.abort = abort

-- Run -------------------------------------------------------------------------

local script = cfg.script
local args = cfg.args or {}
say(string.format("turtlesim: %s %s", script, table.concat(args, " ")))
say(string.format("turtlesim: start %s fuel %s", world:pos(), tostring(turtle.getFuelLevel())))

-- Headless helper running beside the script: presses --key values (one per
-- second, for programs that wait on key events rather than read()), and
-- stops the run if nothing happens for --idle seconds.
local function keyboard()
    local pending = {}
    for _, name in ipairs(cfg.keys or {}) do
        pending[#pending + 1] = name
    end
    local idle = tonumber(cfg.idle) or 10
    while true do
        local id = nativeStartTimer(1)
        repeat
            local _, fired = os.pullEvent("timer")
        until fired == id
        local name = table.remove(pending, 1)
        if name then
            local code = keys[name]
            if not code then
                world.abort("unknown key name for --key: " .. name)
            end
            say("> [key " .. name .. "]")
            os.queueEvent("key", code, false)
            os.queueEvent("key_up", code)
            lastActivity = os.clock()
        elseif os.clock() - lastActivity > idle then
            world.abort(string.format("nothing happened for %ds; the script is probably waiting for a key. Pass --key NAME or run with --ui.", idle))
        end
    end
end

shell.setDir(fs.getDir(script))
term.redirect(screen)
local ok, err
local function runScript()
    ok, err = pcall(shell.execute, script, table.unpack(args))
end
if cfg.interactive then
    runScript()
else
    parallel.waitForAny(runScript, keyboard)
end
local status = { ok = ok and err ~= false, error = (not ok) and tostring(err) or nil }
if not ok then
    printError(tostring(err))
elseif err == false then
    status.error = "script exited with an error (see output above)"
end
finish(status)
