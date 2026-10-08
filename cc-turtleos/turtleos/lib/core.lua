-- turtleos/lib/core.lua
local logger = require("turtleos.lib.logger")
local jobs = require("turtleos.lib.jobs")
local ui = require("turtleos.lib.ui")

local core = {}

local BOOT_DELAY = 5

-- If a job is set to start on boot, count down and run it. Any key during
-- the countdown goes to the menu instead.
local function autorun()
    local auto = jobs.autorun()
    if not auto then return end
    jobs.setBase("turtleos")
    local job = jobs.load(auto.role, auto.id)
    if not job or job.broken then return end
    local resume = jobs.progress(job) ~= nil
    if job.bootResumeOnly and not resume then return end

    local timer = os.startTimer(1)
    local left = BOOT_DELAY
    while left > 0 do
        ui.clear()
        ui.bar(1, "TurtleOS", ui.fuelText())
        ui.write(2, 4, (resume and "Resuming " or "Starting ") .. job.title, ui.theme.accent)
        ui.write(2, 5, "in " .. left .. "...")
        ui.write(2, 7, "Press any key for the menu", ui.theme.dim)
        local ev, id = os.pullEvent()
        if ev == "key" then return end
        if ev == "timer" and id == timer then
            left = left - 1
            timer = os.startTimer(1)
        end
    end
    jobs.run(job, jobs.options(job), true)
end

function core.init()
    logger.info("TurtleOS initializing...")
    autorun()

    -- The menu handles all user interaction; it returns when the player
    -- picks "Exit to shell".
    while true do
        local success = shell.run("turtleos/menu.lua")
        if success then
            term.clear()
            term.setCursorPos(1, 1)
            return
        end
        logger.error("Menu crashed or failed to load.")
        print("Press any key to retry or 'r' to reboot.")
        local _, key = os.pullEvent("char")
        if key == "r" then os.reboot() end
    end
end

return core
