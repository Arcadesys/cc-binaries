-- turtleos/strategies/miner/branch.lua
-- Branch mine: a main tunnel with side branches every few blocks. Follows
-- ore veins it uncovers, unloads into a chest at the start when full, and
-- can pick up where it left off after a reboot.

local nav = require("turtleos.lib.nav")
local inv = require("turtleos.lib.inv")

local JUNK = {}
for _, name in ipairs({
    "stone", "cobblestone", "deepslate", "cobbled_deepslate", "tuff", "granite",
    "diorite", "andesite", "dirt", "gravel", "calcite", "netherrack", "blackstone",
    "basalt", "smooth_basalt", "dripstone_block", "pointed_dripstone", "sand",
    "sandstone", "clay", "moss_block",
}) do
    JUNK["minecraft:" .. name] = true
end

local function isOre(block)
    local name = block.name
    if name:match("_ore$") or name == "minecraft:ancient_debris" then return true end
    local tags = block.tags or {}
    return tags["c:ores"] or tags["forge:ores"] or false
end

local DIG = { dig = true, patience = 10 }

local function branchCount(opts)
    return math.floor(opts.length / opts.spacing)
end

local function sides(opts)
    if opts.sides == "left" then return { 3 } end
    if opts.sides == "right" then return { 1 } end
    return { 3, 1 }
end

local function estimateFuel(opts)
    local branch = 2 * opts.branch + 4
    return 2 * opts.length + branchCount(opts) * #sides(opts) * branch + 50
end

local function run(opts, ctx)
    local function keep(name, kept)
        if name == "minecraft:torch" then return true end
        if inv.isFuel(name) then return 64 - kept end
        return 0
    end

    local function unload()
        nav.face(2)
        if not inv.unload("front", keep) then
            ctx.log("Chest behind start is full!")
        end
        nav.face(0)
    end

    local function goHome()
        local ok, err = nav.goTo(0, 0, 0, "yxz", DIG)
        if not ok then error("Can't get home: " .. err, 0) end
        nav.face(0)
    end

    -- At the start spot: refuel from inventory or the chest underneath,
    -- or wait for the player to add fuel.
    local function fuelAtHome(need)
        while not (inv.refuel(need) or inv.refuelFrom("down", need)) do
            if ctx.stopping() then return false end
            ctx.log("Need " .. need .. " fuel, have " .. inv.fuelLevel())
            ctx.wait(30, "Add coal. Retry in")
        end
        return true
    end

    -- Go unload (and refuel), then come back to exactly where we were.
    local function tripHome(reason)
        local back = nav.get()
        ctx.status(reason .. ": going to unload")
        goHome()
        unload()
        local need = 2 * (math.abs(back.x) + math.abs(back.y) + math.abs(back.z)) + 100
        if not fuelAtHome(need) then return false end
        ctx.status("Heading back")
        local ok, err = nav.goTo(back.x, back.y, back.z, "zxy", DIG)
        if not ok then error("Can't get back: " .. err, 0) end
        nav.face(back.f)
        return true
    end

    local function tossJunk()
        for slot = 1, 16 do
            local d = turtle.getItemDetail(slot)
            if d and JUNK[d.name] then
                turtle.select(slot)
                turtle.dropDown()
            end
        end
        turtle.select(1)
        inv.compact()
    end

    -- Room and fuel before every tunnel block. Returns false to stop.
    local function checkpoint()
        if inv.freeSlots() <= 2 then
            if opts.dropJunk then tossJunk() end
            if inv.freeSlots() <= 2 and not tripHome("Full") then return false end
        end
        local need = nav.distanceHome() + 64
        if inv.fuelLevel() < need and not inv.refuel(need + 500) then
            if not tripHome("Low fuel") then return false end
        end
        return true
    end

    -- Mine out an ore vein starting at `dir` ("up", "down" or a facing),
    -- then come back to where we started.
    local function vein(dir, depth)
        depth = depth or 0
        local ok, block
        if dir == "up" then
            ok, block = turtle.inspectUp()
        elseif dir == "down" then
            ok, block = turtle.inspectDown()
        else
            nav.face(dir)
            ok, block = turtle.inspect()
        end
        if not ok or not isOre(block) or depth > 24 then return end
        local from = nav.get()
        local moved
        if dir == "up" then
            moved = nav.up(DIG)
        elseif dir == "down" then
            moved = nav.down(DIG)
        else
            moved = nav.forward(DIG)
        end
        if not moved then return end
        ctx.count("Ore")
        for _, d in ipairs({ "up", "down", 0, 1, 2, 3 }) do
            vein(d, depth + 1)
        end
        nav.goTo(from.x, from.y, from.z, "yxz", DIG)
    end

    -- Dig one block of 2-high tunnel in `heading` and check the floor and
    -- the lower walls for ore.
    local function tunnelStep(heading)
        if not checkpoint() then return false, "stopped" end
        nav.face(heading)
        local ok, err = nav.forward(DIG)
        if not ok then return false, err end
        ctx.count("Dug")
        if opts.veins then vein("up") end
        while turtle.detectUp() do
            if not turtle.digUp() then break end
            sleep(0.3)
        end
        if opts.veins then
            vein("down")
            vein((heading + 1) % 4)
            vein((heading + 3) % 4)
            nav.face(heading)
        end
        return true
    end

    -- A side branch: out along the floor, back along the ceiling so all four
    -- walls get checked, then back into the main tunnel.
    local function branch(heading)
        local dug = 0
        for i = 1, opts.branch do
            if ctx.stopping() then break end
            ctx.status(string.format("Branch %s, block %d of %d", heading == 1 and "right" or "left", i, opts.branch))
            local ok, err = tunnelStep(heading)
            if not ok then
                if err ~= "stopped" then ctx.log("Branch ended early: " .. err) end
                break
            end
            dug = i
        end
        local back = (heading + 2) % 4
        if dug > 0 then
            if opts.veins then vein(heading) end
            nav.up(DIG)
            for i = dug, 1, -1 do
                if opts.veins then
                    if i == dug then vein(heading) end
                    vein("up")
                    vein((heading + 1) % 4)
                    vein((heading + 3) % 4)
                end
                nav.face(back)
                if i > 1 then nav.forward(DIG) end
            end
            nav.down(DIG)
        end
        local ok, err = nav.goTo(0, 0, nav.get().z, "yxz", DIG)
        if not ok then error("Can't get back to the main tunnel: " .. err, 0) end
    end

    local total = branchCount(opts)
    local start = 1
    if ctx.resume then
        local saved = ctx.progress()
        if saved and saved.branch then start = saved.branch end
    end
    if not nav.atHome() then
        ctx.status("Returning to start")
        goHome()
    end
    unload()
    if not fuelAtHome(math.min(estimateFuel(opts), 400)) then
        return "Stopped: no fuel"
    end

    local sinceTorch = 0
    local function mainTo(z)
        local ok, err = nav.goTo(0, 0, math.min(nav.get().z, z), "yxz", DIG)
        if not ok then error("Can't get back to the main tunnel: " .. err, 0) end
        while nav.get().z < z do
            if ctx.stopping() then return false end
            ctx.status(string.format("Main tunnel %d of %d", nav.get().z + 1, opts.length))
            local ok2, err2 = tunnelStep(0)
            if not ok2 then
                if err2 ~= "stopped" then ctx.log("Main tunnel blocked: " .. err2) end
                return false
            end
            sinceTorch = sinceTorch + 1
            -- Torch on the ceiling block, out of the turtle's way. Skip the
            -- blocks where branches start, since the turtle passes those.
            if opts.torches > 0 and sinceTorch >= opts.torches and nav.get().z % opts.spacing ~= 0
                and inv.select("minecraft:torch") then
                if turtle.placeUp() then sinceTorch = 0 end
            end
        end
        return true
    end

    local finished = true
    for k = start, total do
        ctx.saveProgress({ branch = k })
        if not mainTo(k * opts.spacing) then finished = false break end
        for _, heading in ipairs(sides(opts)) do
            if ctx.stopping() then break end
            branch(heading)
        end
        ctx.count("Branches")
        if ctx.stopping() then finished = false break end
    end
    if finished and not mainTo(opts.length) then finished = false end

    -- Leave the stone in the tunnel rather than filling the chest with it.
    if opts.dropJunk then tossJunk() end
    ctx.status("Heading home")
    goHome()
    unload()
    if finished then
        ctx.clearProgress()
        return "Mine finished"
    end
    return "Stopped at start spot (Resume to continue)"
end

return {
    title = "Branch miner",
    summary = "Tunnel + side branches, follows ore",
    description = "Digs a 2-high main tunnel with side branches every few blocks, mining out any ore vein it sees. Unloads at a chest when full and comes back. Tosses stone and dirt to save trips.",
    setup = {
        "1. Go to the level you want to mine. Diamonds: Y -58. Iron: Y 16. Coal: Y 96 (or anywhere).",
        "2. Dig a small room. Place the turtle on the floor facing the way the main tunnel should go.",
        "3. Put a chest directly BEHIND the turtle. Ores and everything it keeps go there.",
        "4. Fuel: put coal in the turtle, or in a chest directly UNDER it (dig a hole for it). It also burns coal it mines.",
        "5. Optional: give it torches to light the main tunnel.",
        "If it stops or the chunk unloads, choose Resume to carry on from the last branch.",
    },
    options = {
        { key = "length", label = "Main tunnel", type = "number", default = 32, min = 3, max = 256, step = 4 },
        { key = "branch", label = "Branch length", type = "number", default = 16, min = 1, max = 64, step = 4 },
        { key = "spacing", label = "Branch every", type = "number", default = 3, min = 2, max = 16 },
        { key = "sides", label = "Branches", type = "choice", default = "both", choices = { "both", "left", "right" } },
        { key = "veins", label = "Follow ore veins", type = "bool", default = true },
        { key = "dropJunk", label = "Toss stone/dirt", type = "bool", default = true },
        { key = "torches", label = "Torch every", type = "number", default = 8, min = 0, max = 32 },
    },
    estimateFuel = estimateFuel,
    -- On boot, only carry on an unfinished mine; never start a new one.
    bootResumeOnly = true,
    progressText = function(saved, opts)
        return "branch " .. saved.branch .. " of " .. branchCount(opts)
    end,
    run = run,
}
