-- Stop a job partway (as if Q was pressed), then resume it, in one world:
--   turtlesim/turtle --root cc-turtleos --world cc-turtleos/tests/world_mine.lua \
--     cc-turtleos/tests/stop_resume.lua miner branch 150 length=24 branch=8
package.path = "/?.lua;/?/init.lua;" .. package.path
local jobs = require("turtleos.lib.jobs")
local nav = require("turtleos.lib.nav")
jobs.setBase("turtleos")
local args = { ... }
local job = jobs.load(args[1], args[2])
local stopAfter = tonumber(args[3])
HARD = args[#args] == "hard"
if HARD then table.remove(args) end
local opts = jobs.options(job)
for i = 4, #args do
    local k, v = args[i]:match("^(%w+)=(.*)$")
    if v == "true" then v = true elseif v == "false" then v = false else v = tonumber(v) or v end
    opts[k] = v
end

local forward, moves = turtle.forward, 0
turtle.forward = function()
    moves = moves + 1
    if moves == stopAfter then os.queueEvent("key", keys.q) if HARD then os.queueEvent("key", keys.q) end end
    return forward()
end

print("FIRST: " .. tostring(jobs.run(job, opts, false)))
-- turtlesim's fast sleep re-queues events, so drop any leftover copy of
-- the Q press before resuming.
os.queueEvent("drained")
repeat until os.pullEvent() == "drained"
local p = nav.get()
print(string.format("AT %d,%d,%d progress %s", p.x, p.y, p.z, textutils.serialize(jobs.progress(job), { compact = true })))
print("RESUMED: " .. tostring(jobs.run(job, opts, true)))
print("PROGRESS AFTER: " .. tostring(jobs.progress(job)))
