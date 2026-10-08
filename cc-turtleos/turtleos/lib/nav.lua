-- turtleos/lib/nav.lua
-- Dead-reckoning position tracker for jobs. Coordinates are relative to the
-- spot the job started from (home): x = right, y = up, z = forward.
-- Facing: 0 = forward, 1 = right, 2 = back, 3 = left.
-- Every move is saved, so a turtle that reboots (chunk unload, server restart)
-- knows where it is and can find its way home.

local nav = {}

local STATE_FILE = "/.turtleos/nav"
local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = 1, 0, -1, 0 }

local pos = { x = 0, y = 0, z = 0, f = 0 }

local function save()
    if not fs.exists("/.turtleos") then fs.makeDir("/.turtleos") end
    local h = fs.open(STATE_FILE, "w")
    if h then
        h.write(textutils.serialize(pos))
        h.close()
    end
end

function nav.reset()
    pos = { x = 0, y = 0, z = 0, f = 0 }
    save()
end

-- Returns true when a saved position was loaded.
function nav.load()
    if not fs.exists(STATE_FILE) then return false end
    local h = fs.open(STATE_FILE, "r")
    local data = h and textutils.unserialize(h.readAll())
    if h then h.close() end
    if type(data) ~= "table" or not data.x then return false end
    pos = { x = data.x, y = data.y, z = data.z, f = data.f % 4 }
    return true
end

function nav.clear()
    if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
end

function nav.get()
    return { x = pos.x, y = pos.y, z = pos.z, f = pos.f }
end

function nav.atHome()
    return pos.x == 0 and pos.y == 0 and pos.z == 0
end

-- Moves needed to get back home.
function nav.distanceHome()
    return math.abs(pos.x) + math.abs(pos.y) + math.abs(pos.z)
end

function nav.turnLeft()
    turtle.turnLeft()
    pos.f = (pos.f + 3) % 4
    save()
end

function nav.turnRight()
    turtle.turnRight()
    pos.f = (pos.f + 1) % 4
    save()
end

function nav.face(f)
    f = f % 4
    if (pos.f + 1) % 4 == f then
        nav.turnRight()
    elseif (pos.f + 3) % 4 == f then
        nav.turnLeft()
    else
        while pos.f ~= f do nav.turnRight() end
    end
end

local SIDES = {
    forward = { move = "forward", dig = "dig", detect = "detect", inspect = "inspect", attack = "attack" },
    up = { move = "up", dig = "digUp", detect = "detectUp", inspect = "inspectUp", attack = "attackUp" },
    down = { move = "down", dig = "digDown", detect = "detectDown", inspect = "inspectDown", attack = "attackDown" },
}

-- opts.dig: true to dig anything in the way, false to never dig, or a
--   function(blockData) returning true for blocks it may dig.
-- opts.patience: seconds to keep retrying a blocked move (default 30).
-- Returns true, or false and a reason.
local function step(side, opts)
    opts = opts or {}
    local s = SIDES[side]
    if turtle.getFuelLevel() == 0 then
        return false, "out of fuel"
    end
    local deadline = os.clock() + (opts.patience or 30)
    local digs = 0
    while not turtle[s.move]() do
        local ok, data = turtle[s.inspect]()
        if ok then
            local allowed = opts.dig == true or (type(opts.dig) == "function" and opts.dig(data))
            if not allowed then
                -- Wait in case it's a player or gravel still settling.
                if os.clock() > deadline then
                    return false, "blocked by " .. data.name
                end
                sleep(0.5)
            elseif not turtle[s.dig]() then
                return false, "can't dig " .. data.name
            else
                digs = digs + 1
                -- Gravel and sand can keep falling into the gap.
                if digs > 64 then return false, "too much falling gravel" end
            end
        else
            -- Nothing solid: a mob or player is in the way.
            turtle[s.attack]()
            if os.clock() > deadline then
                return false, "blocked by an entity"
            end
            sleep(0.3)
        end
    end
    if side == "up" then
        pos.y = pos.y + 1
    elseif side == "down" then
        pos.y = pos.y - 1
    else
        pos.x = pos.x + DX[pos.f]
        pos.z = pos.z + DZ[pos.f]
    end
    save()
    return true
end

function nav.forward(opts) return step("forward", opts) end
function nav.up(opts) return step("up", opts) end
function nav.down(opts) return step("down", opts) end

-- Walk to (x, y, z), one axis at a time in `order` (default "yxz").
-- The order matters: it's how jobs keep the path inside a tunnel or above a
-- field. Returns true, or false and a reason.
function nav.goTo(x, y, z, order, opts)
    order = order or "yxz"
    for axis in order:gmatch(".") do
        if axis == "y" then
            while pos.y < y do
                local ok, err = nav.up(opts)
                if not ok then return false, err end
            end
            while pos.y > y do
                local ok, err = nav.down(opts)
                if not ok then return false, err end
            end
        elseif axis == "x" and pos.x ~= x then
            nav.face(pos.x < x and 1 or 3)
            while pos.x ~= x do
                local ok, err = nav.forward(opts)
                if not ok then return false, err end
            end
        elseif axis == "z" and pos.z ~= z then
            nav.face(pos.z < z and 0 or 2)
            while pos.z ~= z do
                local ok, err = nav.forward(opts)
                if not ok then return false, err end
            end
        end
    end
    return true
end

return nav
