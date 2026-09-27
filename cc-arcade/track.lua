-- track.lua
-- Track & Field Demake (Timing Race)
-- Controls: [Left]=Player 1, [Center]=Player 2, [Right]=Player 3
-- Time your press in the GREEN zone to advance! RED = go back!
-- Keyboard exit: [Backspace] or [E]

local input = require("input")
local creditsAPI = require("credits")
local audio = require("audio")

math.randomseed(os.epoch("utc"))

local w, h = term.getSize()

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------

local BET_COST = 5
local TRACK_LENGTH = math.max(10, h - 8)  -- Vertical track
local WIN_PRIZE = 15

-- Timing bar settings
local BAR_WIDTH = 20
local BAR_SPEED_MIN = 0.03
local BAR_SPEED_MAX = 0.08
local GREEN_SIZE = 4       -- Size of the "sweet spot"
local YELLOW_SIZE = 2      -- Near-miss zone
local RED_SIZE = 2         -- Penalty zone on edges

-- Player config
local players = {
    { name = "P1", color = colors.red, pos = 1, barPos = 1, barDir = 1, barSpeed = 0.05 },
    { name = "P2", color = colors.blue, pos = 1, barPos = 1, barDir = 1, barSpeed = 0.05 },
    { name = "P3", color = colors.green, pos = 1, barPos = 1, barDir = 1, barSpeed = 0.05 },
}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function clear(bg)
    term.setBackgroundColor(bg or colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function drawText(x, y, text, fg, bg)
    term.setCursorPos(x, y)
    if fg then term.setTextColor(fg) end
    if bg then term.setBackgroundColor(bg) end
    term.write(text)
end

local function drawCenter(y, text, fg, bg)
    if bg then term.setBackgroundColor(bg) end
    if fg then term.setTextColor(fg) end
    local x = math.max(1, math.floor((w - #text) / 2) + 1)
    term.setCursorPos(x, y)
    term.write(text)
end

local function waitButtonOrExit()
    while true do
        local event, p1 = os.pullEvent()
        local button = input.getButton(event, p1)
        if button then
            if event == "redstone" then sleep(0.2) end
            return button
        end
        if event == "key" then
            local name = keys.getName(p1)
            if name == "backspace" then return "EXIT" end
        elseif event == "char" then
            if tostring(p1):lower() == "e" then return "EXIT" end
        elseif event == "terminate" then
            return "EXIT"
        end
    end
end

local function waitForBreakEvent(seconds)
    local timerId
    if seconds and seconds > 0 then
        timerId = os.startTimer(seconds)
    end

    while true do
        local event, p1 = os.pullEvent()

        if event == "disk" then
            return { type = "disk", event = event, p1 = p1 }
        end

        local button = input.getButton(event, p1)
        if button then
            if event == "redstone" then sleep(0.2) end
            return { type = "button", button = button, event = event, p1 = p1 }
        end

        if event == "key" then
            local name = keys.getName(p1)
            if name == "backspace" then return { type = "exit" } end
            return { type = "key", event = event, p1 = p1 }
        elseif event == "char" then
            if tostring(p1):lower() == "e" then return { type = "exit" } end
            return { type = "key", event = event, p1 = p1 }
        elseif event == "terminate" then
            return { type = "exit" }
        end

        if timerId and event == "timer" and p1 == timerId then
            return { type = "timeout" }
        end
    end
end

--------------------------------------------------------------------------------
-- DRAWING
--------------------------------------------------------------------------------

local function drawHeader(credits)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.clearLine()
    
    local title = " TRACK & FIELD "
    term.setCursorPos(math.floor((w - #title) / 2) + 1, 1)
    term.write(title)
    
    if credits then
        local cStr = "Credits: " .. tostring(credits)
        term.setCursorPos(w - #cStr, 1)
        term.write(cStr)
    end
end

-- Draw timing bar for a player
local function drawTimingBar(player, x, y)
    local barWidth = BAR_WIDTH
    
    -- Calculate zone positions (centered green zone)
    local greenStart = math.floor((barWidth - GREEN_SIZE) / 2) + 1
    local greenEnd = greenStart + GREEN_SIZE - 1
    local yellowStart = greenStart - YELLOW_SIZE
    local yellowEnd = greenEnd + YELLOW_SIZE
    
    -- Draw the bar background with zones
    term.setCursorPos(x, y)
    for i = 1, barWidth do
        local bg
        if i <= RED_SIZE or i > barWidth - RED_SIZE then
            bg = colors.red
        elseif i >= greenStart and i <= greenEnd then
            bg = colors.lime
        elseif i >= yellowStart and i <= yellowEnd then
            bg = colors.yellow
        else
            bg = colors.gray
        end
        term.setBackgroundColor(bg)
        term.write(" ")
    end
    
    -- Draw the moving indicator
    local indicatorPos = math.floor(player.barPos)
    if indicatorPos >= 1 and indicatorPos <= barWidth then
        term.setCursorPos(x + indicatorPos - 1, y)
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
        term.write("|")
    end
    
    -- Draw player label
    term.setCursorPos(x - 4, y)
    term.setBackgroundColor(colors.black)
    term.setTextColor(player.color)
    term.write(player.name .. ":")
end

-- Get the zone at a position
local function getZone(pos)
    local barWidth = BAR_WIDTH
    local greenStart = math.floor((barWidth - GREEN_SIZE) / 2) + 1
    local greenEnd = greenStart + GREEN_SIZE - 1
    local yellowStart = greenStart - YELLOW_SIZE
    local yellowEnd = greenEnd + YELLOW_SIZE
    
    local intPos = math.floor(pos)
    
    if intPos <= RED_SIZE or intPos > barWidth - RED_SIZE then
        return "RED"
    elseif intPos >= greenStart and intPos <= greenEnd then
        return "GREEN"
    elseif intPos >= yellowStart and intPos <= yellowEnd then
        return "YELLOW"
    else
        return "GRAY"
    end
end

-- Draw the vertical race track
local function drawTrack(startY)
    local trackX = 6
    local trackWidth = #players * 6 + 4
    
    -- Draw finish line
    term.setCursorPos(trackX, startY)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    term.write(string.rep("=", trackWidth) .. " FINISH!")
    
    -- Draw track lanes
    for row = 1, TRACK_LENGTH do
        local y = startY + row
        term.setCursorPos(trackX, y)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.gray)
        
        -- Lane dividers and runners
        for i, p in ipairs(players) do
            local laneX = trackX + (i - 1) * 6 + 2
            
            -- Is runner at this position? (invert: pos 1 = bottom, TRACK_LENGTH = top)
            local runnerRow = TRACK_LENGTH - p.pos + 1
            
            if row == runnerRow then
                -- Draw runner
                term.setCursorPos(laneX, y)
                term.setTextColor(p.color)
                term.setBackgroundColor(colors.black)
                term.write(" o ")   -- Head
            else
                -- Empty lane
                term.setCursorPos(laneX, y)
                term.setBackgroundColor(colors.black)
                term.setTextColor(colors.gray)
                if row == TRACK_LENGTH then
                    term.write("---")  -- Start line
                else
                    term.write(" | ")
                end
            end
        end
    end
    
    -- Draw start label
    term.setCursorPos(trackX, startY + TRACK_LENGTH + 1)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write(" START " .. string.rep("-", trackWidth - 7))
    
    -- Draw lane labels
    for i, p in ipairs(players) do
        local laneX = trackX + (i - 1) * 6 + 2
        term.setCursorPos(laneX, startY + TRACK_LENGTH + 2)
        term.setTextColor(p.color)
        term.write(" " .. p.name .. " ")
    end
end

-- Draw instructions
local function drawInstructions(y)
    term.setBackgroundColor(colors.black)
    drawCenter(y, "[1] P1  [2] P2  [3] P3", colors.lightGray)
    drawCenter(y + 1, "Press when indicator is in GREEN!", colors.lime)
end

--------------------------------------------------------------------------------
-- GAME LOGIC
--------------------------------------------------------------------------------

local function resetPlayers()
    for i, p in ipairs(players) do
        p.pos = 1
        p.barPos = 1
        p.barDir = 1
        p.barSpeed = BAR_SPEED_MIN + math.random() * (BAR_SPEED_MAX - BAR_SPEED_MIN)
    end
end

local function updateBars(dt)
    for i, p in ipairs(players) do
        p.barPos = p.barPos + p.barDir * p.barSpeed * dt * 60
        
        -- Bounce off edges
        if p.barPos >= BAR_WIDTH then
            p.barPos = BAR_WIDTH
            p.barDir = -1
            -- Randomize speed slightly on bounce
            p.barSpeed = BAR_SPEED_MIN + math.random() * (BAR_SPEED_MAX - BAR_SPEED_MIN)
        elseif p.barPos <= 1 then
            p.barPos = 1
            p.barDir = 1
            p.barSpeed = BAR_SPEED_MIN + math.random() * (BAR_SPEED_MAX - BAR_SPEED_MIN)
        end
    end
end

local function handlePress(playerIdx)
    local p = players[playerIdx]
    local zone = getZone(p.barPos)
    
    if zone == "GREEN" then
        -- Perfect! Move forward 2
        p.pos = clamp(p.pos + 2, 1, TRACK_LENGTH)
        audio.play("advance")
        return "PERFECT", 2
    elseif zone == "YELLOW" then
        -- Good! Move forward 1
        p.pos = clamp(p.pos + 1, 1, TRACK_LENGTH)
        audio.play("advance")
        return "GOOD", 1
    elseif zone == "RED" then
        -- Ouch! Move back 2
        p.pos = clamp(p.pos - 2, 1, TRACK_LENGTH)
        audio.play("bad")
        return "OUCH", -2
    else
        -- Gray zone - no movement
        audio.play("bad")
        return "MISS", 0
    end
end

local function checkWinner()
    for i, p in ipairs(players) do
        if p.pos >= TRACK_LENGTH then
            return i
        end
    end
    return nil
end

local function showResult(playerIdx, result, delta)
    local p = players[playerIdx]
    local msg = p.name .. ": " .. result
    if delta > 0 then
        msg = msg .. " (+" .. delta .. ")"
    elseif delta < 0 then
        msg = msg .. " (" .. delta .. ")"
    end
    
    local color = colors.white
    if result == "PERFECT" then color = colors.lime
    elseif result == "GOOD" then color = colors.yellow
    elseif result == "OUCH" then color = colors.red
    else color = colors.gray end
    
    drawCenter(h - 1, msg .. string.rep(" ", 20), color, colors.black)
end

--------------------------------------------------------------------------------
-- MAIN GAME LOOP
--------------------------------------------------------------------------------

local function runRace(cards)
    resetPlayers()
    
    local barY = 3
    local trackStartY = barY + #players + 2
    
    -- Calculate dynamic track length
    TRACK_LENGTH = math.max(8, h - trackStartY - 4)
    
    local lastTime = os.clock()
    local winner = nil
    
    while not winner do
        local currentTime = os.clock()
        local dt = currentTime - lastTime
        lastTime = currentTime
        
        -- Update timing bars
        updateBars(dt)
        
        -- Draw everything
        clear(colors.black)
        drawHeader(cards and cards[1] and creditsAPI.get(cards[1].path))
        
        -- Draw timing bars
        for i, p in ipairs(players) do
            drawTimingBar(p, 8, barY + i - 1)
        end
        
        -- Draw track
        drawTrack(trackStartY)
        
        -- Draw instructions
        drawInstructions(h - 3)
        
        -- Check for input
        local timerId = os.startTimer(0.05)
        local event, p1 = os.pullEvent()
        
        if event == "timer" and p1 == timerId then
            -- Just continue animation
        else
            local button = input.getButton(event, p1)
            
            if button == "LEFT" then
                local result, delta = handlePress(1)
                showResult(1, result, delta)
                sleep(0.15)
            elseif button == "CENTER" then
                local result, delta = handlePress(2)
                showResult(2, result, delta)
                sleep(0.15)
            elseif button == "RIGHT" then
                local result, delta = handlePress(3)
                showResult(3, result, delta)
                sleep(0.15)
            end
            
            -- Check for exit
            if event == "key" then
                local name = keys.getName(p1)
                if name == "backspace" then return nil end
            elseif event == "char" then
                if tostring(p1):lower() == "e" then return nil end
            elseif event == "terminate" then
                return nil
            end
        end
        
        winner = checkWinner()
    end
    
    return winner
end

local function showWinScreen(winnerIdx, cards)
    local p = players[winnerIdx]
    
    clear(colors.black)
    drawHeader(cards and cards[1] and creditsAPI.get(cards[1].path))
    
    -- Victory animation
    for flash = 1, 6 do
        local bg = (flash % 2 == 0) and colors.black or p.color
        term.setBackgroundColor(bg)
        term.clear()
        drawHeader(cards and cards[1] and creditsAPI.get(cards[1].path))
        
        local cy = math.floor(h / 2)
        drawCenter(cy - 2, "================", colors.yellow, bg)
        drawCenter(cy - 1, "    WINNER!     ", colors.white, bg)
        drawCenter(cy, "    " .. p.name .. " WINS!    ", p.color, bg)
        drawCenter(cy + 1, "================", colors.yellow, bg)
        
        -- ASCII trophy
        drawCenter(cy + 3, "   ___   ", colors.yellow, bg)
        drawCenter(cy + 4, "  |   |  ", colors.yellow, bg)
        drawCenter(cy + 5, "   \\_/   ", colors.yellow, bg)
        drawCenter(cy + 6, "    |    ", colors.yellow, bg)
        drawCenter(cy + 7, "   ===   ", colors.yellow, bg)
        
        audio.play("win")
        sleep(0.2)
    end
    
    term.setBackgroundColor(colors.black)
    drawCenter(h - 2, "Press any button to continue...", colors.gray, colors.black)
    waitButtonOrExit()
end

--------------------------------------------------------------------------------
-- ATTRACT MODE
--------------------------------------------------------------------------------

local function runAttractMode()
    resetPlayers()
    
    local barY = 4
    local trackStartY = barY + #players + 2
    TRACK_LENGTH = math.max(8, h - trackStartY - 4)
    
    local lastTime = os.clock()
    local autoTimer = 0
    
    while true do
        local currentTime = os.clock()
        local dt = currentTime - lastTime
        lastTime = currentTime
        autoTimer = autoTimer + dt
        
        -- Update timing bars
        updateBars(dt)
        
        -- Auto-play: random button presses
        if autoTimer > 0.3 + math.random() * 0.5 then
            autoTimer = 0
            local idx = math.random(1, 3)
            handlePress(idx)
            
            -- Check for winner in attract mode, reset if someone wins
            if checkWinner() then
                resetPlayers()
            end
        end
        
        -- Draw everything
        clear(colors.black)
        
        term.setBackgroundColor(colors.purple)
        term.setTextColor(colors.white)
        term.setCursorPos(1, 1)
        term.clearLine()
        drawCenter(1, " TRACK & FIELD ", colors.yellow, colors.purple)
        
        drawCenter(2, "INSERT DISK TO PLAY", colors.white, colors.black)
        
        -- Draw timing bars
        for i, p in ipairs(players) do
            drawTimingBar(p, 8, barY + i - 1)
        end
        
        -- Draw track
        drawTrack(trackStartY)
        
        -- Draw attract text
        drawCenter(h - 2, "Time your press in the GREEN zone!", colors.lime, colors.black)
        drawCenter(h - 1, string.format("Cost: %d credits  |  Prize: %d credits", BET_COST, WIN_PRIZE), colors.gray, colors.black)
        
        -- Check for break event
        local brk = waitForBreakEvent(0.05)
        if brk then
            if brk.type == "exit" then
                return { type = "exit" }
            elseif brk.type ~= "timeout" then
                return brk
            end
        end
    end
end

--------------------------------------------------------------------------------
-- MAIN ENTRY POINT
--------------------------------------------------------------------------------

local function main()
    while true do
        -- Attract mode until card inserted
        local brk = runAttractMode()
        
        if brk and brk.type == "exit" then
            clear()
            return
        end
        
        if brk and brk.type == "disk" then
            -- Card inserted - start game
            local cards = creditsAPI.findCards()
            
            if #cards > 0 then
                local card = cards[1]
                local currentCredits = creditsAPI.get(card.path)
                
                if currentCredits >= BET_COST then
                    -- Deduct bet
                    creditsAPI.add(-BET_COST, card.path)
                    audio.play("bet")
                    
                    -- Run the race
                    local winner = runRace(cards)
                    
                    if winner then
                        -- Award prize
                        creditsAPI.add(WIN_PRIZE, card.path)
                        showWinScreen(winner, cards)
                    end
                else
                    -- Not enough credits
                    clear(colors.black)
                    drawHeader(currentCredits)
                    drawCenter(math.floor(h/2), "NOT ENOUGH CREDITS!", colors.red)
                    drawCenter(math.floor(h/2) + 2, string.format("Need %d, have %d", BET_COST, currentCredits), colors.gray)
                    audio.play("bad")
                    sleep(2)
                end
            end
        end
    end
end

-- Run
main()
