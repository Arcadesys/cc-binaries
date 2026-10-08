-- turtlesim: a virtual world and a fake `turtle` API for CC:Tweaked scripts.
--
-- Pure Lua (no CraftOS dependencies), so it can be required by tests as well as
-- by boot.lua. Coordinates follow Minecraft: east = +x, up = +y, south = +z.

local sim = {}

local DIRS = { "north", "east", "south", "west" }
local DIR_INDEX = { north = 1, east = 2, south = 3, west = 4 }
local DELTA = {
    north = { 0, 0, -1 },
    east = { 1, 0, 0 },
    south = { 0, 0, 1 },
    west = { -1, 0, 0 },
    up = { 0, 1, 0 },
    down = { 0, -1, 0 },
}
local OPPOSITE = { north = "south", south = "north", east = "west", west = "east", up = "down", down = "up" }

sim.DIRS = DIRS
sim.DELTA = DELTA

-- Fuel value per item, matching vanilla furnace burn times / 10.
sim.FUEL_VALUES = {
    ["minecraft:coal"] = 80,
    ["minecraft:charcoal"] = 80,
    ["minecraft:coal_block"] = 800,
    ["minecraft:lava_bucket"] = 1000,
    ["minecraft:blaze_rod"] = 120,
    ["minecraft:stick"] = 5,
    ["minecraft:oak_planks"] = 15,
    ["minecraft:spruce_planks"] = 15,
    ["minecraft:birch_planks"] = 15,
    ["minecraft:oak_log"] = 15,
    ["minecraft:spruce_log"] = 15,
    ["minecraft:birch_log"] = 15,
}

local CONTAINERS = {
    ["minecraft:chest"] = 27,
    ["minecraft:trapped_chest"] = 27,
    ["minecraft:barrel"] = 27,
    ["minecraft:hopper"] = 5,
}

local UNBREAKABLE = {
    ["minecraft:bedrock"] = true,
    ["minecraft:barrier"] = true,
}

local function key(x, y, z)
    return x .. "," .. y .. "," .. z
end

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = copy(v)
    end
    return out
end

local function qualify(name)
    if type(name) == "string" and not name:find(":", 1, true) then
        return "minecraft:" .. name
    end
    return name
end
sim.qualify = qualify

-- Accepts "cobblestone", "minecraft:cobblestone", "cobblestone:32",
-- { "cobblestone", 32 } or { name = "cobblestone", count = 32 }.
local function parseStack(spec)
    if spec == nil then
        return nil
    end
    if type(spec) == "string" then
        local name, count = spec:match("^(.-):(%d+)$")
        if name then
            return { name = qualify(name), count = tonumber(count) }
        end
        return { name = qualify(spec), count = 1 }
    end
    if type(spec) == "table" then
        local name = spec.name or spec[1]
        local count = spec.count or spec[2] or 1
        return { name = qualify(name), count = count }
    end
    error("bad item spec: " .. tostring(spec), 3)
end
sim.parseStack = parseStack

local function parseBlock(spec)
    if spec == nil or spec == false or spec == "air" or spec == "minecraft:air" then
        return nil
    end
    if type(spec) == "string" then
        return { name = qualify(spec) }
    end
    local block = copy(spec)
    block.name = qualify(block.name or block[1])
    block[1] = nil
    return block
end

-- World ---------------------------------------------------------------------

local World = {}
World.__index = World

-- opts (all optional; a world file returns a table of these):
--   turtle   = { x, y, z, facing, fuel, fuelLimit, selected, inventory = { [slot] = spec } }
--   blocks   = { { x, y, z, "name" or { name=, state=, tags=, items=, drops=, unbreakable= } } }
--   fill     = { { x1, y1, z1, x2, y2, z2, "name" } }   -- solid cuboid
--   floor    = "minecraft:stone" or false               -- infinite floor at floorY (default -1)
--   floorY   = -1
--   unlimitedFuel = false
--   onPlace  = function(world, x, y, z, itemName) -> block spec, false (can't place) or nil (default)
function sim.newWorld(opts)
    opts = opts or {}
    local t = opts.turtle or {}
    local w = setmetatable({
        blocks = {},
        dropped = {},
        floor = opts.floor == nil and "minecraft:stone" or opts.floor,
        floorY = opts.floorY or -1,
        floorDrops = opts.floorDrops,
        deepFloor = opts.deepFloor,
        deepFloorY = opts.deepFloorY,
        ores = opts.ores,
        seed = opts.seed or 1,
        unlimitedFuel = opts.unlimitedFuel or false,
        log = {},
        trace = nil,
        stats = { moves = 0, turns = 0, dug = 0, placed = 0, fuelUsed = 0, actions = 0 },
        changes = {},
        turtle = {
            x = t.x or 0, y = t.y or 0, z = t.z or 0,
            facing = t.facing or "north",
            fuel = t.fuel or 0,
            fuelLimit = t.fuelLimit or 20000,
            selected = t.selected or 1,
            slots = {},
        },
        visited = {},
        minedByName = {},
        failures = {},
        maxActions = opts.maxActions or 1000000,
        onPlace = opts.onPlace,
    }, World)

    for _, f in ipairs(opts.fill or {}) do
        local x1, y1, z1, x2, y2, z2, name = table.unpack(f)
        for x = math.min(x1, x2), math.max(x1, x2) do
            for y = math.min(y1, y2), math.max(y1, y2) do
                for z = math.min(z1, z2), math.max(z1, z2) do
                    w.blocks[key(x, y, z)] = parseBlock(name)
                end
            end
        end
    end
    for _, b in ipairs(opts.blocks or {}) do
        local block = parseBlock(b[4] or b.block)
        w:setBlock(b[1] or b.x, b[2] or b.y, b[3] or b.z, block, true)
    end
    for slot, spec in pairs(t.inventory or {}) do
        w.turtle.slots[slot] = parseStack(spec)
    end
    w.changes = {}
    w.visited[key(w.turtle.x, w.turtle.y, w.turtle.z)] = true
    return w
end

-- Deterministic 0..1 noise for (x, y, z, salt) so a world seed always
-- generates the same ore layout.
local function hash01(seed, x, y, z, salt)
    -- CC's Lua has no bitwise operators; a Park-Miller style mix stays exact
    -- in doubles because every product is below 2^53.
    local m = 2147483647
    local h = (x * 73856093 + y * 19349663 + z * 83492791 + seed * 2654435 + salt * 97531) % m
    h = (h * 48271 + 11) % m
    h = (h * 48271 + 17) % m
    return h / m
end
sim.hash01 = hash01

-- Natural block below floorY: ores from `self.ores`, otherwise the floor.
-- Each ore = { name, chance = per-vein-cell, minY, maxY, drops, vein = cell size }.
function World:natural(x, y, z)
    for i, ore in ipairs(self.ores or {}) do
        if (not ore.minY or y >= ore.minY) and (not ore.maxY or y <= ore.maxY) then
            local v = ore.vein or 2
            local cx, cy, cz = math.floor(x / v), math.floor(y / v), math.floor(z / v)
            if hash01(self.seed, cx, cy, cz, i) < (ore.chance or 0.01)
                and hash01(self.seed, x, y, z, i + 100) < (ore.density or 0.55) then
                return { name = qualify(ore.name or ore[1]), drops = ore.drops, implicit = true }
            end
        end
    end
    local name = self.floor
    if self.deepFloor and self.deepFloorY and y <= self.deepFloorY then
        name = self.deepFloor
    end
    return { name = qualify(name), drops = self.floorDrops and self.floorDrops[name], implicit = true }
end

function World:getBlock(x, y, z)
    local k = key(x, y, z)
    local b = self.blocks[k]
    if b then
        return b
    end
    if self.floor and y <= self.floorY and not self.blocks[k .. "#air"] then
        b = self:natural(x, y, z)
        self.blocks[k] = b  -- materialize so later edits/containers stick
        return b
    end
    return nil
end

function World:setBlock(x, y, z, block, silent)
    local k = key(x, y, z)
    if block and CONTAINERS[block.name] and not block.items then
        block.items = {}
    end
    if block and block.items then
        local items = {}
        for slot, spec in pairs(block.items) do
            items[slot] = parseStack(spec)
        end
        block.items = items
        block.size = block.size or CONTAINERS[block.name] or 27
    end
    self.blocks[k] = block
    if block == nil and self.floor and y <= self.floorY then
        self.blocks[k .. "#air"] = true
    elseif block then
        self.blocks[k .. "#air"] = nil
    end
    if not silent then
        self.changes[#self.changes + 1] = { x = x, y = y, z = z, name = block and block.name or "air" }
    end
end

function World:say(fmt, ...)
    local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    self.log[#self.log + 1] = msg
    if self.trace then
        self.trace(msg)
    end
end

function World:pos()
    local t = self.turtle
    return string.format("(%d,%d,%d %s)", t.x, t.y, t.z, t.facing)
end

-- Position of the block on `side` ("front"/"up"/"down"/"back", or a
-- peripheral side name) relative to the turtle.
function World:target(side)
    local t = self.turtle
    local dir
    if side == "front" or side == "forward" then
        dir = t.facing
    elseif side == "back" then
        dir = OPPOSITE[t.facing]
    elseif side == "up" or side == "top" then
        dir = "up"
    elseif side == "down" or side == "bottom" then
        dir = "down"
    elseif side == "left" then
        dir = DIRS[(DIR_INDEX[t.facing] - 2) % 4 + 1]
    elseif side == "right" then
        dir = DIRS[DIR_INDEX[t.facing] % 4 + 1]
    else
        return nil
    end
    local d = DELTA[dir]
    return t.x + d[1], t.y + d[2], t.z + d[3], dir
end

-- Inventory helpers -----------------------------------------------------------

local MAX_STACK = 64

-- Insert a stack into a slot table (1..size), preferring `first`. Returns the
-- number of items that did not fit.
local function insert(slots, size, stack, first)
    local remaining = stack.count
    local order = {}
    if first then
        for i = first, size do order[#order + 1] = i end
        for i = 1, first - 1 do order[#order + 1] = i end
    else
        for i = 1, size do order[#order + 1] = i end
    end
    for _, i in ipairs(order) do
        local s = slots[i]
        if remaining > 0 and s and s.name == stack.name and s.count < MAX_STACK then
            local n = math.min(MAX_STACK - s.count, remaining)
            s.count = s.count + n
            remaining = remaining - n
        end
    end
    for _, i in ipairs(order) do
        if remaining > 0 and not slots[i] then
            local n = math.min(MAX_STACK, remaining)
            slots[i] = { name = stack.name, count = n }
            remaining = remaining - n
        end
    end
    return remaining
end
sim.insert = insert

function World:give(spec, slot)
    local stack = parseStack(spec)
    return insert(self.turtle.slots, 16, stack, slot)
end

-- Put a block next to the turtle ("front", "up", "down", ...); nil clears it.
function World:setSide(side, block)
    local x, y, z = self:target(side)
    self:setBlock(x, y, z, parseBlock(block))
end

-- Remove every stack of `name` from the turtle; returns how many items went.
function World:take(name)
    name = qualify(name)
    local n = 0
    for i = 1, 16 do
        local s = self.turtle.slots[i]
        if s and s.name == name then
            n = n + s.count
            self.turtle.slots[i] = nil
        end
    end
    return n
end

function World:count(name)
    name = qualify(name)
    local total = 0
    for i = 1, 16 do
        local s = self.turtle.slots[i]
        if s and (name == nil or s.name == name) then
            total = total + s.count
        end
    end
    return total
end

-- The turtle API --------------------------------------------------------------

local function checkSlot(slot)
    if type(slot) ~= "number" or slot < 1 or slot > 16 or slot % 1 ~= 0 then
        error("Slot out of range (expected 1-16)", 3)
    end
end

function World:makeTurtle()
    local w = self
    local t = self.turtle
    local api = {}

    local function act(name)
        w.stats.actions = w.stats.actions + 1
        if w.stats.actions > w.maxActions then
            local msg = "exceeded " .. w.maxActions .. " turtle actions (infinite loop?)"
            if w.abort then
                w.abort(msg)
            end
            error("turtlesim: " .. msg, 0)
        end
        if w.onAction then
            w.onAction(name)
        end
    end

    local function move(dir, label)
        act(label)
        if not w.unlimitedFuel and t.fuel <= 0 then
            w:say("%s blocked: out of fuel %s", label, w:pos())
            return false, "Out of fuel"
        end
        local d = DELTA[dir]
        local nx, ny, nz = t.x + d[1], t.y + d[2], t.z + d[3]
        if w:getBlock(nx, ny, nz) then
            w:say("%s blocked by %s %s", label, w:getBlock(nx, ny, nz).name, w:pos())
            return false, "Movement obstructed"
        end
        t.x, t.y, t.z = nx, ny, nz
        if not w.unlimitedFuel then
            t.fuel = t.fuel - 1
            w.stats.fuelUsed = w.stats.fuelUsed + 1
        end
        w.stats.moves = w.stats.moves + 1
        w.visited[key(nx, ny, nz)] = true
        w:say("%s -> %s", label, w:pos())
        return true
    end

    function api.forward() return move(t.facing, "forward") end
    function api.back() return move(OPPOSITE[t.facing], "back") end
    function api.up() return move("up", "up") end
    function api.down() return move("down", "down") end

    function api.turnLeft()
        act("turnLeft")
        t.facing = DIRS[(DIR_INDEX[t.facing] - 2) % 4 + 1]
        w.stats.turns = w.stats.turns + 1
        w:say("turnLeft -> %s", w:pos())
        return true
    end

    function api.turnRight()
        act("turnRight")
        t.facing = DIRS[DIR_INDEX[t.facing] % 4 + 1]
        w.stats.turns = w.stats.turns + 1
        w:say("turnRight -> %s", w:pos())
        return true
    end

    local function detect(side)
        act("detect")
        local x, y, z = w:target(side)
        return w:getBlock(x, y, z) ~= nil
    end
    function api.detect() return detect("front") end
    function api.detectUp() return detect("up") end
    function api.detectDown() return detect("down") end

    local function inspect(side)
        act("inspect")
        local x, y, z = w:target(side)
        local b = w:getBlock(x, y, z)
        if not b then
            return false, "No block to inspect"
        end
        return true, { name = b.name, state = copy(b.state or {}), tags = copy(b.tags or {}) }
    end
    function api.inspect() return inspect("front") end
    function api.inspectUp() return inspect("up") end
    function api.inspectDown() return inspect("down") end

    local function compare(side)
        act("compare")
        local x, y, z = w:target(side)
        local b = w:getBlock(x, y, z)
        local s = t.slots[t.selected]
        if not b then
            return s == nil
        end
        return s ~= nil and s.name == b.name
    end
    function api.compare() return compare("front") end
    function api.compareUp() return compare("up") end
    function api.compareDown() return compare("down") end

    local function dig(side, label)
        act(label)
        local x, y, z = w:target(side)
        local b = w:getBlock(x, y, z)
        if not b then
            return false, "Nothing to dig here"
        end
        if b.unbreakable or UNBREAKABLE[b.name] then
            w:say("%s failed: %s is unbreakable", label, b.name)
            return false, "Cannot break unbreakable block"
        end
        w:setBlock(x, y, z, nil)
        w.stats.dug = w.stats.dug + 1
        w.minedByName[b.name] = (w.minedByName[b.name] or 0) + 1
        local drops = b.drops
        if drops == nil then
            drops = { { name = b.name, count = 1 } }
        elseif type(drops) ~= "table" or drops.name or type(drops[1]) == "string" and #drops == 1 then
            drops = { drops }
        end
        for _, spec in ipairs(drops) do
            local stack = parseStack(spec)
            local left = insert(t.slots, 16, stack, t.selected)
            if left > 0 then
                w.dropped[#w.dropped + 1] = { name = stack.name, count = left }
            end
        end
        for _, stack in pairs(b.items or {}) do
            w.dropped[#w.dropped + 1] = copy(stack)
        end
        w:say("%s %s at %d,%d,%d", label, b.name, x, y, z)
        return true
    end
    function api.dig() return dig("front", "dig") end
    function api.digUp() return dig("up", "digUp") end
    function api.digDown() return dig("down", "digDown") end

    local function place(side, label)
        act(label)
        local x, y, z, dir = w:target(side)
        local s = t.slots[t.selected]
        if not s then
            return false, "No items to place"
        end
        if w:getBlock(x, y, z) then
            return false, "Cannot place block here"
        end
        local block = { name = s.name }
        if CONTAINERS[s.name] then
            block.items = {}
        end
        if dir ~= "up" and dir ~= "down" then
            block.state = { facing = OPPOSITE[dir] }
        end
        if w.onPlace then
            local custom = w.onPlace(w, x, y, z, s.name)
            if custom == false then
                return false, "Cannot place block here"
            elseif custom then
                block = parseBlock(custom)
            end
        end
        w:setBlock(x, y, z, block)
        s.count = s.count - 1
        if s.count <= 0 then
            t.slots[t.selected] = nil
        end
        w.stats.placed = w.stats.placed + 1
        w:say("%s %s at %d,%d,%d", label, block.name, x, y, z)
        return true
    end
    function api.place() return place("front", "place") end
    function api.placeUp() return place("up", "placeUp") end
    function api.placeDown() return place("down", "placeDown") end

    local function attack(side)
        act("attack")
        return false, "Nothing to attack here"
    end
    function api.attack() return attack("front") end
    function api.attackUp() return attack("up") end
    function api.attackDown() return attack("down") end

    function api.select(slot)
        checkSlot(slot)
        t.selected = slot
        return true
    end
    function api.getSelectedSlot() return t.selected end

    function api.getItemCount(slot)
        slot = slot or t.selected
        checkSlot(slot)
        local s = t.slots[slot]
        return s and s.count or 0
    end

    function api.getItemSpace(slot)
        slot = slot or t.selected
        checkSlot(slot)
        local s = t.slots[slot]
        return s and (MAX_STACK - s.count) or MAX_STACK
    end

    function api.getItemDetail(slot, detailed)
        slot = slot or t.selected
        checkSlot(slot)
        local s = t.slots[slot]
        if not s then
            return nil
        end
        local d = { name = s.name, count = s.count }
        if detailed then
            d.displayName = s.name:gsub("^.-:", ""):gsub("_", " ")
            d.maxCount = MAX_STACK
            d.tags = {}
        end
        return d
    end

    function api.transferTo(slot, count)
        checkSlot(slot)
        local from = t.slots[t.selected]
        if not from then
            return false, "No items to transfer"
        end
        count = math.min(count or from.count, from.count)
        local to = t.slots[slot]
        if to and to.name ~= from.name then
            return false, "No space for items"
        end
        local space = to and (MAX_STACK - to.count) or MAX_STACK
        local n = math.min(count, space)
        if n <= 0 then
            return false, "No space for items"
        end
        if to then
            to.count = to.count + n
        else
            t.slots[slot] = { name = from.name, count = n }
        end
        from.count = from.count - n
        if from.count <= 0 then
            t.slots[t.selected] = nil
        end
        return true
    end

    function api.compareTo(slot)
        checkSlot(slot)
        local a, b = t.slots[t.selected], t.slots[slot]
        if a == nil or b == nil then
            return a == b
        end
        return a.name == b.name
    end

    function api.getFuelLevel()
        return w.unlimitedFuel and "unlimited" or t.fuel
    end
    function api.getFuelLimit()
        return w.unlimitedFuel and "unlimited" or t.fuelLimit
    end

    function api.refuel(count)
        act("refuel")
        local s = t.slots[t.selected]
        local value = s and sim.FUEL_VALUES[s.name]
        if count == 0 then
            if value then return true end
            return false, "Items not combustible"
        end
        if not value then
            return false, "Items not combustible"
        end
        local n = math.min(count or s.count, s.count)
        local room = math.floor((t.fuelLimit - t.fuel) / value)
        n = math.max(0, math.min(n, room))
        t.fuel = t.fuel + n * value
        s.count = s.count - n
        if s.count <= 0 then
            t.slots[t.selected] = nil
        end
        if s.name == "minecraft:lava_bucket" and n > 0 then
            insert(t.slots, 16, { name = "minecraft:bucket", count = n }, t.selected)
        end
        w:say("refuel %d x %s -> fuel %d", n, s.name, t.fuel)
        return true
    end

    local function containerAt(side)
        local x, y, z = w:target(side)
        local b = w:getBlock(x, y, z)
        if b and b.items then
            return b
        end
        return nil
    end

    local function drop(side, label, count)
        act(label)
        local s = t.slots[t.selected]
        if not s then
            return false, "No items to drop"
        end
        local n = math.min(count or s.count, s.count)
        local c = containerAt(side)
        local moved = n
        if c then
            moved = n - insert(c.items, c.size, { name = s.name, count = n })
            if moved <= 0 then
                return false, "No space for items"
            end
        else
            w.dropped[#w.dropped + 1] = { name = s.name, count = n }
        end
        s.count = s.count - moved
        local name = s.name
        if s.count <= 0 then
            t.slots[t.selected] = nil
        end
        w:say("%s %d x %s%s", label, moved, name, c and (" into " .. c.name) or "")
        return true
    end
    function api.drop(n) return drop("front", "drop", n) end
    function api.dropUp(n) return drop("up", "dropUp", n) end
    function api.dropDown(n) return drop("down", "dropDown", n) end

    local function suck(side, label, count)
        act(label)
        local c = containerAt(side)
        if not c then
            return false, "No items to take"
        end
        local want = count or MAX_STACK
        for slot = 1, c.size do
            local s = c.items[slot]
            if s then
                local n = math.min(want, s.count)
                local left = insert(t.slots, 16, { name = s.name, count = n }, t.selected)
                local moved = n - left
                if moved <= 0 then
                    return false, "No space for items"
                end
                s.count = s.count - moved
                if s.count <= 0 then
                    c.items[slot] = nil
                end
                w:say("%s %d x %s from %s", label, moved, s.name, c.name)
                return true
            end
        end
        return false, "No items to take"
    end
    function api.suck(n) return suck("front", "suck", n) end
    function api.suckUp(n) return suck("up", "suckUp", n) end
    function api.suckDown(n) return suck("down", "suckDown", n) end

    function api.equipLeft() return true end
    function api.equipRight() return true end
    function api.craft() return false, "No crafting table" end

    -- Tally failures that usually mean a bug in the script. Empty digs and
    -- bumping into stone (then digging it) are routine, so they don't count.
    local TRACKED = {
        "forward", "back", "up", "down", "place", "placeUp", "placeDown",
        "dig", "digUp", "digDown", "drop", "dropUp", "dropDown", "refuel", "transferTo",
    }
    for _, name in ipairs(TRACKED) do
        local fn = api[name]
        api[name] = function(...)
            local ok, reason = fn(...)
            if ok == false and reason ~= "Nothing to dig here" and reason ~= "Movement obstructed" then
                local label = name .. " (" .. tostring(reason) .. ")"
                w.failures[label] = (w.failures[label] or 0) + 1
            end
            return ok, reason
        end
    end

    return api
end

-- Peripherals: containers next to the turtle look like CC inventories.
function World:makePeripheral(fallback)
    local w = self
    local SIDES = { "front", "back", "top", "bottom", "left", "right" }
    local p = {}

    local function container(side)
        local x, y, z = w:target(side)
        if not x then
            return nil
        end
        local b = w:getBlock(x, y, z)
        if b and b.items then
            return b
        end
    end

    local function wrapContainer(c)
        local inv = {}
        function inv.size() return c.size end
        function inv.list()
            local out = {}
            for slot, s in pairs(c.items) do
                out[slot] = { name = s.name, count = s.count }
            end
            return out
        end
        function inv.getItemDetail(slot)
            local s = c.items[slot]
            return s and { name = s.name, count = s.count, maxCount = MAX_STACK, displayName = s.name } or nil
        end
        function inv.getItemLimit() return MAX_STACK end
        function inv.getMetadata() return { name = c.name, displayName = c.name } end
        -- Only the turtle is reachable: accept "turtle" or the direction
        -- pointing at it (the legacy push-direction style lib_inventory uses).
        function inv.pushItems(toName, fromSlot, limit, toSlot)
            local s = c.items[fromSlot]
            if not s then
                return 0
            end
            local n = math.min(limit or s.count, s.count)
            local left = insert(w.turtle.slots, 16, { name = s.name, count = n }, toSlot or w.turtle.selected)
            local moved = n - left
            s.count = s.count - moved
            if s.count <= 0 then
                c.items[fromSlot] = nil
            end
            if moved > 0 then
                w:say("chest pushItems %d x %s -> turtle (%s)", moved, s.name, tostring(toName))
            end
            return moved
        end
        function inv.pullItems(fromName, fromSlot, limit, toSlot)
            local s = w.turtle.slots[fromSlot]
            if not s then
                return 0
            end
            local n = math.min(limit or s.count, s.count)
            local moved = n - insert(c.items, c.size, { name = s.name, count = n }, toSlot)
            s.count = s.count - moved
            if s.count <= 0 then
                w.turtle.slots[fromSlot] = nil
            end
            return moved
        end
        return inv
    end

    function p.isPresent(side)
        if container(side) then return true end
        return fallback and fallback.isPresent(side) or false
    end
    function p.getType(side)
        local c = container(side)
        if c then return c.name, "inventory" end
        if fallback then return fallback.getType(side) end
    end
    function p.hasType(side, ty)
        local c = container(side)
        if c then return ty == c.name or ty == "inventory" end
        if fallback and fallback.hasType then return fallback.hasType(side, ty) end
    end
    function p.getMethods(side)
        local c = container(side)
        if c then
            local names = {}
            for k in pairs(wrapContainer(c)) do names[#names + 1] = k end
            table.sort(names)
            return names
        end
        if fallback then return fallback.getMethods(side) end
    end
    function p.wrap(side)
        local c = container(side)
        if c then return wrapContainer(c) end
        if fallback then return fallback.wrap(side) end
    end
    function p.call(side, method, ...)
        local c = container(side)
        if c then
            local inv = wrapContainer(c)
            if not inv[method] then
                error("No such method " .. tostring(method), 2)
            end
            return inv[method](...)
        end
        if fallback then return fallback.call(side, method, ...) end
        error("No peripheral attached", 2)
    end
    function p.getNames()
        local names = {}
        for _, side in ipairs(SIDES) do
            if container(side) then names[#names + 1] = side end
        end
        if fallback then
            for _, n in ipairs(fallback.getNames()) do names[#names + 1] = n end
        end
        return names
    end
    function p.find(ty, filter)
        local found = {}
        for _, side in ipairs(p.getNames()) do
            if p.hasType(side, ty) then
                local wrapped = p.wrap(side)
                if not filter or filter(side, wrapped) then
                    found[#found + 1] = wrapped
                end
            end
        end
        return table.unpack(found)
    end
    function p.getName(wrapped)
        if fallback and fallback.getName then return fallback.getName(wrapped) end
    end
    return p
end

function World:makeGps()
    local w = self
    return {
        CHANNEL_GPS = 65534,
        locate = function()
            if w.noGps then
                return nil
            end
            return w.turtle.x, w.turtle.y, w.turtle.z
        end,
    }
end

-- Reporting -------------------------------------------------------------------

function World:inventoryLines()
    local lines = {}
    for i = 1, 16 do
        local s = self.turtle.slots[i]
        if s then
            lines[#lines + 1] = string.format("  %2d%s %3d x %s", i, i == self.turtle.selected and "*" or " ", s.count, s.name)
        end
    end
    if #lines == 0 then
        lines[1] = "  (empty)"
    end
    return lines
end

local function isOreName(name)
    return name ~= nil and (name:find("_ore$") ~= nil or name == "minecraft:ancient_debris")
end
sim.isOreName = isOreName

local MAP_CHARS = { north = "^", east = ">", south = "v", west = "<" }

-- Top-down ASCII map of the turtle's current layer. North is up.
function World:mapLines()
    local t = self.turtle
    local minX, maxX, minZ, maxZ = t.x, t.x, t.z, t.z
    for k in pairs(self.visited) do
        local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
        x, y, z = tonumber(x), tonumber(y), tonumber(z)
        if y == t.y then
            minX, maxX = math.min(minX, x), math.max(maxX, x)
            minZ, maxZ = math.min(minZ, z), math.max(maxZ, z)
        end
    end
    -- Show everything visited on this layer, capped so huge runs stay readable.
    local MAXW, MAXH = 72, 40
    minX, maxX, minZ, maxZ = minX - 1, maxX + 1, minZ - 1, maxZ + 1
    if maxX - minX + 1 > MAXW then
        minX = math.max(minX, math.min(t.x - math.floor(MAXW / 2), maxX - MAXW + 1))
        maxX = minX + MAXW - 1
    end
    if maxZ - minZ + 1 > MAXH then
        minZ = math.max(minZ, math.min(t.z - math.floor(MAXH / 2), maxZ - MAXH + 1))
        maxZ = minZ + MAXH - 1
    end
    local lines = { string.format("  layer y=%d, x %d..%d, z %d..%d (north is up)", t.y, minX, maxX, minZ, maxZ) }
    for z = minZ, maxZ do
        local row = {}
        for x = minX, maxX do
            local ch
            if x == t.x and z == t.z then
                ch = MAP_CHARS[t.facing]
            else
                local b = self:getBlock(x, t.y, z)
                if b then
                    ch = b.items and "C" or (isOreName(b.name) and "o" or "#")
                elseif self.visited[key(x, t.y, z)] then
                    ch = "."
                else
                    ch = " "
                end
            end
            row[#row + 1] = ch
        end
        lines[#lines + 1] = "  |" .. table.concat(row) .. "|"
    end
    lines[#lines + 1] = "  legend: ^>v< turtle  . visited  # block  o ore  C container"
    return lines
end


-- Every explicitly placed or scripted block (natural floor and ore excluded),
-- as {x, y, z, name, facing?} sorted by position. For build-vs-blueprint diffs.
function World:placedBlocks()
    local out = {}
    for k, b in pairs(self.blocks) do
        if type(b) == "table" and not b.implicit then
            local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
            if x then
                out[#out + 1] = { tonumber(x), tonumber(y), tonumber(z), b.name, b.state and b.state.facing or nil }
            end
        end
    end
    table.sort(out, function(a, c)
        if a[2] ~= c[2] then return a[2] < c[2] end
        if a[3] ~= c[3] then return a[3] < c[3] end
        return a[1] < c[1]
    end)
    return out
end

-- Ore mined, plus ore still touching the tunnel (i.e. missed by the miner).
function World:oreSummary()
    local mined, missed = {}, {}
    for name, n in pairs(self.minedByName) do
        if isOreName(name) then
            mined[name] = n
        end
    end
    local seen = {}
    for k in pairs(self.visited) do
        local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
        x, y, z = tonumber(x), tonumber(y), tonumber(z)
        for _, d in pairs(DELTA) do
            local nk = key(x + d[1], y + d[2], z + d[3])
            local b = not seen[nk] and self.blocks[nk]
            seen[nk] = true
            if b and isOreName(b.name) then
                missed[b.name] = (missed[b.name] or 0) + 1
            end
        end
    end
    return mined, missed
end

local function tally(t)
    local names, total = {}, 0
    for name, n in pairs(t) do
        names[#names + 1] = name
        total = total + n
    end
    table.sort(names, function(a, b)
        if t[a] ~= t[b] then return t[a] > t[b] end
        return a < b
    end)
    local parts = {}
    for _, name in ipairs(names) do
        parts[#parts + 1] = string.format("%s %d", name:gsub("^minecraft:", ""), t[name])
    end
    return total, table.concat(parts, ", ")
end

function World:report()
    local t = self.turtle
    local s = self.stats
    local lines = {
        "== turtlesim report ==",
        string.format("position  %d,%d,%d facing %s", t.x, t.y, t.z, t.facing),
        string.format("fuel      %s (used %d)", self.unlimitedFuel and "unlimited" or tostring(t.fuel), s.fuelUsed),
        string.format("actions   %d  moves %d  turns %d  dug %d  placed %d", s.actions, s.moves, s.turns, s.dug, s.placed),
    }
    local mined, missed = self:oreSummary()
    local minedTotal, minedText = tally(mined)
    local missedTotal, missedText = tally(missed)
    if minedTotal + missedTotal > 0 then
        lines[#lines + 1] = string.format("ores      mined %d%s", minedTotal, minedTotal > 0 and (": " .. minedText) or "")
        lines[#lines + 1] = string.format("          missed %d (still touching the tunnel)%s", missedTotal, missedTotal > 0 and (": " .. missedText) or "")
        if s.fuelUsed > 0 then
            lines[#lines + 1] = string.format("          %.1f ores per 100 fuel", minedTotal * 100 / s.fuelUsed)
        end
    end
    local failTotal, failText = tally(self.failures)
    if failTotal > 0 then
        lines[#lines + 1] = string.format("failed    %d action(s): %s", failTotal, failText)
    end
    lines[#lines + 1] = "inventory"
    for _, l in ipairs(self:inventoryLines()) do lines[#lines + 1] = l end
    if #self.dropped > 0 then
        local n = 0
        for _, d in ipairs(self.dropped) do n = n + d.count end
        lines[#lines + 1] = string.format("dropped   %d item(s) on the ground", n)
    end
    for k, b in pairs(self.blocks) do
        if type(b) == "table" and b.items and next(b.items) then
            local counts = {}
            for _, st in pairs(b.items) do
                counts[st.name] = (counts[st.name] or 0) + st.count
            end
            local _, text = tally(counts)
            lines[#lines + 1] = string.format("%s at %s: %s", b.name:gsub("^minecraft:", ""), k, text)
        end
    end
    lines[#lines + 1] = "map"
    for _, l in ipairs(self:mapLines()) do lines[#lines + 1] = l end
    return lines
end

return sim
