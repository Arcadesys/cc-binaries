-- blackjack.lua
-- Sequential Multiplayer Blackjack for Arcade OS
-- Visual Overhaul

local w, h = term.getSize()
local SUITS = {"H", "D", "C", "S"}
local RANKS = {"2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"}

-- Colors
local C_TABLE = colors.green
local C_TEXT = colors.white
local C_CARD_BG = colors.white
local C_CARD_RED = colors.red
local C_CARD_BLK = colors.black
local C_HIDDEN = colors.red
local C_LABEL = colors.yellow
local C_MSG = colors.cyan

-- Card Dimensions
local CARD_W = 4
local CARD_H = 3

local input = require("input")

local function waitKey()
    while true do
        local e, p1 = os.pullEvent()
        local button = input.getButton(e, p1)
        if button then
            if e == "redstone" then sleep(0.2) end
            return button
        end
    end
end

--------------------------------------------------------------------------------
-- GAME LOGIC
--------------------------------------------------------------------------------

local function createDeck()
    local deck = {}
    for _, s in ipairs(SUITS) do
        for _, r in ipairs(RANKS) do
            table.insert(deck, {suit=s, rank=r})
        end
    end
    -- Shuffle
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
    return deck
end

local function getCardValue(card)
    if card.rank == "A" then return 11 end
    if card.rank == "K" or card.rank == "Q" or card.rank == "J" then return 10 end
    return tonumber(card.rank)
end

local function calculateHand(hand)
    local total = 0
    local aces = 0
    for _, card in ipairs(hand) do
        total = total + getCardValue(card)
        if card.rank == "A" then aces = aces + 1 end
    end
    while total > 21 and aces > 0 do
        total = total - 10
        aces = aces - 1
    end
    return total
end

local function drawCardDeck(deck)
    if #deck == 0 then deck = createDeck() end -- Reshuffle if empty
    return table.remove(deck, 1)
end

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------



local function animateSparkles(x, y, width, height)
    local duration = 1.5
    local startTime = os.clock()
    local colorsList = {colors.yellow, colors.gold or colors.orange, colors.white}
    
    while os.clock() - startTime < duration do
        local rx = math.random(x, x + width - 1)
        local ry = math.random(y, y + height - 1)
        local color = colorsList[math.random(1, #colorsList)]
        
        term.setCursorPos(rx, ry)
        term.setTextColor(color)
        term.write("*")
        
        sleep(0.05)
    end
end

local function animateChips(startX, startY, endX, endY)
    local steps = 10
    local dx = (endX - startX) / steps
    local dy = (endY - startY) / steps
    
    for i = 1, steps do
        local cx = math.floor(startX + dx * i)
        local cy = math.floor(startY + dy * i)
        
        -- Draw Chip
        term.setCursorPos(cx, cy)
        term.setBackgroundColor(colors.yellow)
        term.setTextColor(colors.black)
        term.write("O")
        
        sleep(0.05)
        
        -- Clear Chip (simple clear, might overwrite background)
        term.setCursorPos(cx, cy)
        term.setBackgroundColor(colors.green) -- Assuming table color
        term.write(" ")
    end
end

local function drawText(x, y, text, fg, bg)
    term.setCursorPos(x, y)
    if fg then term.setTextColor(fg) end
    if bg then term.setBackgroundColor(bg) end
    term.write(text)
end

local function drawCenter(y, text, fg, bg)
    local x = math.floor((w - #text)/2) + 1
    drawText(x, y, text, fg, bg)
end

local function getSuitColor(suit)
    if suit == "H" or suit == "D" then return C_CARD_RED else return C_CARD_BLK end
end

local function getSuitChar(suit)
    -- If using a font that supports symbols, we could use them.
    -- Standard CC font doesn't have suit symbols, so we use letters.
    return suit
end

local function drawGraphicalCard(x, y, card, hidden)
    -- Card Background
    term.setBackgroundColor(hidden and C_HIDDEN or C_CARD_BG)
    
    for i=0, CARD_H-1 do
        term.setCursorPos(x, y+i)
        term.write(string.rep(" ", CARD_W))
    end
    
    if hidden then
        -- Pattern for hidden card
        term.setTextColor(colors.white)
        term.setCursorPos(x, y+1)
        term.write(" ?? ")
    else
        -- Rank and Suit
        local sColor = getSuitColor(card.suit)
        term.setTextColor(sColor)
        
        local rankStr = card.rank
        if #rankStr == 1 then rankStr = rankStr .. " " end
        
        -- Top Left
        term.setCursorPos(x, y)
        term.write(rankStr)
        
        -- Center Suit
        term.setCursorPos(x+1, y+1)
        term.write(getSuitChar(card.suit))
        
        -- Bottom Right (Rotated/Inverted conceptually, but just text here)
        term.setCursorPos(x+CARD_W-#rankStr, y+CARD_H-1)
        term.write(rankStr)
    end
end

local function drawHandGraphical(centerX, y, name, hand, hideFirst, isActive, status)
    -- Calculate total width of hand to center it
    -- Overlap cards by 1 column if hand is large?
    -- Let's do simple spacing: CARD_W + 1
    local spacing = CARD_W + 1
    local totalW = (#hand * spacing) - 1
    local startX = math.floor(centerX - totalW/2)
    
    -- Draw Name Label
    local labelColor = isActive and colors.yellow or colors.lightGray
    drawText(startX, y - 1, name, labelColor, C_TABLE)
    
    -- Draw Status if present
    if status and status ~= "Playing" then
        local sColor = colors.lightGray
        if status == "Blackjack!" or string.find(status, "WIN") then sColor = colors.gold or colors.orange end
        if status == "Bust!" or string.find(status, "LOSE") then sColor = colors.red end
        drawText(startX + #name + 2, y - 1, status, sColor, C_TABLE)
    end
    
    -- Draw Cards
    for i, card in ipairs(hand) do
        local cx = startX + (i-1)*spacing
        local isHidden = hideFirst and (i == 1)
        drawGraphicalCard(cx, y, card, isHidden)
    end
    
    -- Draw Score
    if not hideFirst then
        local score = calculateHand(hand)
        drawText(startX, y + CARD_H, "Score: " .. score, colors.gray, C_TABLE)
    end
end

local function drawTable(players, dealerHand, currentPlayerIdx, message, showDealer)
    term.setBackgroundColor(C_TABLE)
    term.clear()
    
    -- Header
    drawCenter(1, " BLACKJACK ", colors.black, colors.lime)
    
    -- Dealer Area (Top Center)
    local dealerY = 3
    drawHandGraphical(w/2, dealerY, "DEALER", dealerHand, not showDealer, false, nil)
    
    -- Player Area (Bottom)
    -- Distribute players evenly
    local playerY = h - 6 -- Leave room for controls
    local sectionW = w / #players
    
    for i, p in ipairs(players) do
        local pCenterX = (i-1)*sectionW + sectionW/2
        local isActive = (i == currentPlayerIdx)
        -- Add indicator if active
        if isActive then
            drawText(math.floor(pCenterX)-2, playerY-2, " vvv ", colors.white, C_TABLE)
        end
        drawHandGraphical(pCenterX, playerY, "P"..i, p.hand, false, isActive, p.status)
    end
    
    -- Message / Controls Area (Bottom 2 lines)
    local footerY = h - 1
    term.setBackgroundColor(colors.black)
    term.setCursorPos(1, h-1)
    term.clearLine()
    term.setCursorPos(1, h)
    term.clearLine()
    
    if message then
        drawCenter(h-1, message, C_MSG, colors.black)
    end
    
    -- Draw 3-Column Footer
    local colW = math.floor(w / 3)
    local c1 = "Hit"
    local c2 = "Stand"
    local c3 = "Shift >"
    
    if currentPlayerIdx == 0 then
        c1 = "-"
        c2 = "Deal"
        c3 = "Cash Out"
    elseif message and string.find(message, "ADV") then
        c1 = "Double"
        c2 = "Surrender"
        c3 = "Back"
    end
    
    -- Left Button
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    term.write(string.rep(" ", colW))
    drawText(math.floor(colW/2 - #c1/2)+1, h, c1, colors.white, colors.red)
    
    -- Center Button
    term.setCursorPos(colW + 1, h)
    term.setBackgroundColor(colors.yellow)
    term.setTextColor(colors.black)
    term.write(string.rep(" ", colW))
    drawText(colW + math.floor(colW/2 - #c2/2)+1, h, c2, colors.black, colors.yellow)
    
    -- Right Button
    term.setCursorPos(colW * 2 + 1, h)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.write(string.rep(" ", w - (colW*2)))
    drawText(colW*2 + math.floor((w - colW*2)/2 - #c3/2)+1, h, c3, colors.white, colors.blue)
end

local function waitForBreakEvent(seconds)
    local timerId
    if seconds and seconds > 0 then
        timerId = os.startTimer(seconds)
    end

    while true do
        local e, p1 = os.pullEvent()

        if e == "disk" then
            return { type = "disk", event = e, p1 = p1 }
        end
        if e == "disk_eject" then
            return { type = "disk_eject", event = e, p1 = p1 }
        end

        local button = input.getButton(e, p1)
        if button then
            return { type = "button", button = button, event = e, p1 = p1 }
        end

        if e == "key" or e == "char" then
            return { type = "key", event = e, p1 = p1 }
        end

        if timerId and e == "timer" and p1 == timerId then
            return { type = "timeout" }
        end
    end
end

local function runAttractMode()
    local function cpuWantsHit(hand)
        local score = calculateHand(hand)
        if score <= 11 then return true end
        if score >= 17 then return false end
        return score < 16
    end

    while true do
        local players = {
            { hand = {}, status = "Playing", name = "CPU 1" },
            { hand = {}, status = "Playing", name = "CPU 2" },
            { hand = {}, status = "Playing", name = "CPU 3" }
        }

        local deck = createDeck()
        local dealerHand = {}

        -- Initial deal
        for _ = 1, 2 do
            for _, p in ipairs(players) do
                table.insert(p.hand, drawCardDeck(deck))
                drawTable(players, dealerHand, 0, "ATTRACTION MODE - Insert Disk to Play", false)
                local brk = waitForBreakEvent(0.15)
                if brk and brk.type == "disk" then return brk end
            end

            table.insert(dealerHand, drawCardDeck(deck))
            drawTable(players, dealerHand, 0, "ATTRACTION MODE - Insert Disk to Play", false)
            local brk = waitForBreakEvent(0.15)
            if brk and brk.type == "disk" then return brk end
        end

        -- CPU turns
        for i, p in ipairs(players) do
            while true do
                local score = calculateHand(p.hand)
                if score == 21 and #p.hand == 2 then
                    p.status = "Blackjack!"
                    break
                elseif score > 21 then
                    p.status = "Bust!"
                    break
                end

                if cpuWantsHit(p.hand) then
                    table.insert(p.hand, drawCardDeck(deck))
                    drawTable(players, dealerHand, i, "ATTRACTION MODE - " .. p.name .. " hits", false)
                    local brk = waitForBreakEvent(0.35)
                    if brk and brk.type == "disk" then return brk end
                else
                    p.status = "Stand"
                    drawTable(players, dealerHand, i, "ATTRACTION MODE - " .. p.name .. " stands", false)
                    local brk = waitForBreakEvent(0.35)
                    if brk and brk.type == "disk" then return brk end
                    break
                end
            end
        end

        -- Dealer turn
        drawTable(players, dealerHand, 0, "ATTRACTION MODE - Dealer reveals", true)
        local brk = waitForBreakEvent(0.8)
        if brk and brk.type == "disk" then return brk end

        while calculateHand(dealerHand) < 17 do
            table.insert(dealerHand, drawCardDeck(deck))
            drawTable(players, dealerHand, 0, "ATTRACTION MODE - Dealer hits", true)
            brk = waitForBreakEvent(0.6)
            if brk and brk.type == "disk" then return brk end
        end

        -- Resolve (no credits; just show outcomes)
        local dealerScore = calculateHand(dealerHand)
        local dealerBust = dealerScore > 21

        for _, p in ipairs(players) do
            local pScore = calculateHand(p.hand)
            if p.status == "Bust!" then
                p.status = "LOSE"
            elseif p.status == "Blackjack!" then
                p.status = "WIN!"
            elseif dealerBust then
                p.status = "WIN!"
            elseif pScore > dealerScore then
                p.status = "WIN!"
            elseif pScore == dealerScore then
                p.status = "PUSH"
            else
                p.status = "LOSE"
            end
        end

        drawTable(players, dealerHand, 0, "ATTRACTION MODE - Round over (Insert Disk)", true)
        brk = waitForBreakEvent(2.0)
        if brk and brk.type == "disk" then return brk end

        -- Small pause before next round
        brk = waitForBreakEvent(0.6)
        if brk and brk.type == "disk" then return brk end
    end
end

--------------------------------------------------------------------------------
-- MAIN LOOP
--------------------------------------------------------------------------------

local function main()
    term.setBackgroundColor(colors.black)
    term.clear()
    
    local creditsAPI = require("credits")
    local audio = require("audio")
    
    while true do
        drawCenter(h/2 - 2, "BLACKJACK", colors.lime, colors.black)
        drawCenter(h/2, "Insert Cards (Max 3)", colors.white, colors.black)
        drawCenter(h/2 + 2, "[C] Start Game   [R] Exit", colors.gray, colors.black)
        
        -- Lobby Loop
        local detectedCards = {}
        local attractDelay = 8
        local attractTimer = os.startTimer(attractDelay)
        while true do
            local event, p1 = os.pullEvent()

            if event == "timer" and p1 == attractTimer and #detectedCards == 0 then
                -- CPU vs CPU demo until a disk is inserted (attract mode)
                runAttractMode()

                -- Redraw lobby after attract mode
                term.setBackgroundColor(colors.black)
                term.clear()
                drawCenter(h/2 - 2, "BLACKJACK", colors.lime, colors.black)
                drawCenter(h/2, "Insert Cards (Max 3)", colors.white, colors.black)
                drawCenter(h/2 + 2, "[C] Start Game   [R] Exit", colors.gray, colors.black)

                -- Refresh cards and reset timer
                detectedCards = creditsAPI.findCards()
                attractTimer = os.startTimer(attractDelay)
            end

            -- Arcade button controls (works for redstone + key-based configs)
            local button = input.getButton(event, p1)
            if button == "CENTER" then
                if #detectedCards > 0 then break end
                drawCenter(h/2 + 4, "No players detected!", colors.red, colors.black)
                sleep(1)
                term.setCursorPos(1, h/2+4) term.clearLine()
                attractTimer = os.startTimer(attractDelay)
            elseif button == "RIGHT" then
                term.setBackgroundColor(colors.black)
                term.clear()
                if fs.exists("menu.lua") then shell.run("menu.lua") end
                return
            end

            if event == "key" then
                local key = keys.getName(p1)
                if key == "enter" or key == "space" then -- Start
                    if #detectedCards > 0 then break end
                    drawCenter(h/2 + 4, "No players detected!", colors.red, colors.black)
                    sleep(1)
                    term.setCursorPos(1, h/2+4) term.clearLine()
                    attractTimer = os.startTimer(attractDelay)
                elseif key == "backspace" or key == "e" then -- Exit
                     term.setBackgroundColor(colors.black)
                     term.clear()
                     if fs.exists("menu.lua") then shell.run("menu.lua") end
                     return
                end
            elseif event == "disk" or event == "disk_eject" then
                -- Refresh cards
                detectedCards = creditsAPI.findCards()
                attractTimer = os.startTimer(attractDelay)
                term.setCursorPos(1, h/2 + 4)
                term.clearLine()
                local msg = "Players: "
                for i, c in ipairs(detectedCards) do
                    msg = msg .. c.name .. " "
                end
                drawCenter(h/2 + 4, msg, colors.yellow, colors.black)
            end
            
            -- Initial scan if just opened
            if #detectedCards == 0 then
                 detectedCards = creditsAPI.findCards()
                 if #detectedCards > 0 then
                    attractTimer = os.startTimer(attractDelay)
                    term.setCursorPos(1, h/2 + 4)
                    term.clearLine()
                    local msg = "Players: "
                    for i, c in ipairs(detectedCards) do
                        msg = msg .. c.name .. " "
                    end
                    drawCenter(h/2 + 4, msg, colors.yellow, colors.black)
                end
            end
        end
        
        -- Limit to 3 players
        local players = {}
        for i, card in ipairs(detectedCards) do
            if i > 3 then break end
            creditsAPI.lock(card.path)
            table.insert(players, {
                hand={}, 
                status="Playing", 
                bet=10, 
                name=card.name, -- Use card name
                mountPath=card.path 
            })
            if creditsAPI.get(card.path) < 10 then
                drawCenter(h/2, card.name .. " needs 10 credits!", colors.red, colors.black)
                creditsAPI.unlock(card.path)
                sleep(2)
                return -- Go back to lobby effectively (restarts main)
            end
            creditsAPI.remove(10, card.path) -- Deduct bet immediately
        end
        
        local deck = createDeck()
        local dealerHand = {}
        
        -- Initial Deal
        for _=1,2 do
            for _, p in ipairs(players) do 
                table.insert(p.hand, drawCardDeck(deck)) 
                audio.playDeal()
                sleep(0.2)
            end
            table.insert(dealerHand, drawCardDeck(deck))
            audio.playDeal()
            sleep(0.2)
        end
        
        -- Player Turns
        for i, p in ipairs(players) do
            while true do
                local score = calculateHand(p.hand)
                if score == 21 and #p.hand == 2 then
                    p.status = "Blackjack!"
                    break
                elseif score > 21 then
                    p.status = "Bust!"
                    break
                end
                
                drawTable(players, dealerHand, i, p.name .. "'s Turn", false)
                local action = waitKey()
                
                -- Normal Mode
                if action == "LEFT" then -- Hit
                    table.insert(p.hand, drawCardDeck(deck))
                    audio.playDeal()
                elseif action == "CENTER" then -- Stand
                    p.status = "Stand"
                    break
                elseif action == "RIGHT" then -- Shift (Advanced Mode)
                    -- Show Advanced Options
                    drawTable(players, dealerHand, i, "ADV: [L] Dbl [C] Surr [R] Back", false)
                    local advAction = waitKey()
                    
                    if advAction == "LEFT" then -- Double Down
                        if creditsAPI.get(p.mountPath) >= p.bet then
                            creditsAPI.remove(p.bet, p.mountPath)
                            p.bet = p.bet * 2
                            table.insert(p.hand, drawCardDeck(deck))
                            audio.playDeal()
                            score = calculateHand(p.hand)
                            if score > 21 then p.status = "Bust!" else p.status = "Dbl Stand" end
                            break
                        else
                             drawTable(players, dealerHand, i, "Not enough credits!", false)
                             sleep(1)
                        end
                    elseif advAction == "CENTER" then -- Surrender
                         p.status = "Surrender"
                         break
                    elseif advAction == "RIGHT" then -- Back
                        -- Loop continues
                    end
                end
            end
            drawTable(players, dealerHand, i, p.name .. " Done", false)
            sleep(0.5)
        end
        
        -- Dealer Turn
        drawTable(players, dealerHand, 0, "Dealer's Turn...", true)
        sleep(1)
        while calculateHand(dealerHand) < 17 do
            table.insert(dealerHand, drawCardDeck(deck))
            audio.playDeal()
            drawTable(players, dealerHand, 0, "Dealer Hits...", true)
            sleep(1)
        end
        
        -- Resolve
        local dealerScore = calculateHand(dealerHand)
        local dealerBust = dealerScore > 21
        
        for _, p in ipairs(players) do
            local pScore = calculateHand(p.hand)
            if p.status == "Bust!" then
                p.status = "LOSE"
            elseif p.status == "Surrender" then
                p.status = "SURRENDER"
                creditsAPI.add(math.floor(p.bet / 2), p.mountPath)
            elseif p.status == "Blackjack!" then
                 p.status = "WIN!"
                 creditsAPI.add(math.floor(p.bet * 2.5), p.mountPath) -- 3:2 payout usually, but let's do 2.5x return
            elseif dealerBust then
                p.status = "WIN!"
                creditsAPI.add(p.bet * 2, p.mountPath)
            elseif pScore > dealerScore then
                p.status = "WIN!"
                creditsAPI.add(p.bet * 2, p.mountPath)
            elseif pScore == dealerScore then
                p.status = "PUSH"
                creditsAPI.add(p.bet, p.mountPath)
            else
                p.status = "LOSE"
            end
            
            -- Unlock card
            creditsAPI.unlock(p.mountPath)
        end
        
        drawTable(players, dealerHand, 0, "Round Over!", true)
        
        -- Play Animations for Winners
        local sectionW = w / #players
        local playerY = h - 6
        local dealerX, dealerY = w/2, 3
        
        for i, p in ipairs(players) do
            if p.status == "WIN!" or p.status == "Blackjack!" then
                local pCenterX = math.floor((i-1)*sectionW + sectionW/2)
                
                -- Animate Chips from Dealer to Player
                audio.playChip()
                animateChips(dealerX, dealerY, pCenterX, playerY)
                audio.playWin()
                
                -- Animate Sparkles around Player
                animateSparkles(pCenterX - 6, playerY - 2, 12, 6)
                
                drawTable(players, dealerHand, 0, "Round Over!", true) -- Redraw to clear noise
            end
        end
        
        drawTable(players, dealerHand, 0, "Round Over! [C] Play Again", true)
        
        local endAction = waitKey()
        if endAction == "RIGHT" then
            break
        end
    end
    
    -- Exit to Menu
    term.setBackgroundColor(colors.black)
    term.clear()
    if fs.exists("menu.lua") then shell.run("menu.lua") end
end

main()
