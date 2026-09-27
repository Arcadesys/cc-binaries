-- idlecraft.lua
-- Minecraft Incremental Idle Game (Free to Play!)
-- Hire Steves, install mods, and make number go up!

local w, h = term.getSize()
local cx, cy = math.floor(w / 2), math.floor(h / 2)

local input = require("input")
local audio = require("audio")

local function refreshSize()
    w, h = term.getSize()
    cx, cy = math.floor(w / 2), math.floor(h / 2)
end

--------------------------------------------------------------------------------
-- UI PRIMITIVES
--------------------------------------------------------------------------------

local HAS_BLIT = type(term.blit) == "function" and type(colors) == "table" and type(colors.toBlit) == "function"

local function toBlit(c)
    if not HAS_BLIT then return "0" end
    return colors.toBlit(c)
end

local function fillRect(x, y, width, height, bg, fg, ch)
    if width <= 0 or height <= 0 then return end
    ch = ch or " "
    bg = bg or colors.black
    fg = fg or colors.white

    if HAS_BLIT then
        local text = string.rep(ch, width)
        local fgs = string.rep(toBlit(fg), width)
        local bgs = string.rep(toBlit(bg), width)
        for row = 0, height - 1 do
            term.setCursorPos(x, y + row)
            term.blit(text, fgs, bgs)
        end
    else
        term.setBackgroundColor(bg)
        term.setTextColor(fg)
        for row = 0, height - 1 do
            term.setCursorPos(x, y + row)
            term.write(string.rep(ch, width))
        end
    end
end

local function writeAt(x, y, text, fg, bg)
    if not text or #text == 0 then return end
    term.setCursorPos(x, y)
    if HAS_BLIT and fg and bg then
        term.blit(text, string.rep(toBlit(fg), #text), string.rep(toBlit(bg), #text))
        return
    end
    if bg then term.setBackgroundColor(bg) end
    if fg then term.setTextColor(fg) end
    term.write(text)
end

local function centerText(x, y, width, text, fg, bg)
    local tx = x + math.floor((width - #text) / 2)
    writeAt(tx, y, text, fg, bg)
end

local function drawTitleBar(title, rightText)
    local w2, _ = term.getSize()
    fillRect(1, 1, w2, 1, colors.green)
    writeAt(2, 1, title, colors.white, colors.green)
    if rightText then
        writeAt(math.max(1, w2 - #rightText), 1, rightText, colors.lime, colors.green)
    end
end

local function drawButtonBar(leftText, centerTextLabel, rightText)
    local w2, h2 = term.getSize()
    local colW = math.floor(w2 / 3)
    local leftW = colW
    local midW = colW
    local rightW = w2 - (colW * 2)

    local function fit(text, width)
        text = text or ""
        if width <= 0 then return "" end
        if #text > width then return text:sub(1, width) end
        return text
    end

    fillRect(1, h2, leftW, 1, colors.red)
    fillRect(leftW + 1, h2, midW, 1, colors.yellow)
    fillRect(leftW + midW + 1, h2, rightW, 1, colors.blue)

    centerText(1, h2, leftW, fit(leftText, leftW), colors.white, colors.red)
    centerText(leftW + 1, h2, midW, fit(centerTextLabel, midW), colors.black, colors.yellow)
    centerText(leftW + midW + 1, h2, rightW, fit(rightText, rightW), colors.white, colors.blue)
end

--------------------------------------------------------------------------------
-- GAME STATE
--------------------------------------------------------------------------------

local state = {
    -- Resources
    blocks = 0,           -- Main currency
    diamonds = 0,         -- Premium currency (earned through gameplay)
    
    -- Workers
    steves = 0,           -- Basic miners
    alexes = 0,           -- Better miners
    golems = 0,           -- Iron golems (super miners)
    
    -- Buildings
    mines = 0,            -- Passive block gen
    villages = 0,         -- Generate steves
    forges = 0,           -- Boost multiplier
    
    -- Mods installed (upgrades)
    mods = {
        efficiency = 0,   -- Click multiplier
        fortune = 0,      -- Chance for bonus
        haste = 0,        -- Worker speed boost
        mending = 0,      -- Auto-repair (passive gen)
        unbreaking = 0,   -- Cost reduction
    },
    
    -- Stats
    totalBlocks = 0,
    totalClicks = 0,
    prestigeCount = 0,
    prestigeBonus = 1,    -- Multiplier from prestige
    
    -- Time tracking
    lastTick = 0,
}

-- Save file path
local SAVE_FILE = ".idlecraft_save"

--------------------------------------------------------------------------------
-- GAME CONSTANTS
--------------------------------------------------------------------------------

local COSTS = {
    steve = 15,
    alex = 100,
    golem = 1000,
    mine = 50,
    village = 500,
    forge = 2500,
}

local MOD_COSTS = {
    efficiency = 25,
    fortune = 75,
    haste = 150,
    mending = 300,
    unbreaking = 500,
}

local MOD_NAMES = {
    efficiency = "Efficiency",
    fortune = "Fortune",
    haste = "Haste",
    mending = "Mending",
    unbreaking = "Unbreaking",
}

local MOD_ICONS = {
    efficiency = "\4",  -- Diamond
    fortune = "\7",     -- Bullet
    haste = ">>",
    mending = "+",
    unbreaking = "#",
}

--------------------------------------------------------------------------------
-- SAVE/LOAD
--------------------------------------------------------------------------------

local function saveGame()
    local f = fs.open(SAVE_FILE, "w")
    if f then
        f.write(textutils.serialize(state))
        f.close()
    end
end

local function loadGame()
    if fs.exists(SAVE_FILE) then
        local f = fs.open(SAVE_FILE, "r")
        if f then
            local data = f.readAll()
            f.close()
            local loaded = textutils.unserialize(data)
            if loaded then
                -- Merge with defaults (for new fields)
                for k, v in pairs(loaded) do
                    if type(v) == "table" and type(state[k]) == "table" then
                        for k2, v2 in pairs(v) do
                            state[k][k2] = v2
                        end
                    else
                        state[k] = v
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- GAME MECHANICS
--------------------------------------------------------------------------------

local function formatNumber(n)
    if n >= 1e12 then return string.format("%.2fT", n / 1e12)
    elseif n >= 1e9 then return string.format("%.2fB", n / 1e9)
    elseif n >= 1e6 then return string.format("%.2fM", n / 1e6)
    elseif n >= 1e3 then return string.format("%.2fK", n / 1e3)
    else return tostring(math.floor(n))
    end
end

local function getClickPower()
    local base = 1
    local effBonus = 1 + (state.mods.efficiency * 0.5)
    local forgeBonus = 1 + (state.forges * 0.25)
    return math.floor(base * effBonus * forgeBonus * state.prestigeBonus)
end

local function getBlocksPerSecond()
    local bps = 0
    
    -- Workers
    local hasteBonus = 1 + (state.mods.haste * 0.2)
    bps = bps + (state.steves * 1 * hasteBonus)
    bps = bps + (state.alexes * 5 * hasteBonus)
    bps = bps + (state.golems * 25 * hasteBonus)
    
    -- Buildings
    bps = bps + (state.mines * 2)
    
    -- Mending mod (passive)
    bps = bps + (state.mods.mending * 0.5)
    
    -- Forge bonus
    local forgeBonus = 1 + (state.forges * 0.25)
    bps = bps * forgeBonus
    
    -- Prestige bonus
    bps = bps * state.prestigeBonus
    
    return bps
end

local function getCost(baseCost, owned)
    local cost = baseCost * math.pow(1.15, owned)
    local reduction = 1 - (state.mods.unbreaking * 0.05)
    reduction = math.max(0.5, reduction)
    return math.floor(cost * reduction)
end

local function getModCost(modName)
    local level = state.mods[modName] or 0
    local base = MOD_COSTS[modName] or 100
    return math.floor(base * math.pow(2, level))
end

local function doClick()
    local power = getClickPower()
    
    -- Fortune chance for bonus
    if state.mods.fortune > 0 then
        local chance = state.mods.fortune * 0.1
        if math.random() < chance then
            power = power * 2
        end
    end
    
    state.blocks = state.blocks + power
    state.totalBlocks = state.totalBlocks + power
    state.totalClicks = state.totalClicks + 1
    
    -- Small chance for diamond on click
    if math.random() < 0.01 then
        state.diamonds = state.diamonds + 1
    end
    
    audio.play("click")
    return power
end

local function doTick(dt)
    local bps = getBlocksPerSecond()
    local earned = bps * dt
    state.blocks = state.blocks + earned
    state.totalBlocks = state.totalBlocks + earned
    
    -- Villages generate steves slowly
    if state.villages > 0 then
        local steveChance = state.villages * 0.01 * dt
        if math.random() < steveChance then
            state.steves = state.steves + 1
        end
    end
    
    -- Rare diamond from mining
    if bps > 0 and math.random() < 0.001 * dt * (1 + state.mods.fortune * 0.5) then
        state.diamonds = state.diamonds + 1
    end
end

local function canPrestige()
    return state.totalBlocks >= 1e6
end

local function getPrestigeBonus()
    local bonus = math.floor(math.log10(state.totalBlocks + 1) - 5)
    return math.max(1, bonus)
end

local function doPrestige()
    if not canPrestige() then return false end
    
    local bonus = getPrestigeBonus()
    state.prestigeCount = state.prestigeCount + 1
    state.prestigeBonus = state.prestigeBonus + bonus
    
    -- Reset progress but keep diamonds and prestige
    state.blocks = 0
    state.steves = 0
    state.alexes = 0
    state.golems = 0
    state.mines = 0
    state.villages = 0
    state.forges = 0
    state.totalBlocks = 0
    state.totalClicks = 0
    
    -- Keep mods at reduced level
    for mod, level in pairs(state.mods) do
        state.mods[mod] = math.floor(level / 2)
    end
    
    audio.play("win")
    return true
end

--------------------------------------------------------------------------------
-- MENUS
--------------------------------------------------------------------------------

local currentMenu = "main"
local menuSelection = 1

local function drawResourceBar()
    refreshSize()
    local bps = getBlocksPerSecond()
    local rightText = formatNumber(state.blocks) .. " blk"
    if bps > 0 then
        rightText = rightText .. " (+" .. formatNumber(bps) .. "/s)"
    end
    drawTitleBar("IDLECRAFT", rightText)
    
    -- Diamond display
    if state.diamonds > 0 then
        writeAt(2, 2, "\4 " .. state.diamonds, colors.cyan, colors.black)
    end
    
    -- Prestige display
    if state.prestigeBonus > 1 then
        local pText = "x" .. state.prestigeBonus .. " prestige"
        writeAt(w - #pText - 1, 2, pText, colors.purple, colors.black)
    end
end

local function drawMainMenu()
    refreshSize()
    term.setBackgroundColor(colors.black)
    term.clear()
    drawResourceBar()
    
    local startY = 4
    
    -- Mine button (big and centered)
    local mineText = "[ MINE! ]"
    local clickPower = getClickPower()
    writeAt(cx - #mineText/2, startY, mineText, colors.lime, colors.black)
    writeAt(cx - 4, startY + 1, "+" .. clickPower .. " blocks", colors.gray, colors.black)
    
    -- Worker counts
    local y = startY + 3
    writeAt(2, y, "Workers:", colors.yellow, colors.black)
    y = y + 1
    if state.steves > 0 then
        writeAt(2, y, "  Steve x" .. state.steves, colors.white, colors.black)
        y = y + 1
    end
    if state.alexes > 0 then
        writeAt(2, y, "  Alex x" .. state.alexes, colors.orange, colors.black)
        y = y + 1
    end
    if state.golems > 0 then
        writeAt(2, y, "  Golem x" .. state.golems, colors.lightGray, colors.black)
        y = y + 1
    end
    
    -- Building counts
    y = y + 1
    writeAt(2, y, "Buildings:", colors.yellow, colors.black)
    y = y + 1
    if state.mines > 0 then
        writeAt(2, y, "  Mine x" .. state.mines, colors.brown, colors.black)
        y = y + 1
    end
    if state.villages > 0 then
        writeAt(2, y, "  Village x" .. state.villages, colors.green, colors.black)
        y = y + 1
    end
    if state.forges > 0 then
        writeAt(2, y, "  Forge x" .. state.forges, colors.red, colors.black)
        y = y + 1
    end
    
    -- Installed mods
    local modLine = ""
    for mod, level in pairs(state.mods) do
        if level > 0 then
            modLine = modLine .. MOD_ICONS[mod] .. level .. " "
        end
    end
    if #modLine > 0 then
        writeAt(2, h - 2, "Mods: " .. modLine, colors.magenta, colors.black)
    end
    
    drawButtonBar("Shop", "MINE!", "Mods")
end

local shopItems = {
    { name = "Hire Steve", key = "steve", type = "worker" },
    { name = "Hire Alex", key = "alex", type = "worker" },
    { name = "Summon Golem", key = "golem", type = "worker" },
    { name = "Build Mine", key = "mine", type = "building" },
    { name = "Build Village", key = "village", type = "building" },
    { name = "Build Forge", key = "forge", type = "building" },
}

local function getOwned(key)
    if key == "steve" then return state.steves
    elseif key == "alex" then return state.alexes
    elseif key == "golem" then return state.golems
    elseif key == "mine" then return state.mines
    elseif key == "village" then return state.villages
    elseif key == "forge" then return state.forges
    end
    return 0
end

local function buyItem(key)
    local owned = getOwned(key)
    local cost = getCost(COSTS[key], owned)
    
    if state.blocks >= cost then
        state.blocks = state.blocks - cost
        if key == "steve" then state.steves = state.steves + 1
        elseif key == "alex" then state.alexes = state.alexes + 1
        elseif key == "golem" then state.golems = state.golems + 1
        elseif key == "mine" then state.mines = state.mines + 1
        elseif key == "village" then state.villages = state.villages + 1
        elseif key == "forge" then state.forges = state.forges + 1
        end
        audio.play("click")
        return true
    end
    return false
end

local function drawShopMenu()
    refreshSize()
    term.setBackgroundColor(colors.black)
    term.clear()
    drawResourceBar()
    
    writeAt(2, 3, "=== SHOP ===", colors.yellow, colors.black)
    
    local startY = 5
    for i, item in ipairs(shopItems) do
        local y = startY + i - 1
        local owned = getOwned(item.key)
        local cost = getCost(COSTS[item.key], owned)
        local canAfford = state.blocks >= cost
        
        local line = item.name
        local costStr = formatNumber(cost) .. " blk"
        local ownedStr = "(" .. owned .. ")"
        
        if i == menuSelection then
            writeAt(2, y, "> ", colors.lime, colors.black)
            writeAt(4, y, line, canAfford and colors.white or colors.gray, colors.black)
        else
            writeAt(2, y, "  ", colors.white, colors.black)
            writeAt(4, y, line, canAfford and colors.white or colors.gray, colors.black)
        end
        
        writeAt(20, y, costStr, canAfford and colors.lime or colors.red, colors.black)
        writeAt(w - #ownedStr - 1, y, ownedStr, colors.lightGray, colors.black)
    end
    
    -- Description of selected item
    local sel = shopItems[menuSelection]
    local desc = ""
    if sel.key == "steve" then desc = "Basic miner. 1 block/s"
    elseif sel.key == "alex" then desc = "Better miner. 5 blocks/s"
    elseif sel.key == "golem" then desc = "Iron golem. 25 blocks/s"
    elseif sel.key == "mine" then desc = "Passive mining. 2 blocks/s"
    elseif sel.key == "village" then desc = "Slowly spawns Steves!"
    elseif sel.key == "forge" then desc = "Boosts all production 25%"
    end
    writeAt(2, h - 2, desc, colors.gray, colors.black)
    
    drawButtonBar("Back", "Buy", "Next")
end

local modItems = { "efficiency", "fortune", "haste", "mending", "unbreaking" }

local function drawModMenu()
    refreshSize()
    term.setBackgroundColor(colors.black)
    term.clear()
    drawResourceBar()
    
    writeAt(2, 3, "=== MODS ===", colors.magenta, colors.black)
    
    local startY = 5
    for i, modKey in ipairs(modItems) do
        local y = startY + i - 1
        local level = state.mods[modKey] or 0
        local cost = getModCost(modKey)
        local canAfford = state.blocks >= cost
        
        local name = MOD_NAMES[modKey] .. " " .. (level > 0 and tostring(level) or "")
        local costStr = formatNumber(cost) .. " blk"
        
        if i == menuSelection then
            writeAt(2, y, "> ", colors.lime, colors.black)
            writeAt(4, y, name, canAfford and colors.white or colors.gray, colors.black)
        else
            writeAt(2, y, "  ", colors.white, colors.black)
            writeAt(4, y, name, canAfford and colors.white or colors.gray, colors.black)
        end
        
        writeAt(24, y, costStr, canAfford and colors.lime or colors.red, colors.black)
    end
    
    -- Prestige option
    local prestigeY = startY + #modItems + 1
    if canPrestige() then
        local pBonus = getPrestigeBonus()
        writeAt(2, prestigeY, "[ PRESTIGE ]", colors.purple, colors.black)
        writeAt(2, prestigeY + 1, "Reset for +" .. pBonus .. "x bonus!", colors.magenta, colors.black)
    end
    
    -- Description of selected mod
    local desc = ""
    if menuSelection <= #modItems then
        local sel = modItems[menuSelection]
        if sel == "efficiency" then desc = "Click power +50%"
        elseif sel == "fortune" then desc = "Chance for 2x clicks"
        elseif sel == "haste" then desc = "Worker speed +20%"
        elseif sel == "mending" then desc = "Passive +0.5/s"
        elseif sel == "unbreaking" then desc = "Costs -5% (min 50%)"
        end
    end
    writeAt(2, h - 2, desc, colors.gray, colors.black)
    
    drawButtonBar("Back", "Install", "Next")
end

local function buyMod(modKey)
    local cost = getModCost(modKey)
    if state.blocks >= cost then
        state.blocks = state.blocks - cost
        state.mods[modKey] = (state.mods[modKey] or 0) + 1
        audio.play("click")
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- ATTRACT MODE / DEMO
--------------------------------------------------------------------------------

local function drawDemo()
    refreshSize()
    term.setBackgroundColor(colors.black)
    term.clear()
    
    -- Title
    local title = "IDLECRAFT"
    writeAt(cx - #title/2, 3, title, colors.lime, colors.black)
    
    -- Subtitle
    local sub = "Minecraft Incremental"
    writeAt(cx - #sub/2, 4, sub, colors.green, colors.black)
    
    -- Animation: falling blocks
    local blocks = { "\127", "#", "O", "@", "*" }
    for i = 1, 8 do
        local bx = math.random(2, w - 1)
        local by = math.random(6, h - 4)
        local bc = { colors.brown, colors.gray, colors.lightGray, colors.cyan }
        writeAt(bx, by, blocks[math.random(#blocks)], bc[math.random(#bc)], colors.black)
    end
    
    -- Features
    local y = 8
    writeAt(4, y, "\7 Hire Steves & Alexes", colors.white, colors.black)
    writeAt(4, y + 1, "\7 Build Mines & Forges", colors.white, colors.black)
    writeAt(4, y + 2, "\7 Install Enchantment Mods", colors.white, colors.black)
    writeAt(4, y + 3, "\7 Prestige for Bonuses", colors.white, colors.black)
    
    -- Free to play
    writeAt(cx - 7, h - 3, "FREE TO PLAY!", colors.yellow, colors.black)
    
    drawButtonBar("", "Play", "")
end

local function runDemo()
    local demoTimer = os.startTimer(5)
    
    while true do
        drawDemo()
        
        local e, p1 = os.pullEvent()
        
        if e == "timer" and p1 == demoTimer then
            return false  -- Demo ended, go back to menu
        end
        
        local button = input.getButton(e, p1)
        if button then
            return true  -- Player wants to play
        end
    end
end

--------------------------------------------------------------------------------
-- MAIN GAME LOOP
--------------------------------------------------------------------------------

local function waitInput(timeout)
    local timer = timeout and os.startTimer(timeout) or nil
    
    while true do
        local e, p1 = os.pullEvent()
        
        if e == "timer" then
            if p1 == timer then
                return nil, "tick"
            end
        end
        
        local button = input.getButton(e, p1)
        if button then
            if e == "redstone" then sleep(0.1) end
            return button
        end
    end
end

local function gameLoop()
    loadGame()
    state.lastTick = os.clock()
    
    local saveTimer = 0
    local running = true
    
    while running do
        -- Calculate time delta
        local now = os.clock()
        local dt = now - state.lastTick
        state.lastTick = now
        
        -- Game tick
        doTick(dt)
        
        -- Draw current menu
        if currentMenu == "main" then
            drawMainMenu()
        elseif currentMenu == "shop" then
            drawShopMenu()
        elseif currentMenu == "mods" then
            drawModMenu()
        end
        
        -- Autosave every ~30 seconds of game time
        saveTimer = saveTimer + dt
        if saveTimer >= 30 then
            saveGame()
            saveTimer = 0
        end
        
        -- Wait for input with timeout for ticks
        local button, reason = waitInput(0.5)
        
        if button then
            if currentMenu == "main" then
                if button == "LEFT" then
                    currentMenu = "shop"
                    menuSelection = 1
                elseif button == "CENTER" then
                    doClick()
                elseif button == "RIGHT" then
                    currentMenu = "mods"
                    menuSelection = 1
                end
                
            elseif currentMenu == "shop" then
                if button == "LEFT" then
                    currentMenu = "main"
                elseif button == "CENTER" then
                    local item = shopItems[menuSelection]
                    buyItem(item.key)
                elseif button == "RIGHT" then
                    menuSelection = menuSelection + 1
                    if menuSelection > #shopItems then
                        menuSelection = 1
                    end
                end
                
            elseif currentMenu == "mods" then
                if button == "LEFT" then
                    currentMenu = "main"
                elseif button == "CENTER" then
                    if menuSelection <= #modItems then
                        buyMod(modItems[menuSelection])
                    end
                elseif button == "RIGHT" then
                    menuSelection = menuSelection + 1
                    if menuSelection > #modItems then
                        menuSelection = 1
                    end
                end
            end
        end
    end
    
    saveGame()
end

--------------------------------------------------------------------------------
-- ENTRY POINT
--------------------------------------------------------------------------------

local function main()
    math.randomseed(os.time())
    
    -- Check for demo mode (attract mode from menu)
    local args = { ... }
    if args[1] == "--demo" then
        while true do
            local wantsPlay = runDemo()
            if wantsPlay then
                break
            end
            return  -- Exit back to menu
        end
    end
    
    -- Run main game
    gameLoop()
end

-- Handle graceful exit
local ok, err = pcall(main)
saveGame()

if not ok and err ~= "Terminated" then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.red)
    print("Error: " .. tostring(err))
    sleep(2)
end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
