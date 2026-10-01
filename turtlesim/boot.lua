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

local function logText(text)
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

if not cfg.realTime then
    -- Fast-forward sleeps: yield once so events still flow, but don't wait.
    local fake = 0
    local function fastSleep(seconds)
        fake = fake + (tonumber(seconds) or 0)
        os.queueEvent("turtlesim_tick")
        os.pullEvent("turtlesim_tick")
    end
    _G.sleep = fastSleep
    os.sleep = fastSleep
end

-- Finish ----------------------------------------------------------------------

local function writeJSON(name, value)
    local h = fs.open(RESULTS .. "/" .. name, "w")
    h.write(textutils.serializeJSON(value))
    h.close()
end

local function finish(status)
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
    printError("turtlesim: " .. reason)
    finish({ ok = false, error = reason })
end
world.abort = abort

-- Run -------------------------------------------------------------------------

local script = cfg.script
local args = cfg.args or {}
say(string.format("turtlesim: %s %s", script, table.concat(args, " ")))
say(string.format("turtlesim: start %s fuel %s", world:pos(), tostring(turtle.getFuelLevel())))

shell.setDir(fs.getDir(script))
local ok, err = pcall(shell.execute, script, table.unpack(args))
local status = { ok = ok and err ~= false, error = (not ok) and tostring(err) or nil }
if not ok then
    printError(tostring(err))
elseif err == false then
    status.error = "script exited with an error (see output above)"
end
finish(status)
