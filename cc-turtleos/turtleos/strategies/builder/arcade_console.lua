-- turtleos/strategies/builder/arcade_console.lua
-- Builds an arcade console: a 5x4 advanced monitor screen, the computer under
-- it, three button pedestals in front, and redstone in the floor from each
-- button to its own side of the computer.
--
-- Layout, in nav coordinates (home = the centre pedestal, z toward the screen):
--   screen      x -2..2, y 0..3, z = D       (monitors placed from z = D-1)
--   computer    (0, -1, D), in the floor under the screen's bottom middle
--   pedestals   x -2, 0, 2 at (x, 0, 0), a button on each at y = 1
--   redstone    in a groove in the floor (y = -1):
--     centre  x = 0,  z 0..D-1        -> the computer's front
--     left    x = -2, z 0..D, then (-1, -1, D) -> the computer's left
--     right   x = 2,  z 0..D, then (1, -1, D)  -> the computer's right
-- The lines never touch side by side, so each button reaches one side only. A
-- button powers its pedestal, which powers the redstone under it.

local nav = require("turtleos.lib.nav")
local inv = require("turtleos.lib.inv")

local MONITOR = "computercraft:monitor_advanced"
local COMPUTER = "computercraft:computer_advanced"
local REDSTONE = "minecraft:redstone"
local WIRE = "minecraft:redstone_wire"
local NO_DIG = { dig = false }

local function isButton(name) return name:find("_button$") ~= nil end
local function reserved(name)
    return name == MONITOR or name == COMPUTER or name == REDSTONE or isButton(name) or inv.isFuel(name)
end

local function wires(d)
    local list = {}
    for z = 0, d - 1 do list[#list + 1] = { 0, z } end
    for _, x in ipairs({ -2, 2 }) do
        for z = 0, d do list[#list + 1] = { x, z } end
        list[#list + 1] = { x < 0 and -1 or 1, d }
    end
    return list
end

local function needs(opts)
    return {
        { MONITOR, 20, "advanced monitors" },
        { COMPUTER, 1, "advanced computer" },
        { REDSTONE, #wires(opts.distance), "redstone dust" },
        { isButton, 3, "buttons" },
    }
end

local function estimateFuel(opts)
    return 10 * opts.distance + 120
end

local function run(opts, ctx)
    local d = opts.distance
    -- A resumed build has already used some of these.
    local missing = {}
    for _, n in ipairs(ctx.resume and {} or needs(opts)) do
        local have = inv.count(n[1])
        if have < n[2] then missing[#missing + 1] = (n[2] - have) .. " " .. n[3] end
    end
    if #missing > 0 then error("Needs " .. table.concat(missing, ", "), 0) end
    if inv.fuelLevel() < estimateFuel(opts) then
        inv.refuel(estimateFuel(opts))
        if inv.fuelLevel() < estimateFuel(opts) then error("Needs about " .. estimateFuel(opts) .. " fuel", 0) end
    end
    -- Blocks the player brought make the pedestals; floor dug out of the
    -- grooves fills any gaps under the redstone.
    local brought = {}
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item and not reserved(item.name) then brought[item.name] = true end
    end
    local function placeBlockDown(prefer)
        for pass = 1, 2 do
            for slot = 1, 16 do
                local item = turtle.getItemDetail(slot)
                if item and not reserved(item.name) and (pass == 2 or prefer(item.name)) then
                    turtle.select(slot)
                    if turtle.placeDown() then return true end
                end
            end
        end
        return false
    end
    local function place(dir, match, what)
        if not inv.select(match) then error("Ran out of " .. what, 0) end
        local ok = (dir == "down" and turtle.placeDown or turtle.place)()
        if not ok then error("Can't place the " .. what .. " (something in the way?)", 0) end
    end
    local function go(x, y, z, order)
        local ok, err = nav.goTo(x, y, z, order, NO_DIG)
        if not ok then error("Can't get to the next spot: " .. err, 0) end
    end
    local function below(name)
        local ok, block = turtle.inspectDown()
        return ok and block.name == name
    end

    local phase = 1
    if ctx.resume then
        local saved = ctx.progress()
        if saved and saved.phase then phase = saved.phase end
        -- Climb over whatever is built, then come down where the phase starts.
        ctx.status("Getting back on track")
        local p = nav.get()
        go(p.x, 5, p.z, "y")
    end

    -- 1. Grooves, redstone and the computer.
    if phase <= 1 then
        ctx.saveProgress({ phase = 1 })
        local cells = wires(d)
        cells[#cells + 1] = { 0, d, computer = true }
        for k, c in ipairs(cells) do
            if ctx.stopping() then return "Stopped (Resume to continue)" end
            ctx.status(string.format("Floor wiring %d of %d", k, #cells))
            go(c[1], nav.get().y, c[2], "xz")
            go(c[1], 0, c[2], "y")
            local done = below(c.computer and COMPUTER or WIRE)
            if not done then
                if turtle.detectDown() and not turtle.digDown() then error("Can't dig the floor here", 0) end
                -- Redstone needs a solid block under it.
                go(c[1], -1, c[2], "y")
                if not turtle.detectDown() and not placeBlockDown(function(name) return not brought[name] end) then
                    error("Needs a block to fill a hole in the floor", 0)
                end
                go(c[1], 0, c[2], "y")
                if c.computer then place("down", COMPUTER, "computer")
                else place("down", REDSTONE, "redstone") end
                ctx.count(c.computer and "Computer" or "Redstone")
            end
        end
        -- The computer starts now, so the player only has to install a game.
        if peripheral.getType("bottom") then pcall(peripheral.call, "bottom", "turnOn") end
        phase = 2
    end

    -- 2. The screen, placed facing back toward the buttons.
    if phase <= 2 then
        ctx.saveProgress({ phase = 2 })
        go(nav.get().x, math.max(nav.get().y, 0), d - 1, "yz")
        for y = 0, 3 do
            for i = 0, 4 do
                if ctx.stopping() then return "Stopped (Resume to continue)" end
                -- Snake across each row.
                local x = (y % 2 == 0) and (i - 2) or (2 - i)
                ctx.status(string.format("Screen %d of 20", y * 5 + i + 1))
                go(x, y, d - 1, "yx")
                nav.face(0)
                local ok, block = turtle.inspect()
                if not (ok and block.name == MONITOR) then
                    if ok and not turtle.dig() then error("Can't clear the screen spot", 0) end
                    place("forward", MONITOR, "monitors")
                    ctx.count("Monitors")
                end
            end
        end
        phase = 3
    end

    -- 3. Pedestals and buttons.
    if phase <= 3 then
        ctx.saveProgress({ phase = 3 })
        go(nav.get().x, 4, nav.get().z, "y")
        for _, x in ipairs({ -2, 0, 2 }) do
            if ctx.stopping() then return "Stopped (Resume to continue)" end
            ctx.status("Button pedestal at " .. (x < 0 and "left" or x > 0 and "right" or "centre"))
            go(x, 4, 0, "xz")
            go(x, 1, 0, "y")
            if not turtle.detectDown() and not placeBlockDown(function(name) return brought[name] end) then
                error("Needs 3 blocks for the button pedestals", 0)
            end
            go(x, 2, 0, "y")
            if not turtle.detectDown() then
                place("down", isButton, "buttons")
                ctx.count("Buttons")
            end
        end
    end

    -- Park behind the middle button, out of the way.
    ctx.clearProgress()
    go(0, 2, -1, "zx")
    nav.down(NO_DIG)
    nav.down(NO_DIG)
    nav.face(0)
    return "Console built. Install a game on the computer, then run config."
end

return {
    title = "Arcade console",
    summary = "5x4 screen, computer, 3 buttons",
    description = "Builds an arcade cabinet: a 5 wide, 4 tall advanced monitor screen with the computer in the floor under it, and three button pedestals in front. Redstone in grooves in the floor joins each button to its own side of the computer.",
    setup = {
        "1. Find flat, solid ground: 5 wide and (distance + 2) deep, with room 4 high for the screen.",
        "2. Place the turtle on the ground where the MIDDLE button should go, facing where the screen should be.",
        "3. Give it 20 advanced monitors, 1 advanced computer, 3 buttons, redstone dust (13 at distance 3), 3 blocks for the pedestals, and fuel. It needs a pickaxe to cut the grooves.",
        "4. The buttons go at the screen's left edge, middle and right edge.",
        "5. When it's done: click the computer's front (in the groove under the screen), install a game, e.g. wget run https://raw.githubusercontent.com/Arcadesys/cc-binaries/main/cc-arcade/get.lua all --startup, then run arcade/config and press LEFT, CENTER, RIGHT.",
        "It only digs the grooves and anything where a screen block goes.",
    },
    options = {
        { key = "distance", label = "Buttons to screen", type = "number", default = 3, min = 2, max = 8 },
    },
    estimateFuel = estimateFuel,
    bootResumeOnly = true,
    progressText = function(saved)
        return ({ "floor wiring", "screen", "buttons" })[saved.phase] or "building"
    end,
    run = run,
}
