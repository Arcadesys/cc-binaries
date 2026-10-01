--[[
Strategy generator for branch mining.
Produces a linear list of steps for the turtle to execute without moving the turtle at generation time.
]]

local strategy = {}

local function normalizePositiveInt(value, default)
    local numberValue = tonumber(value)
    if not numberValue or numberValue < 1 then
        return default
    end
    return math.floor(numberValue)
end

local function pushStep(steps, x, y, z, facing, stepType, data)
    steps[#steps + 1] = {
        type = stepType,
        x = x,
        y = y,
        z = z,
        facing = facing,
        data = data,
    }
end

local function forward(x, z, facing)
    if facing == 0 then
        z = z + 1
    elseif facing == 1 then
        x = x + 1
    elseif facing == 2 then
        z = z - 1
    else
        x = x - 1
    end
    return x, z
end

local function turnLeft(facing)
    return (facing + 3) % 4
end

local function turnRight(facing)
    return (facing + 1) % 4
end

--- Generate a branch mining strategy
---@param length number Length of the main spine
---@param branchInterval number Distance between branches
---@param branchLength number Length of each branch
---@param torchInterval number Distance between torches on spine
---@return table
function strategy.generate(length, branchInterval, branchLength, torchInterval)
    length = normalizePositiveInt(length, 60)
    branchInterval = normalizePositiveInt(branchInterval, 3)
    branchLength = normalizePositiveInt(branchLength, 16)
    torchInterval = normalizePositiveInt(torchInterval, 6)

    local steps = {}
    local x, y, z = 0, 0, 0
    local facing = 0 -- 0: forward, 1: right, 2: back, 3: left

    -- The spine is two blocks tall: clear the block above each spine cell
    -- before scanning, so ore up there is taken rather than refilled.
    pushStep(steps, x, y, z, facing, "dig_up")
    pushStep(steps, x, y, z, facing, "mine_neighbors")

    for i = 1, length do
        x, z = forward(x, z, facing)
        pushStep(steps, x, y, z, facing, "move")
        pushStep(steps, x, y, z, facing, "dig_up")
        pushStep(steps, x, y, z, facing, "mine_neighbors")

        if i % branchInterval == 0 then
            -- Left branch
            facing = turnLeft(facing)
            pushStep(steps, x, y, z, facing, "turn", "left")
            for _ = 1, branchLength do
                x, z = forward(x, z, facing)
                pushStep(steps, x, y, z, facing, "move")
                pushStep(steps, x, y, z, facing, "mine_neighbors")
            end

            -- Go UP
            y = y + 1
            pushStep(steps, x, y, z, facing, "move")
            pushStep(steps, x, y, z, facing, "mine_neighbors")

            -- Turn around and return to spine
            facing = turnRight(facing)
            pushStep(steps, x, y, z, facing, "turn", "right")
            facing = turnRight(facing)
            pushStep(steps, x, y, z, facing, "turn", "right")
            for _ = 1, branchLength do
                x, z = forward(x, z, facing)
                pushStep(steps, x, y, z, facing, "move")
                pushStep(steps, x, y, z, facing, "mine_neighbors")
            end

            -- Go DOWN
            y = y - 1
            pushStep(steps, x, y, z, facing, "move")

            -- Right branch (mirror of left). Coming back from the left branch
            -- the turtle already faces right, so it heads straight out.
            for _ = 1, branchLength do
                x, z = forward(x, z, facing)
                pushStep(steps, x, y, z, facing, "move")
                pushStep(steps, x, y, z, facing, "mine_neighbors")
            end

            -- Go UP
            y = y + 1
            pushStep(steps, x, y, z, facing, "move")
            pushStep(steps, x, y, z, facing, "mine_neighbors")

            facing = turnRight(facing)
            pushStep(steps, x, y, z, facing, "turn", "right")
            facing = turnRight(facing)
            pushStep(steps, x, y, z, facing, "turn", "right")
            for _ = 1, branchLength do
                x, z = forward(x, z, facing)
                pushStep(steps, x, y, z, facing, "move")
                pushStep(steps, x, y, z, facing, "mine_neighbors")
            end

            -- Go DOWN
            y = y - 1
            pushStep(steps, x, y, z, facing, "move")

            -- Back from the right branch facing left; face down the spine.
            facing = turnRight(facing)
            pushStep(steps, x, y, z, facing, "turn", "right")
        end

        -- After any branches: a branch returns through the upper spine cell,
        -- which is where the torch goes, and would dig it back up.
        if i % torchInterval == 0 then
            pushStep(steps, x, y, z, facing, "place_torch")
        end

        if i % 5 == 0 then
            pushStep(steps, x, y, z, facing, "dump_trash")
        end
    end

    -- Return to origin
    facing = turnRight(facing)
    pushStep(steps, x, y, z, facing, "turn", "right")
    facing = turnRight(facing)
    pushStep(steps, x, y, z, facing, "turn", "right")
    for _ = 1, length do
        x, z = forward(x, z, facing)
        pushStep(steps, x, y, z, facing, "move")
    end
    facing = turnRight(facing)
    pushStep(steps, x, y, z, facing, "turn", "right")
    facing = turnRight(facing)
    pushStep(steps, x, y, z, facing, "turn", "right")

    pushStep(steps, x, y, z, facing, "done")

    return steps
end

return strategy
