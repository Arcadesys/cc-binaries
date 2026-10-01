--[[
Factory entry point for the modular agent system.
Exposes a `run(args)` helper so it can be required/bundled while remaining
runnable as a stand-alone turtle program.
]]

local logger = require("lib_logger")
local diagnostics = require("lib_diagnostics")
local debug = debug

local states = {
    INITIALIZE = require("state_initialize"),
    CHECK_REQUIREMENTS = require("state_check_requirements"),
    BUILD = require("state_build"),
    MINE = require("state_mine"),
    TREEFARM = require("state_treefarm"),
    RESTOCK = require("state_restock"),
    REFUEL = require("state_refuel"),
    BLOCKED = require("state_blocked"),
    ERROR = require("state_error"),
    DONE = require("state_done"),
}

local function mergeTables(base, extra)
    if type(base) ~= "table" then
        base = {}
    end
    if type(extra) == "table" then
        for key, value in pairs(extra) do
            base[key] = value
        end
    end
    return base
end

local function buildPayload(ctx, extra)
    local payload = { context = diagnostics.snapshot(ctx) }
    if extra then
        mergeTables(payload, extra)
    end
    return payload
end

local function run(args)
    local ctx = {
        state = "INITIALIZE",
        config = {
            verbose = false,
            schemaPath = nil,
        },
        origin = { x = 0, y = 0, z = 0, facing = "north" },
        pointer = 1,
        schema = nil,
        strategy = nil,
        inventoryState = {},
        fuelState = {},
        retries = 0,
    }

    local index = 1
    while index <= #args do
        local value = args[index]
        if value == "--resume" then
            ctx.config.resume = true
        elseif value == "--job" or value == "--dimension" or value == "--heading" or value == "--output-side" or value == "--supply-side" or value == "--checkpoint" then
            index = index + 1
            local fields = { ["--job"]="job", ["--dimension"]="dimension", ["--heading"]="heading", ["--output-side"]="outputSide", ["--supply-side"]="supplySide", ["--checkpoint"]="checkpointPath" }
            ctx.config[fields[value]] = args[index]
        elseif value == "--home" or value == "--bounds-min" or value == "--bounds-max" then
            local point = {x=tonumber(args[index+1]), y=tonumber(args[index+2]), z=tonumber(args[index+3])}
            if value == "--home" then ctx.config.home = point
            else
                ctx.config.bounds = ctx.config.bounds or {}
                ctx.config.bounds[value == "--bounds-min" and "min" or "max"] = point
            end
            index = index + 3
        elseif value == "--fuel-margin" or value == "--torch-reserve" or value == "--fill-reserve" then
            local fields = { ["--fuel-margin"]="fuelMargin", ["--torch-reserve"]="torchReserve", ["--fill-reserve"]="fillReserve" }
            index = index + 1; ctx.config[fields[value]] = tonumber(args[index]) or -1
        elseif value == "--fuel-item" or value == "--torch-item" or value == "--fill-item" then
            local fields = { ["--fuel-item"]="fuelItem", ["--torch-item"]="torchItem", ["--fill-item"]="fillItem" }
            index = index + 1; ctx.config[fields[value]] = args[index]
        elseif value == "--verbose" then
            ctx.config.verbose = true
        elseif value == "mine" then
            ctx.config.mode = "mine"
        elseif value == "tunnel" then
            ctx.config.mode = "tunnel"
        elseif value == "excavate" then
            ctx.config.mode = "excavate"
        elseif value == "treefarm" then
            ctx.state = "TREEFARM"
        elseif value == "farm" then
            ctx.config.mode = "farm"
        elseif value == "--farm-type" then
            index = index + 1
            ctx.config.farmType = args[index]
        elseif value == "--width" then
            index = index + 1
            ctx.config.width = tonumber(args[index])
        elseif value == "--height" then
            index = index + 1
            ctx.config.height = tonumber(args[index])
        elseif value == "--depth" then
            index = index + 1
            ctx.config.depth = tonumber(args[index])
        elseif value == "--length" then
            index = index + 1
            ctx.config.length = tonumber(args[index]) or -1
        elseif value == "--branch-interval" then
            index = index + 1
            ctx.config.branchInterval = tonumber(args[index]) or -1
        elseif value == "--branch-length" then
            index = index + 1
            ctx.config.branchLength = tonumber(args[index]) or -1
        elseif value == "--torch-interval" then
            index = index + 1
            ctx.config.torchInterval = tonumber(args[index]) or -1
        elseif not value:find("^--") and not ctx.config.schemaPath and ctx.config.mode ~= "mine" and ctx.config.mode ~= "farm" then
            ctx.config.schemaPath = value
        end
        index = index + 1
    end

    if not ctx.config.schemaPath and ctx.config.mode ~= "mine" and ctx.config.mode ~= "farm" then
        ctx.config.schemaPath = "schema.json"
    end

    if ctx.config.home then ctx.config.home.facing = ctx.config.heading end
    ctx.config.heading = nil

    -- Initialize logger
    local logOpts = {
        level = ctx.config.verbose and "debug" or "info",
        timestamps = true
    }
    logger.attach(ctx, logOpts)
    
    ctx.logger:info("Agent starting...")

    -- Initial fuel check
    if turtle and turtle.getFuelLevel then
        local level = turtle.getFuelLevel()
        local limit = turtle.getFuelLimit()
        ctx.logger:info(string.format("Fuel: %s / %s", tostring(level), tostring(limit)))
        if level ~= "unlimited" and type(level) == "number" and level < 100 then
             ctx.logger:warn("Fuel is very low on startup!")
        end
    end

    local miningTimer
    while ctx.state ~= "EXIT" do
        local stateHandler = states[ctx.state]
        if not stateHandler then
            ctx.logger:error("Unknown state: " .. tostring(ctx.state), buildPayload(ctx))
            break
        end

        if ctx.config.mode == "mine" and ctx.state == "MINE" then
            local miner = require("lib_safe_miner")
            local status = require("lib_mining_status")
            status.render(ctx, not ctx.startConfirmed)
            if ctx.startConfirmed and not miningTimer then miningTimer = os.startTimer(0.05) end
            local timer = miningTimer
            local event, value = os.pullEvent()
            local runStep = event == "timer" and value == timer and ctx.startConfirmed
            if runStep then miningTimer = nil end
            if event == "key" and status.key(ctx, value) then
                runStep = false
            elseif event == "key" and keys and value == keys.q then
                ctx.state = miner.requestStop(ctx)
            elseif event == "key" and keys and value == keys.r and ctx.startConfirmed then
                ctx.state = miner.requestReturn(ctx)
            elseif event == "key" and keys and value == keys.enter then
                ctx.startConfirmed = true
            elseif event == "timer" and value == timer then
                -- Run one bounded instruction below.
            end
            if ctx.state == "EXIT" then status.render(ctx); break end
            if ctx.state ~= "MINE" then stateHandler = states[ctx.state]
            elseif not runStep then
                stateHandler = function() return "MINE" end
            end
        end

        ctx.logger:debug("Entering state: " .. ctx.state)
        local ok, nextStateOrErr = pcall(stateHandler, ctx)
        if not ok then
            local trace = debug and debug.traceback and debug.traceback() or nil
            ctx.logger:error("Crash in state " .. ctx.state .. ": " .. tostring(nextStateOrErr),
                buildPayload(ctx, { error = tostring(nextStateOrErr), traceback = trace }))
            ctx.lastError = nextStateOrErr
            ctx.state = "ERROR"
        else
            if type(nextStateOrErr) ~= "string" or nextStateOrErr == "" then
                ctx.logger:error("State returned invalid transition", buildPayload(ctx, { result = tostring(nextStateOrErr) }))
                ctx.lastError = nextStateOrErr
                ctx.state = "ERROR"
            elseif not states[nextStateOrErr] and nextStateOrErr ~= "EXIT" then
                ctx.logger:error("Transitioned to unknown state: " .. tostring(nextStateOrErr), buildPayload(ctx))
                ctx.state = "ERROR"
            else
                ctx.state = nextStateOrErr
            end
        end

        ---@diagnostic disable-next-line: undefined-global
        sleep(0)
    end

    if ctx.config.mode == "mine" then
        local status=require("lib_mining_status")
        status.render(ctx)
        if ctx.phase=="NEEDS_HELP" and os and os.pullEvent and keys then
            while true do
                local event,key=os.pullEvent()
                if event=="key" and key==keys.q then break end
                if event=="key" and status.key(ctx,key) then status.render(ctx) end
            end
        end
    else ctx.logger:info("Agent finished.") end
    return ctx
end

local module = { run = run }

---@diagnostic disable-next-line: undefined-field
if not _G.__FACTORY_EMBED__ then
    local argv = { ... }
    run(argv)
end

return module
