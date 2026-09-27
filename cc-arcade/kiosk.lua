-- kiosk.lua
-- Kiosk Menu: Always up-to-date arcade menu with jazz and graphics!
-- Intended for spawn / public machines.

local audio = require("audio")
local input = require("input")
local credits = require("credits")

-- Dynamic game list - always fresh!
local function getGames()
    return {
        { name = "Blackjack", cmd = "blackjack", icon = "\4" },
        { name = "Baccarat", cmd = "baccarat", icon = "\5" },
        { name = "Super Slots", cmd = "slots", icon = "$" },
        { name = "Horse Race", cmd = "race", icon = ">" },
        { name = "Can't Stop", cmd = "cant_stop", icon = "!" },
        { name = "RPS Rogue", cmd = "rps_rogue", icon = "*" },
        { name = "Idlecraft", cmd = "idlecraft", icon = "+" },
    }
end

local function getUtilities()
    return {
        { name = "Cashier", cmd = "cashier", icon = "$" },
        { name = "Roulette Watch", cmd = "screensavers/roulette", icon = "@" },
        { name = "Update Arcade", cmd = "update", icon = "^" },
        { name = "Reboot", cmd = "reboot", icon = "O" },
        { name = "Shutdown", cmd = "shutdown", icon = "X" },
    }
end

local w, h = term.getSize()
local selected = 1
local jazzCoroutine = nil
local animFrame = 0
local rainbowColors = {colors.red, colors.orange, colors.yellow, colors.lime, colors.cyan, colors.lightBlue, colors.purple, colors.magenta}

--------------------------------------------------------------------------------
-- Graphics & Animation
--------------------------------------------------------------------------------

local function drawRainbowBorder()
    animFrame = animFrame + 1
    
    -- Top border
    term.setCursorPos(1, 1)
    for x = 1, w do
        term.setBackgroundColor(rainbowColors[((x + animFrame) % #rainbowColors) + 1])
        term.write(" ")
    end
    
    -- Bottom border
    term.setCursorPos(1, h)
    for x = 1, w do
        term.setBackgroundColor(rainbowColors[((x + animFrame + 4) % #rainbowColors) + 1])
        term.write(" ")
    end
    
    -- Side borders
    for y = 2, h - 1 do
        term.setBackgroundColor(rainbowColors[((y + animFrame) % #rainbowColors) + 1])
        term.setCursorPos(1, y)
        term.write(" ")
        term.setBackgroundColor(rainbowColors[((y + animFrame + 4) % #rainbowColors) + 1])
        term.setCursorPos(w, y)
        term.write(" ")
    end
end

local function drawSparkle(x, y)
    local sparkles = {"*", "+", ".", "o"}
    local sparkleColors = {colors.yellow, colors.white, colors.lime, colors.cyan}
    term.setCursorPos(x, y)
    term.setTextColor(sparkleColors[math.random(#sparkleColors)])
    term.setBackgroundColor(colors.black)
    term.write(sparkles[math.random(#sparkles)])
end

local function drawHeader()
    term.setBackgroundColor(colors.black)
    
    -- Animated title
    local title = " ARCADE "
    local titleX = math.floor((w - #title) / 2)
    
    term.setCursorPos(titleX, 2)
    for i = 1, #title do
        local colorIdx = ((i + animFrame) % #rainbowColors) + 1
        term.setTextColor(rainbowColors[colorIdx])
        term.write(title:sub(i, i))
    end
    
    -- Subtitle with pulse effect
    local sub = "[ INSERT CARD TO PLAY ]"
    local name = credits.getName()
    if name then
        sub = "[ " .. name:upper() .. " - " .. credits.get() .. " CREDITS ]"
    end
    
    local subX = math.floor((w - #sub) / 2)
    term.setCursorPos(subX, 3)
    local pulseColor = (animFrame % 10 < 5) and colors.yellow or colors.white
    term.setTextColor(pulseColor)
    term.write(sub)
end

local function drawMenu()
    local games = getGames()
    local utilities = getUtilities()
    local menuItems = {}
    for _, g in ipairs(games) do table.insert(menuItems, g) end
    table.insert(menuItems, { name = "---", cmd = "", icon = "-", separator = true })
    for _, u in ipairs(utilities) do table.insert(menuItems, u) end
    
    -- Clear inner area
    term.setBackgroundColor(colors.black)
    for y = 2, h - 1 do
        term.setCursorPos(2, y)
        term.write(string.rep(" ", w - 2))
    end
    
    drawRainbowBorder()
    drawHeader()
    
    -- Random sparkles
    if math.random() > 0.7 then
        drawSparkle(math.random(3, w - 2), math.random(5, h - 2))
    end
    
    -- Menu items
    local startY = 5
    local maxVisible = h - 7
    local offset = 0
    
    -- Scroll if needed
    if selected > maxVisible then
        offset = selected - maxVisible
    end
    
    for i, item in ipairs(menuItems) do
        local displayIdx = i - offset
        if displayIdx >= 1 and displayIdx <= maxVisible then
            local y = startY + displayIdx - 1
            term.setCursorPos(3, y)
            
            if item.separator then
                term.setTextColor(colors.gray)
                term.write(string.rep("-", w - 5))
            elseif i == selected then
                -- Selected item with animation
                term.setBackgroundColor(colors.blue)
                term.setTextColor(colors.yellow)
                local arrow = (animFrame % 4 < 2) and "> " or ">> "
                term.write(arrow .. item.icon .. " " .. item.name .. " ")
                term.setBackgroundColor(colors.black)
            else
                term.setTextColor(colors.white)
                term.write("  " .. item.icon .. " " .. item.name)
            end
        end
    end
    
    -- Footer
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.black)
    term.setCursorPos(2, h - 1)
    term.write(string.rep(" ", w - 2))
    local footer = "[<] PREV  [O] SELECT  [>] NEXT"
    term.setCursorPos(math.floor((w - #footer) / 2), h - 1)
    term.write(footer)
    
    return menuItems
end

local function drawWelcomePopup(name, amount)
    local popupW, popupH = 30, 11
    local px = math.floor((w - popupW) / 2)
    local py = math.floor((h - popupH) / 2)
    
    -- Draw animated border box
    for row = py, py + popupH do
        term.setCursorPos(px, row)
        local borderColor = rainbowColors[((row + animFrame) % #rainbowColors) + 1]
        term.setBackgroundColor(borderColor)
        term.write(" ")
        term.setBackgroundColor(colors.blue)
        term.write(string.rep(" ", popupW - 2))
        term.setBackgroundColor(borderColor)
        term.write(" ")
    end
    
    -- Stars around welcome
    local stars = {"*", "+", ".", "*", "+"}
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.yellow)
    term.setCursorPos(px + 2, py + 1)
    for i, s in ipairs(stars) do
        term.setTextColor(rainbowColors[((i + animFrame) % #rainbowColors) + 1])
        term.write(s .. " ")
    end
    
    term.setTextColor(colors.yellow)
    term.setCursorPos(px + 4, py + 3)
    term.write("*** WELCOME BACK! ***")
    
    term.setTextColor(colors.white)
    term.setCursorPos(px + 4, py + 5)
    term.write("Player: " .. name)
    
    term.setTextColor(colors.lime)
    term.setCursorPos(px + 4, py + 7)
    term.write("Credits: " .. amount)
    
    term.setTextColor(colors.cyan)
    term.setCursorPos(px + 4, py + 9)
    local msg = (animFrame % 6 < 3) and ">> SELECT A GAME! <<" or "<< SELECT A GAME! >>"
    term.write(msg)
end

--------------------------------------------------------------------------------
-- Jazz Background
--------------------------------------------------------------------------------

local function startJazz()
    if not jazzCoroutine or coroutine.status(jazzCoroutine) == "dead" then
        jazzCoroutine = coroutine.create(function()
            while true do
                audio.playJazz()
                sleep(0.5)
            end
        end)
    end
end

local function tickJazz()
    if jazzCoroutine and coroutine.status(jazzCoroutine) ~= "dead" then
        coroutine.resume(jazzCoroutine)
    end
end

--------------------------------------------------------------------------------
-- Main Loop
--------------------------------------------------------------------------------

local function launchGame(item)
    audio.stopJazz()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    
    if item.cmd == "reboot" then
        os.reboot()
    elseif item.cmd == "shutdown" then
        os.shutdown()
    elseif item.cmd == "" then
        -- Separator, do nothing
        return
    else
        if fs.exists(item.cmd .. ".lua") then
            shell.run(item.cmd)
        else
            term.setTextColor(colors.red)
            print("Game not installed: " .. item.cmd)
            sleep(1)
        end
    end
end

local function main()
    _G.ARCADE_KIOSK = true
    local cardInserted = credits.getName() ~= nil
    local showWelcome = false
    local welcomeTimer = 0
    
    -- Start the jazz!
    startJazz()
    
    -- Animation timer
    local animTimer = os.startTimer(0.15)
    
    while true do
        -- Get fresh menu each frame
        local menuItems = drawMenu()
        
        -- Show welcome popup if needed
        if showWelcome and welcomeTimer > 0 then
            local name = credits.getName()
            local amount = credits.get()
            if name then
                drawWelcomePopup(name, amount)
            end
            welcomeTimer = welcomeTimer - 1
            if welcomeTimer <= 0 then
                showWelcome = false
            end
        end
        
        -- Tick jazz
        tickJazz()
        
        local event, p1 = os.pullEvent()
        
        -- Handle keyboard navigation separately from physical buttons
        if event == "key" then
            local keyName = keys.getName(p1)
            if keyName == "up" then
                selected = selected - 1
                while menuItems[selected] and menuItems[selected].separator do
                    selected = selected - 1
                end
                if selected < 1 then selected = #menuItems end
                audio.playClick()
            elseif keyName == "down" then
                selected = selected + 1
                while menuItems[selected] and menuItems[selected].separator do
                    selected = selected + 1
                end
                if selected > #menuItems then selected = 1 end
                audio.playClick()
            elseif keyName == "enter" or keyName == "space" then
                if menuItems[selected] and not menuItems[selected].separator then
                    audio.playConfirm()
                    launchGame(menuItems[selected])
                    startJazz()
                    cardInserted = credits.getName() ~= nil
                end
            elseif keyName == "left" then
                selected = selected - 1
                while menuItems[selected] and menuItems[selected].separator do
                    selected = selected - 1
                end
                if selected < 1 then selected = #menuItems end
                audio.playClick()
            elseif keyName == "right" then
                selected = selected + 1
                while menuItems[selected] and menuItems[selected].separator do
                    selected = selected + 1
                end
                if selected > #menuItems then selected = 1 end
                audio.playClick()
            end
        end
        
        -- Handle physical arcade buttons (redstone/char)
        local button = input.getButton(event, p1)
        
        if event == "redstone" or event == "char" then
            if button == "LEFT" then
                selected = selected - 1
                while menuItems[selected] and menuItems[selected].separator do
                    selected = selected - 1
                end
                if selected < 1 then selected = #menuItems end
                audio.playClick()
                if event == "redstone" then sleep(0.15) end
                
            elseif button == "RIGHT" then
                selected = selected + 1
                while menuItems[selected] and menuItems[selected].separator do
                    selected = selected + 1
                end
                if selected > #menuItems then selected = 1 end
                audio.playClick()
                if event == "redstone" then sleep(0.15) end
                
            elseif button == "CENTER" then
                if menuItems[selected] and not menuItems[selected].separator then
                    audio.playConfirm()
                    launchGame(menuItems[selected])
                    startJazz()
                    cardInserted = credits.getName() ~= nil
                end
                if event == "redstone" then sleep(0.15) end
            end
        end
        
        if event == "disk" then
            local name = credits.getName()
            if name and not cardInserted then
                cardInserted = true
                audio.playConfirm()
                showWelcome = true
                welcomeTimer = 25
            end
            
        elseif event == "disk_eject" then
            cardInserted = false
            showWelcome = false
            
        elseif event == "timer" and p1 == animTimer then
            animTimer = os.startTimer(0.15)
        end
    end
end

-- Run with error recovery
while true do
    local ok, err = pcall(main)
    if not ok then
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.red)
        print("Kiosk restarting...")
        term.setTextColor(colors.gray)
        print(tostring(err))
        sleep(1)
    end
end
