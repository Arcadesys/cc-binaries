-- ArcadeOS Setup
--   wget run https://raw.githubusercontent.com/Arcadesys/cc-binaries/main/arcadeos/install.lua
-- Options:
--   --yes           install the default selection without asking
--   --base URL      download from another raw base (fork or branch)
--   --local DIR     copy from a local checkout instead of downloading
--   --no-startup    don't make ArcadeOS start at boot
local DEFAULT_BASE = "https://raw.githubusercontent.com/Arcadesys/cc-binaries/main"

local args = { ... }
local opts = { base = DEFAULT_BASE }
local i = 1
while i <= #args do
    local a = args[i]
    if a == "--yes" then opts.yes = true
    elseif a == "--no-startup" then opts.noStartup = true
    elseif a == "--base" then i = i + 1; opts.base = args[i]
    elseif a == "--local" then i = i + 1; opts.localDir = args[i]
    end
    i = i + 1
end

local isColor = term.isColor()
local W, H = term.getSize()
local C = {
    bg = isColor and colors.white or colors.black,
    fg = isColor and colors.black or colors.white,
    bar = isColor and colors.blue or colors.white,
    barFg = isColor and colors.white or colors.black,
    dim = isColor and colors.gray or colors.white,
    sel = isColor and colors.black or colors.white,
    selFg = isColor and colors.white or colors.black,
}

local function header(title)
    term.setBackgroundColor(C.bg)
    term.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(C.bar)
    term.setTextColor(C.barFg)
    term.clearLine()
    term.setCursorPos(math.max(1, math.floor((W - #title) / 2) + 1), 1)
    term.write(title)
    term.setBackgroundColor(C.bg)
    term.setTextColor(C.fg)
end

local function at(x, y, s, fg, bg)
    term.setCursorPos(x, y)
    if fg then term.setTextColor(fg) end
    if bg then term.setBackgroundColor(bg) end
    term.write(s)
end

local function fail(msg)
    header("ArcadeOS Setup")
    at(2, 3, "Setup cannot continue:", C.fg, C.bg)
    term.setCursorPos(2, 5)
    print(msg)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    error("setup failed", 0)
end

--------------------------------------------------------------------------
-- Fetching

local function readSource(rel)
    if opts.localDir then
        local p = fs.combine(opts.localDir, rel)
        if not fs.exists(p) then return nil, "missing " .. p end
        local h = fs.open(p, "rb")
        local data = h.readAll()
        h.close()
        return data
    end
    if not http then return nil, "The HTTP API is disabled on this server." end
    local url = opts.base .. "/" .. rel
    local h, err = http.get(url, nil, true)
    if not h then return nil, (err or "request failed") .. ": " .. url end
    local data = h.readAll()
    h.close()
    return data
end

local listing, err = readSource("arcadeos/files.json")
if not listing then fail(err) end
local manifest = textutils.unserializeJSON(listing)
if not manifest or not manifest.packages then fail("files.json is not valid.") end

local ORDER = { "core", "arcade", "factory", "pine", "media", "turtle" }
local packages = {}
for _, name in ipairs(ORDER) do
    local p = manifest.packages[name]
    if p then
        p.name = name
        packages[#packages + 1] = p
    end
end
for name, p in pairs(manifest.packages) do
    if not p.name then p.name = name; packages[#packages + 1] = p end
end

local isTurtle = turtle ~= nil
local free = fs.getFreeSpace("/")

local function selectedSize()
    local seen, n = {}, 0
    for _, p in ipairs(packages) do
        if p.selected then
            for _, f in ipairs(p.files) do
                if not seen[f.dest] then
                    seen[f.dest] = true
                    n = n + f.size
                    if fs.exists(f.dest) and not fs.isDir(f.dest) then n = n - fs.getSize(f.dest) end
                end
            end
        end
    end
    return n
end

local budget = free
for _, p in ipairs(packages) do
    if p.required then
        p.selected = true
    elseif p.turtle then
        p.selected = isTurtle
    else
        p.selected = true
    end
end
-- Drop optional packages (largest first) until the default selection fits.
do
    local optional = {}
    for _, p in ipairs(packages) do
        if p.selected and not p.required then optional[#optional + 1] = p end
    end
    table.sort(optional, function(a, b) return a.size > b.size end)
    for _, p in ipairs(optional) do
        if selectedSize() <= budget then break end
        p.selected = false
    end
end

--------------------------------------------------------------------------
-- Package picker

local function kb(n) return ("%dK"):format(math.ceil(n / 1024)) end

local function pick()
    local sel = 1
    while true do
        header("ArcadeOS Setup")
        at(2, 3, "Choose what to install:", C.fg, C.bg)
        for idx, p in ipairs(packages) do
            local y = 4 + idx
            local box = p.selected and "[x]" or "[ ]"
            local hi = idx == sel
            local line = (" %s %-8s %6s  %s"):format(box, p.name, kb(p.size), p.description or "")
            if #line > W - 2 then line = line:sub(1, W - 2) end
            at(2, y, line .. (" "):rep(W - 2 - #line), hi and C.selFg or C.fg, hi and C.sel or C.bg)
        end
        local need, y = selectedSize(), #packages + 6
        at(2, y, ("Needs %s of %s free."):format(kb(math.max(0, need)), kb(free)),
            need > free and (isColor and colors.red or C.fg) or C.fg, C.bg)
        at(2, H - 1, "Up/Down select  Space toggle", C.dim, C.bg)
        at(2, H, "Enter install   Q quit", C.dim, C.bg)
        local ev, a, b, c = os.pullEvent()
        if ev == "key" then
            if a == keys.up then sel = math.max(1, sel - 1)
            elseif a == keys.down then sel = math.min(#packages, sel + 1)
            elseif a == keys.space and not packages[sel].required then packages[sel].selected = not packages[sel].selected
            elseif a == keys.enter then
                if selectedSize() <= free then return true end
            elseif a == keys.q then return false
            end
        elseif ev == "mouse_click" then
            local idx = c - 4
            if packages[idx] then
                sel = idx
                if not packages[idx].required then packages[idx].selected = not packages[idx].selected end
            end
        end
    end
end

if not opts.yes then
    if not pick() then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        term.setCursorPos(1, 1)
        print("Setup cancelled.")
        return
    end
end
if selectedSize() > free then fail("Not enough disk space for the selected packages.") end

--------------------------------------------------------------------------
-- Install

local queue, seen = {}, {}
for _, p in ipairs(packages) do
    if p.selected then
        for _, f in ipairs(p.files) do
            if not seen[f.dest] then seen[f.dest] = true; queue[#queue + 1] = f end
        end
    end
end

header("ArcadeOS Setup")
at(2, 3, "Installing ArcadeOS...", C.fg, C.bg)
local barW = W - 4
for n, f in ipairs(queue) do
    at(2, 5, (" "):rep(W - 2), C.fg, C.bg)
    at(2, 5, f.dest:sub(1, W - 2), C.dim, C.bg)
    local filled = math.floor(barW * n / #queue)
    at(2, 7, (" "):rep(filled), C.fg, C.bar)
    at(2 + filled, 7, (" "):rep(barW - filled), C.fg, isColor and colors.lightGray or C.bg)
    local data, e = readSource(f.src)
    if not data then fail(e) end
    fs.makeDir(fs.getDir(f.dest))
    local h = fs.open(f.dest, "wb")
    if not h then fail("Cannot write " .. f.dest) end
    h.write(data)
    h.close()
end

for _, dir in ipairs({ "/home", "/midi" }) do
    if not fs.exists(dir) then fs.makeDir(dir) end
end

local STARTUP = 'shell.run("/arcadeos/boot.lua")\n'
if not opts.noStartup then
    if fs.exists("/startup.lua") then
        local h = fs.open("/startup.lua", "r")
        local old = h.readAll()
        h.close()
        if old ~= STARTUP and not fs.exists("/startup.lua.bak") then fs.move("/startup.lua", "/startup.lua.bak") end
        if fs.exists("/startup.lua") then fs.delete("/startup.lua") end
    end
    local h = fs.open("/startup.lua", "w")
    h.write(STARTUP)
    h.close()
end

header("ArcadeOS Setup")
at(2, 3, ("Installed %d files."):format(#queue), C.fg, C.bg)
if fs.exists("/startup.lua.bak") then at(2, 5, "Your old startup.lua is saved as startup.lua.bak.", C.fg, C.bg) end
if opts.yes then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.setCursorPos(1, H)
    return
end
at(2, 7, "Press any key to start ArcadeOS.", C.fg, C.bg)
os.pullEvent("key")
shell.run("/arcadeos/boot.lua")
