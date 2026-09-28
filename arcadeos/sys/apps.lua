-- App registry: reads <root>/apps/<id>/app.lua manifests.
local apps = {}

apps.GROUPS = { "Accessories", "Games", "Media", "Turtle", "System" }

local function loadManifest(dir, id)
    local path = fs.combine(dir, "app.lua")
    local fn, err = loadfile(path, nil, { colors = colors, colours = colours })
    if not fn then return nil, err end
    local ok, m = pcall(fn)
    if not ok or type(m) ~= "table" then return nil, ok and "manifest must return a table" or m end
    m.id = id
    m.name = m.name or id
    m.group = m.group or "Accessories"
    m.icon = m.icon or m.name:sub(1, 3):upper()
    m.display = m.display or "tile"
    m.args = m.args or {}
    m.requires = m.requires or {}
    local entry = m.entry or "main.lua"
    if entry:sub(1, 1) ~= "/" then entry = "/" .. fs.combine(dir, entry) end
    m.entry = entry
    m.dir = "/" .. dir
    return m
end

-- env: { turtle = bool, color = bool } lets tests fake the hardware.
function apps.scan(root, env)
    env = env or {}
    local hasTurtle = env.turtle
    if hasTurtle == nil then hasTurtle = turtle ~= nil end
    local list, errors = {}, {}
    local base = fs.combine(root, "apps")
    if not fs.isDir(base) then return list, errors end
    for _, id in ipairs(fs.list(base)) do
        local dir = fs.combine(base, id)
        if fs.isDir(dir) and fs.exists(fs.combine(dir, "app.lua")) then
            local m, err = loadManifest(dir, id)
            if m then
                if not (m.requires.turtle and not hasTurtle) then
                    list[#list + 1] = m
                end
            else
                errors[#errors + 1] = id .. ": " .. tostring(err)
            end
        end
    end
    local order = {}
    for i, g in ipairs(apps.GROUPS) do order[g] = i end
    table.sort(list, function(a, b)
        local ga, gb = order[a.group] or 99, order[b.group] or 99
        if ga ~= gb then return ga < gb end
        return a.name:lower() < b.name:lower()
    end)
    return list, errors
end

-- Returns nil if the app can run, or a human-readable reason.
function apps.missing(m, env)
    env = env or {}
    local req = m.requires or {}
    local isColor = env.color
    if isColor == nil then isColor = term.isColor() end
    if req.color and not isColor then
        return m.name .. " requires an Advanced Computer (color display)."
    end
    if req.speaker then
        local has = env.speaker
        if has == nil then has = peripheral.find("speaker") ~= nil end
        if not has then return m.name .. " requires a speaker. Attach one and try again." end
    end
    if req.http and not http then
        return m.name .. " requires the HTTP API to be enabled."
    end
    if req.turtle and not turtle then
        return m.name .. " only runs on a turtle."
    end
    return nil
end

function apps.find(list, id)
    for _, m in ipairs(list) do
        if m.id == id then return m end
    end
end

function apps.forExtension(list, ext)
    ext = ext:lower()
    for _, m in ipairs(list) do
        for _, e in ipairs(m.opens or {}) do
            if e == ext then return m end
        end
    end
end

return apps
