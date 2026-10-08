-- turtleos/lib/field.lua
-- The farm loop shared by the crop and sugar cane jobs.
--
-- Layout: the turtle's start spot (home) is just outside one corner of the
-- field, facing along it. The field starts one block ahead and runs
-- `length` blocks forward and `width` blocks to the right (or left).
-- The turtle flies over the field at its start height in a snake pattern,
-- calls visit() above each block, and drops the harvest into a chest
-- behind its start spot. A chest under the start spot is used for fuel.

local nav = require("turtleos.lib.nav")
local inv = require("turtleos.lib.inv")

local field = {}

-- Options every field job offers.
field.options = {
    { key = "length", label = "Length (forward)", type = "number", default = 9, min = 1, max = 64 },
    { key = "width", label = "Width", type = "number", default = 9, min = 1, max = 64 },
    { key = "side", label = "Field is to the", type = "choice", default = "right", choices = { "right", "left" } },
}

function field.cycleFuel(opts)
    -- Every block once, plus the trip back along the edges.
    return opts.width * opts.length + opts.width + opts.length + 2
end

local function home(moveOpts)
    local ok, err = nav.goTo(0, 0, 0, "yxz", moveOpts)
    if not ok then error("Can't get home: " .. err, 0) end
    nav.face(0)
end

-- Make sure there's fuel for a whole cycle, waiting for the player to add
-- some if there isn't. Call at home.
local function fuelUp(opts, ctx)
    local need = field.cycleFuel(opts) + 10
    while not ctx.stopping() do
        if inv.refuel(need) or inv.refuelFrom("down", need) then return true end
        ctx.status("Need fuel: " .. need .. ", have " .. inv.fuelLevel())
        ctx.log("Put coal in me or the chest below")
        ctx.wait(30, "Need fuel, retry in")
    end
    return false
end

local function unload(ctx, keep)
    nav.face(2)
    if not inv.unload("front", keep) then
        ctx.log("Output chest is full or missing!")
    end
    nav.face(0)
end

-- Run farm cycles until stopped. job = {
--   visit = function(ctx) ... end,     -- called above each field block
--   keep = function(name, kept) ... end, -- what to hold back when unloading
--   moveOpts = { dig = ... },            -- what may be dug while flying
--   wait = seconds between cycles }
function field.run(opts, ctx, job)
    local sign = opts.side == "left" and -1 or 1
    local moveOpts = job.moveOpts or { dig = false }

    if not nav.atHome() then
        ctx.status("Returning to start")
        home(moveOpts)
    end
    nav.face(0)

    local cycle = 0
    while not ctx.stopping() do
        cycle = cycle + 1
        unload(ctx, job.keep)
        if not fuelUp(opts, ctx) then break end

        for col = 0, opts.width - 1 do
            if ctx.stopping() then break end
            local first, last, step = 1, opts.length, 1
            if col % 2 == 1 then first, last, step = opts.length, 1, -1 end
            for z = first, last, step do
                if ctx.stopping() then break end
                if inv.freeSlots() == 0 then
                    inv.compact()
                    if inv.freeSlots() == 0 then
                        ctx.status("Full, unloading")
                        home(moveOpts)
                        unload(ctx, job.keep)
                        local ok, err = nav.goTo(col * sign, 0, z, "zx", moveOpts)
                        if not ok then error("Can't get back to the field: " .. err, 0) end
                    end
                end
                local ok, err = nav.goTo(col * sign, 0, z, "xz", moveOpts)
                if not ok then
                    ctx.log("Skipped " .. (col + 1) .. "," .. z .. ": " .. err)
                    break
                end
                ctx.status(string.format("Cycle %d, row %d of %d", cycle, col + 1, opts.width))
                job.visit(ctx)
            end
        end

        ctx.status("Heading home")
        home(moveOpts)
        unload(ctx, job.keep)
        ctx.count("Cycles")
        if opts.cycles and cycle >= opts.cycles then break end
        ctx.wait(opts.wait * 60, "Next cycle in")
    end

    home(moveOpts)
    return "Stopped at start spot"
end

return field
