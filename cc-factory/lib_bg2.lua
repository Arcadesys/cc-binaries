--[[
Building Gadgets 2 templates for CC:Tweaked turtles.
A template is the JSON that BG2's Template Manager copies and pastes:
  { "name": ..., "statePosArrayList": "<SNBT>", "requiredItems": { ... } }
statePosArrayList is SNBT for
  { blockstatemap: [ {Name:"ns:id", Properties:{k:"v"}}, ... ],
    startpos: {X,Y,Z}, endpos: {X,Y,Z}, statelist: [I; ...] }
statelist holds one blockstatemap index per cell of the box from startpos to
endpos, air included, walked x fastest, then y, then z
(BlockPos.betweenClosedStream order). Positions come out relative to the
box's corner, so 0,0,0 is the template's minimum corner.
--]]

---@diagnostic disable: undefined-global

local bg2 = {}

local AIR = {
    ["minecraft:air"] = true,
    ["minecraft:cave_air"] = true,
    ["minecraft:void_air"] = true,
}

-- SNBT reader ---------------------------------------------------------------
-- Typed arrays ([B;..], [I;..], [L;..]) are returned as spans of the source
-- text rather than tables: a template's statelist has one entry per cell and
-- can run to hundreds of thousands of numbers.

local function skipSpace(s, i)
    return s:find("[^%s]", i) or (#s + 1)
end

local function fail(s, i, what)
    return nil, string.format("bg2_snbt:%s at %d", what, i)
end

local readValue

local function readQuoted(s, i)
    local quote = s:sub(i, i)
    local out = {}
    local j = i + 1
    while j <= #s do
        local c = s:sub(j, j)
        if c == "\\" then
            out[#out + 1] = s:sub(j + 1, j + 1)
            j = j + 2
        elseif c == quote then
            return table.concat(out), j + 1
        else
            local k = s:find("[\\" .. quote .. "]", j)
            if not k then
                break
            end
            out[#out + 1] = s:sub(j, k - 1)
            j = k
        end
    end
    return fail(s, i, "unterminated_string")
end

local function readBare(s, i)
    local word = s:match("^[%w_%-%.%+]+", i)
    if not word then
        return fail(s, i, "unexpected_character")
    end
    local nextIndex = i + #word
    local digits = word:match("^([%-%+]?%d*%.?%d+)[bBsSlLfFdD]?$")
    if digits then
        return tonumber(digits), nextIndex
    end
    if word == "true" then
        return true, nextIndex
    end
    if word == "false" then
        return false, nextIndex
    end
    return word, nextIndex
end

local function readCompound(s, i)
    local out = {}
    i = skipSpace(s, i + 1)
    if s:sub(i, i) == "}" then
        return out, i + 1
    end
    while true do
        local key, err
        local c = s:sub(i, i)
        if c == '"' or c == "'" then
            key, i = readQuoted(s, i)
        else
            key, i = readBare(s, i)
            key = key and tostring(key)
        end
        if not key then
            return nil, i
        end
        i = skipSpace(s, i)
        if s:sub(i, i) ~= ":" then
            return fail(s, i, "expected_colon")
        end
        local value
        value, err = readValue(s, skipSpace(s, i + 1))
        if value == nil then
            return nil, err
        end
        out[key] = value
        i = skipSpace(s, err)
        c = s:sub(i, i)
        if c == "}" then
            return out, i + 1
        end
        if c ~= "," then
            return fail(s, i, "expected_comma_or_brace")
        end
        i = skipSpace(s, i + 1)
    end
end

local function readList(s, i)
    local kind = s:match("^%[%s*([BIL])%s*;", i)
    if kind then
        local from = s:find(";", i, true) + 1
        local close = s:find("]", from, true)
        if not close then
            return fail(s, i, "unterminated_array")
        end
        return { typedArray = kind, text = s, from = from, to = close - 1 }, close + 1
    end
    local out = {}
    i = skipSpace(s, i + 1)
    if s:sub(i, i) == "]" then
        return out, i + 1
    end
    while true do
        local value, nextIndex = readValue(s, i)
        if value == nil then
            return nil, nextIndex
        end
        out[#out + 1] = value
        i = skipSpace(s, nextIndex)
        local c = s:sub(i, i)
        if c == "]" then
            return out, i + 1
        end
        if c ~= "," then
            return fail(s, i, "expected_comma_or_bracket")
        end
        i = skipSpace(s, i + 1)
    end
end

readValue = function(s, i)
    local c = s:sub(i, i)
    if c == "{" then
        return readCompound(s, i)
    end
    if c == "[" then
        return readList(s, i)
    end
    if c == '"' or c == "'" then
        return readQuoted(s, i)
    end
    return readBare(s, i)
end

--- Parse SNBT text. Typed arrays come back as spans; read them with bg2.eachNumber.
function bg2.readSnbt(text)
    if type(text) ~= "string" then
        return nil, "bg2_snbt:not_a_string"
    end
    local value, nextIndex = readValue(text, skipSpace(text, 1))
    if value == nil then
        return nil, nextIndex
    end
    return value
end

--- Call fn(n) for each number in a typed array span (or plain list).
function bg2.eachNumber(array, fn)
    if type(array) ~= "table" then
        return
    end
    if array.typedArray then
        for n in array.text:sub(array.from, array.to):gmatch("[%-%+]?%d+") do
            fn(tonumber(n))
        end
    else
        for _, n in ipairs(array) do
            fn(n)
        end
    end
end

-- Templates -----------------------------------------------------------------

--- Is this decoded JSON a BG2 template?
function bg2.isTemplate(obj)
    return type(obj) == "table" and type(obj.statePosArrayList) == "string"
end

local function toEntry(state)
    if type(state) ~= "table" or type(state.Name) ~= "string" or AIR[state.Name] then
        return false
    end
    local meta = {}
    if type(state.Properties) == "table" and next(state.Properties) ~= nil then
        meta.state = state.Properties
    end
    return { material = state.Name, meta = meta }
end

local function axis(pos, key)
    return type(pos) == "table" and tonumber(pos[key]) or nil
end

-- Long loops must yield or CC:Tweaked stops the program ("Too long without yielding").
local function pause()
    if os and os.queueEvent and os.pullEvent then
        os.queueEvent("bg2_parse")
        os.pullEvent("bg2_parse")
    end
end

--- Decode a template's statePosArrayList and call addBlock(x, y, z, material, meta)
--- for every block that is not air. Returns true, or false and an error.
function bg2.eachBlock(snbt, addBlock)
    local data, err = bg2.readSnbt(snbt)
    if not data then
        return false, err
    end
    if type(data) ~= "table" or type(data.blockstatemap) ~= "table" or type(data.statelist) ~= "table" then
        return false, "bg2_missing_fields"
    end
    local sx0, sy0, sz0 = axis(data.startpos, "X"), axis(data.startpos, "Y"), axis(data.startpos, "Z")
    local ex, ey, ez = axis(data.endpos, "X"), axis(data.endpos, "Y"), axis(data.endpos, "Z")
    if not (sx0 and sy0 and sz0 and ex and ey and ez) then
        return false, "bg2_missing_bounds"
    end
    local sizeX = math.abs(ex - sx0) + 1
    local sizeY = math.abs(ey - sy0) + 1
    local sizeZ = math.abs(ez - sz0) + 1
    local palette = {}
    for i, state in ipairs(data.blockstatemap) do
        palette[i - 1] = toEntry(state)
    end

    local x, y, z, cells = 0, 0, 0, 0
    local problem = nil
    bg2.eachNumber(data.statelist, function(index)
        if problem then
            return
        end
        if z >= sizeZ then
            problem = "bg2_statelist_too_long"
            return
        end
        local entry = palette[index]
        if entry == nil then
            problem = "bg2_unknown_state:" .. tostring(index)
            return
        end
        if entry then
            local ok, addErr = addBlock(x, y, z, entry.material, entry.meta)
            if not ok then
                problem = addErr or "bg2_add_failed"
                return
            end
        end
        cells = cells + 1
        if cells % 4096 == 0 then
            pause()
        end
        x = x + 1
        if x == sizeX then
            x = 0
            y = y + 1
            if y == sizeY then
                y = 0
                z = z + 1
            end
        end
    end)
    if problem then
        return false, problem
    end
    if cells ~= sizeX * sizeY * sizeZ then
        return false, string.format("bg2_statelist_size:%d of %d cells", cells, sizeX * sizeY * sizeZ)
    end
    return true
end

return bg2
