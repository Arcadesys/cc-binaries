--[[
State: DONE
Cleanup and exit.
--]]

local movement = require("lib_movement")
local logger = require("lib_logger")

local function DONE(ctx)
    if ctx.config.mode == "mine" then return require("lib_safe_miner").step(ctx) end
    logger.log(ctx, "info", "Build complete!")
    movement.goTo(ctx, ctx.origin)
    return "EXIT"
end

return DONE
