-- Run one job headless in turtlesim:
--   turtlesim/turtle --root cc-turtleos --world cc-turtleos/tests/world_crops.lua \
--     cc-turtleos/tests/run_job.lua farmer crops length=5 width=5 cycles=1
-- Add a final "resume" argument to resume from saved position and progress.
package.path = "/?.lua;/?/init.lua;" .. package.path
local jobs = require("turtleos.lib.jobs")
jobs.setBase("turtleos")
local args = { ... }
local resume = false
if args[#args] == "resume" then resume = true table.remove(args) end
local job = jobs.load(args[1], args[2])
local opts = jobs.options(job)
for i = 3, #args do
    local k, v = args[i]:match("^(%w+)=(.*)$")
    if v == "true" then v = true elseif v == "false" then v = false else v = tonumber(v) or v end
    opts[k] = v
end
local result = jobs.run(job, opts, resume)
print("RESULT: " .. tostring(result))
