-- audio.lua
-- Simple Audio Manager for Arcade Games
-- Provides DOS-esque sound effects using the Speaker peripheral

local audio = {}
local speaker = peripheral.find("speaker")

-- Helper to play a note safely
local function play(instrument, volume, pitch)
    if speaker then
        speaker.playNote(instrument, volume, pitch)
    end
end

-- Sound Effects

function audio.playClick()
    -- Simple UI click
    play("hat", 0.5, 24)
end

function audio.playConfirm()
    -- Selection confirmation
    play("bit", 1, 14)
end

function audio.playWin()
    -- Victory jingle
    if not speaker then return end
    play("bit", 2, 12)
    sleep(0.1)
    play("bit", 2, 16)
    sleep(0.1)
    play("bit", 2, 19)
    sleep(0.1)
    play("bit", 2, 24)
end

function audio.playLose()
    -- Losing sound
    if not speaker then return end
    play("bit", 2, 12)
    sleep(0.15)
    play("bit", 2, 8)
    sleep(0.15)
    play("bit", 2, 4)
end

function audio.playShuffle()
    -- Card shuffling / Slot spinning tick
    play("snare", 0.5, 24)
end

function audio.playDeal()
    -- Card dealing sound
    play("hat", 1, 16)
end

function audio.playSlotStop()
    -- Slot reel stopping
    play("basedrum", 2, 16)
end

function audio.playChip()
    -- Chip betting sound
    play("hat", 1, 12)
end

function audio.playCashRegister()
    -- Cha-ching!
    if not speaker then return end
    play("bell", 2, 12)
    sleep(0.1)
    play("bell", 2, 16)
end

function audio.playCoinDispense()
    -- Clinking coins
    if not speaker then return end
    for i = 1, 3 do
        play("bit", 1, 20 + math.random(-2, 2))
        sleep(0.05)
    end
end

function audio.playError()
    -- Error buzzer
    if not speaker then return end
    play("bass", 2, 6)
    sleep(0.1)
    play("bass", 2, 6)
end

-- Cocktail Jazz - 32 bar lounge tune
-- Returns a coroutine that plays in background; call audio.stopJazz() to end
local jazzPlaying = false

function audio.playJazz()
    if not speaker then return end
    jazzPlaying = true
    
    -- Jazz chord progressions (ii-V-I patterns, swing feel)
    -- Notes: 0=F#, 1=G, 2=G#, 3=A, 4=A#, 5=B, 6=C, 7=C#, 8=D, 9=D#, 10=E, 11=F, 12=F#...
    -- Using Minecraft note block range: 0-24 (F#3 to F#5)
    
    local chords = {
        -- Dm7 (ii)
        { bass = 8, notes = {8, 12, 15, 19} },
        -- G7 (V)
        { bass = 13, notes = {13, 17, 19, 23} },
        -- Cmaj7 (I)
        { bass = 6, notes = {6, 10, 13, 17} },
        -- Am7
        { bass = 3, notes = {3, 7, 10, 14} },
        -- Dm7
        { bass = 8, notes = {8, 12, 15, 19} },
        -- G7
        { bass = 13, notes = {13, 17, 19, 23} },
        -- Em7
        { bass = 10, notes = {10, 14, 17, 21} },
        -- A7
        { bass = 3, notes = {3, 8, 10, 13} },
    }
    
    local tempo = 0.35  -- Swing tempo
    local bars = 0
    
    while jazzPlaying and bars < 32 do
        for _, chord in ipairs(chords) do
            if not jazzPlaying then break end
            
            -- Beat 1: Bass note + chord stab
            play("bass", 1.5, chord.bass)
            play("harp", 0.8, chord.notes[1])
            play("harp", 0.6, chord.notes[3])
            sleep(tempo)
            if not jazzPlaying then break end
            
            -- Beat 2: Walking bass
            play("bass", 1.0, chord.bass + 2)
            sleep(tempo * 0.6)
            if not jazzPlaying then break end
            
            -- Swing eighth
            play("harp", 0.5, chord.notes[2])
            sleep(tempo * 0.4)
            if not jazzPlaying then break end
            
            -- Beat 3: Chord hit
            play("bass", 1.2, chord.bass + 4)
            play("harp", 0.7, chord.notes[2])
            play("harp", 0.5, chord.notes[4])
            sleep(tempo)
            if not jazzPlaying then break end
            
            -- Beat 4: Walk back down
            play("bass", 1.0, chord.bass + 2)
            sleep(tempo * 0.5)
            if not jazzPlaying then break end
            
            -- Add some melodic fills occasionally
            if math.random() > 0.6 then
                play("harp", 0.6, chord.notes[math.random(1, 4)] + math.random(-2, 2))
            end
            sleep(tempo * 0.5)
            
            bars = bars + 1
            if bars >= 32 then break end
        end
    end
    
    jazzPlaying = false
end

function audio.stopJazz()
    jazzPlaying = false
end

function audio.isJazzPlaying()
    return jazzPlaying
end

function audio.playDFPWM(path, volume)
    -- Plays a DFPWM file
    if not speaker then return false end
    if not fs.exists(path) then return false end

    local dfpwm = require("cc.audio.dfpwm")
    local decoder = dfpwm.make_decoder()
    
    local file = fs.open(path, "rb")
    if not file then return false end

    -- Read in chunks
    while true do
        local chunk = file.read(16 * 1024)
        if not chunk then break end
        
        local buffer = decoder(chunk)
        
        while not speaker.playAudio(buffer, volume or 1.0) do
            os.pullEvent("speaker_audio_empty")
        end
    end
    
    file.close()
    return true
end

return audio
