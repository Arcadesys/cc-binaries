-- input.lua
-- Input handling for Arcade OS

local config = {
    LEFT = { type = "key", value = keys.left },
    CENTER = { type = "key", value = keys.up },
    RIGHT = { type = "key", value = keys.right }
}

-- Load config if exists
if fs.exists(".button_config") then
    local file = fs.open(".button_config", "r")
    if file then
        local data = file.readAll()
        file.close()
        local loaded = textutils.unserialize(data)
        if loaded then
            config = loaded
        end
    end
end

-- Also support default keys for keyboard fallback
local DEFAULT_KEYS = {
    LEFT = { keys.left, keys.a, keys.q },
    CENTER = { keys.up, keys.w, keys.space, keys.enter },
    RIGHT = { keys.right, keys.d, keys.e }
}

local function isKey(key, set)
    for _, k in ipairs(set) do
        if key == k then return true end
    end
    return false
end

-- Track last-known redstone states so we can detect which button was pressed
-- on the rising edge (helps when multiple inputs are momentarily high).
local lastRedstone = {
    LEFT = false,
    CENTER = false,
    RIGHT = false
}

local function getButton(event, p1)
    if event == "key" then
        -- Check configured keys
        if config.LEFT.type == "key" and p1 == config.LEFT.value then return "LEFT" end
        if config.CENTER.type == "key" and p1 == config.CENTER.value then return "CENTER" end
        if config.RIGHT.type == "key" and p1 == config.RIGHT.value then return "RIGHT" end
        
        -- Check default keys (fallback/keyboard support)
        if isKey(p1, DEFAULT_KEYS.LEFT) then return "LEFT" end
        if isKey(p1, DEFAULT_KEYS.CENTER) then return "CENTER" end
        if isKey(p1, DEFAULT_KEYS.RIGHT) then return "RIGHT" end

    elseif event == "char" then
        -- Numeric keyboard fallback matching on-screen prompts
        local c = tostring(p1 or "")
        if c == "1" then return "LEFT" end
        if c == "2" then return "CENTER" end
        if c == "3" then return "RIGHT" end
        
    elseif event == "redstone" then
        -- Prefer configured redstone using rising-edge detection.
        local states = {
            LEFT = (config.LEFT.type == "redstone") and redstone.getInput(config.LEFT.value) or false,
            CENTER = (config.CENTER.type == "redstone") and redstone.getInput(config.CENTER.value) or false,
            RIGHT = (config.RIGHT.type == "redstone") and redstone.getInput(config.RIGHT.value) or false
        }

        local candidates = {}
        for name, now in pairs(states) do
            if now and not lastRedstone[name] then
                table.insert(candidates, name)
            end
        end

        -- Update memory before returning
        lastRedstone.LEFT = states.LEFT
        lastRedstone.CENTER = states.CENTER
        lastRedstone.RIGHT = states.RIGHT

        if #candidates == 1 then
            return candidates[1]
        end
        if #candidates > 1 then
            -- Ambiguous press (multiple lines rose at once). Ignore.
            return nil
        end
        
        -- Default redstone fallback (Legacy support)
        -- Only check if NOT configured as redstone to avoid double counting if config matches default
        if config.LEFT.type ~= "redstone" and redstone.getInput("left") then return "LEFT" end
        if config.RIGHT.type ~= "redstone" and redstone.getInput("right") then return "RIGHT" end
        if config.CENTER.type ~= "redstone" and (redstone.getInput("top") or redstone.getInput("front")) then return "CENTER" end
    end
    return nil
end

return {
    getButton = getButton
}
