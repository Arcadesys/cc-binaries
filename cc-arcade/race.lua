-- race.lua
-- ASCII Horse Racing (3-button)
-- Controls: [Left]=Horse 1, [Center]=Horse 2, [Right]=Horse 3
-- Keyboard exit: [Backspace] or [E]
-- Optional payout pulse: enable PAYOUT_PULSE below.

local input = require("input")
local creditsAPI = require("credits")
local audio = require("audio")

math.randomseed(os.epoch("utc"))

local w, h = term.getSize()

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------

local BET_COST = 5

-- If you want to drive a dispenser/dropper, set this true.
-- (The arcade already pays via the Credits card system by default.)
local PAYOUT_PULSE = false
local PAYOUT_SIDE = "bottom"
local PAYOUT_PULSE_SECONDS = 0.12

-- Track will auto-fit the current terminal/monitor width.
local MIN_TRACK_LEN = 18
local TRACK_PADDING = 20 -- room for name/odds on the left

-- Odds are fractional (profit = bet * num/den; total return = bet + profit)
-- These are intentionally a little "unfair" (overround) like an arcade book.
local horses = {
    {
        idx = 1,
        name = "COPPER COMET",
        color = colors.orange,
        oddsNum = 4,
        oddsDen = 5,
        style = "STEADY",
    },
    {
        idx = 2,
        name = "LEDGER LIZARD",
        color = colors.lightGray,
        oddsNum = 7,
        oddsDen = 5,
        style = "CLOSER",
    },
    {
        idx = 3,
        name = "NEON PANIC",
        color = colors.purple,
        oddsNum = 3,
        oddsDen = 1,
        style = "CHAOS",
    },
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

local function runAttractModeRace()
    while true do
        clear(colors.black)
        drawHeader(0)
        drawCenter(3, "ATTRACTION MODE", colors.yellow, colors.black)
        drawCenter(5, "Demo Race - Insert Disk / Press Any Button", colors.white, colors.black)
        local brk = waitForBreakEvent(0.8)
        if brk and brk.type ~= "timeout" then return brk end

        local trackLen = computeTrackLen()
        local positions = { 1, 1, 1 }
        local winner = nil

        local raceDelay = 0.10
        while not winner do
            for i, horse in ipairs(horses) do
                local progress = positions[i] / trackLen
                local step = stepForHorse(horse, progress)
                positions[i] = clamp(positions[i] + step, 1, trackLen)
                if positions[i] >= trackLen then
                    winner = i
                    break
                end
            end

            drawTrack(trackLen, positions)
            drawCenter(h - 2, "ATTRACTION MODE - Insert Disk / Press Any Button", colors.gray, colors.black)
            audio.playShuffle()
            brk = waitForBreakEvent(raceDelay)
            if brk and brk.type ~= "timeout" then return brk end
        end

        drawTrack(trackLen, positions, winner)
        drawCenter(h - 2, "ATTRACTION MODE - Winner: " .. horses[winner].name, colors.lime, colors.black)
        audio.playWin()
        brk = waitForBreakEvent(2.0)
        if brk and brk.type ~= "timeout" then return brk end
    end
end

local function oddsString(h)
    return tostring(h.oddsNum) .. ":" .. tostring(h.oddsDen)
end

local function totalReturn(bet, h)
    local profit = bet * (h.oddsNum / h.oddsDen)
    return math.floor(bet + profit)
end

local function pulsePayout(count)
    if not PAYOUT_PULSE then return end
    for _ = 1, count do
        redstone.setOutput(PAYOUT_SIDE, true)
        sleep(PAYOUT_PULSE_SECONDS)
        redstone.setOutput(PAYOUT_SIDE, false)
        sleep(PAYOUT_PULSE_SECONDS)
    end
end

--------------------------------------------------------------------------------
-- RACE LOGIC (PERSONALITIES)
--------------------------------------------------------------------------------

local function stepForHorse(h, progress)
    -- progress: 0..1 (how far the race has advanced for that horse)
    -- returns step delta (can be 0 or negative for CHAOS)

    if h.style == "STEADY" then
        -- Consistent pace. Rare 2-step burst.
        local step = 0
        if math.random() < 0.68 then step = 1 end
        if step == 1 and math.random() < 0.08 then step = 2 end
        return step
    end

    if h.style == "CLOSER" then
        -- Slow early, strong finish.
        local p = 0.48
        local burst = 0.06
        if progress >= 0.60 then
            p = 0.74
            burst = 0.14
        elseif progress >= 0.35 then
            p = 0.58
            burst = 0.09
        end

        local step = 0
        if math.random() < p then step = 1 end
        if step == 1 and math.random() < burst then step = 2 end
        return step
    end

    -- CHAOS
    -- Mostly awkward, occasionally ridiculous.
    local roll = math.random(1, 100)
    if roll <= 18 then return 0 end
    if roll <= 30 then return -1 end
    if roll <= 82 then return 1 end
    if roll <= 95 then return 2 end
    return 3
end

--------------------------------------------------------------------------------
-- DRAWING
--------------------------------------------------------------------------------

local function computeTrackLen()
    local trackLen = w - TRACK_PADDING
    trackLen = clamp(trackLen, MIN_TRACK_LEN, 60)
    return trackLen
end

local function drawHeader(credits)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.yellow)
    term.setCursorPos(1, 1)
    term.clearLine()
    term.setCursorPos(2, 1)
    term.write("HORSE RACE")

    local cText = "Credits: " .. tostring(credits)
    term.setTextColor(colors.white)
    term.setCursorPos(math.max(1, w - #cText + 1), 1)
    term.write(cText)
end

local function drawBetScreen(credits)
    clear(colors.black)
    drawHeader(credits)

    drawCenter(3, "PLACE YOUR BET", colors.lime, colors.black)
    drawCenter(5, "Bet Cost: " .. tostring(BET_COST), colors.white, colors.black)

    local y = 7
    term.setCursorPos(3, y)
    term.setTextColor(colors.gray)
    term.write("[L] " .. horses[1].name .. " (" .. oddsString(horses[1]) .. ")")

    term.setCursorPos(3, y + 2)
    term.write("[C] " .. horses[2].name .. " (" .. oddsString(horses[2]) .. ")")

    term.setCursorPos(3, y + 4)
    term.write("[R] " .. horses[3].name .. " (" .. oddsString(horses[3]) .. ")")

    term.setCursorPos(3, y + 7)
    term.setTextColor(colors.yellow)
    term.write("Win returns (total): ")

    term.setCursorPos(3, y + 8)
    term.setTextColor(colors.white)
    term.write("L=" .. totalReturn(BET_COST, horses[1]) .. "  C=" .. totalReturn(BET_COST, horses[2]) .. "  R=" .. totalReturn(BET_COST, horses[3]))

    term.setCursorPos(3, h - 2)
    term.setTextColor(colors.gray)
    term.write("Keyboard: [E]/[Backspace] to exit")
end

local function drawTrack(trackLen, positions, winnerIdx)
    clear(colors.black)

    local baseY = 3
    for i, horse in ipairs(horses) do
        local labelY = baseY + (i - 1) * 4
        local laneY = labelY + 1

        term.setCursorPos(2, labelY)
        term.setTextColor(colors.white)
        term.write(horse.name)

        term.setCursorPos(w - 10, labelY)
        term.setTextColor(colors.gray)
        term.write(oddsString(horse))

        term.setCursorPos(2, laneY)
        term.setTextColor(colors.gray)
        term.write(string.rep("-", trackLen) .. "|")

        local pos = positions[i]
        local drawX = 2 + clamp(pos, 1, trackLen - 2)
        term.setCursorPos(drawX, laneY)
        term.setTextColor(horse.color)
        term.write("@>")

        if winnerIdx and winnerIdx == i then
            term.setCursorPos(2, laneY + 1)
            term.setTextColor(colors.lime)
            term.write("WINNER")
        end
    end
end

--------------------------------------------------------------------------------
-- MAIN
--------------------------------------------------------------------------------

local function main()
    while true do
        local credits = creditsAPI.get()
        drawBetScreen(credits)

        local brk = waitForBreakEvent(8)
        if brk and brk.type == "timeout" then
            brk = runAttractModeRace()
        end

        if brk and brk.type == "exit" then
            break
        end
        if not brk or brk.type == "disk" then
            -- disk inserted / changed: just redraw bet screen
            goto continue_main
        end

        local button = brk.button

        local betHorse = nil
        if button == "LEFT" then betHorse = 1 end
        if button == "CENTER" then betHorse = 2 end
        if button == "RIGHT" then betHorse = 3 end

        if betHorse == nil then
            audio.playError()
        else
            if credits ~= math.huge and credits < BET_COST then
                audio.playLose()
                drawCenter(h - 4, "Not enough credits!", colors.red, colors.black)
                sleep(1.2)
            else
                audio.playChip()
                creditsAPI.remove(BET_COST)

                local trackLen = computeTrackLen()
                local positions = { 1, 1, 1 }
                local winner = nil

                local raceDelay = 0.12
                while not winner do
                    for i, horse in ipairs(horses) do
                        local progress = positions[i] / trackLen
                        local step = stepForHorse(horse, progress)
                        positions[i] = clamp(positions[i] + step, 1, trackLen)
                        if positions[i] >= trackLen then
                            winner = i
                            break
                        end
                    end

                    drawTrack(trackLen, positions)
                    audio.playShuffle()
                    sleep(raceDelay)
                end

                drawTrack(trackLen, positions, winner)
                term.setCursorPos(2, h - 4)

                if winner == betHorse then
                    audio.playWin()
                    term.setTextColor(colors.lime)
                    local winTotal = totalReturn(BET_COST, horses[winner])
                    local profit = winTotal - BET_COST
                    term.write("YOU WIN! +" .. tostring(profit) .. " credits")

                    creditsAPI.add(winTotal)
                    pulsePayout(profit)
                else
                    audio.playLose()
                    term.setTextColor(colors.red)
                    term.write("YOU LOSE. Winner: " .. horses[winner].name)
                end

                term.setCursorPos(2, h - 2)
                term.setTextColor(colors.gray)
                term.write("Press any button...")
                waitButtonOrExit()
            end
        end

        ::continue_main::
    end

    term.setBackgroundColor(colors.black)
    term.clear()
    if fs.exists("menu.lua") then
        shell.run("menu.lua")
    end
end

main()
