local Kernel = require("sys.kernel")
local theme = require("sys.theme")

local H = {}

function H.withKernel(opts, fn)
    if type(opts) == "function" then fn, opts = opts, {} end
    local parent = window.create(term.current(), 1, 1, opts.w or 51, opts.h or 19, true)
    local k = Kernel.new({
        root = "arcadeos", shell = shell, parent = parent,
        env = opts.env or { turtle = false, color = true, speaker = true },
    })
    k:start(opts.first or false)
    local ok, err = pcall(fn, k, parent)
    for _, p in ipairs(k.procs) do k:kill(p) end
    k:reap()
    k:finish()
    if not ok then error(err, 0) end
end

function H.echo(k, opts)
    opts = opts or {}
    local log = {}
    local env = { log = log, label = opts.label, menus = opts.menus, stubborn = opts.stubborn, palette = opts.palette }
    local p = k:spawn({
        raw = true, env = env, path = "/arcadeos/tests/fixtures/echo.lua",
        title = opts.label or "echo", display = opts.display, focus = opts.focus, native = opts.native,
    })
    k:flushInboxes()
    return p, log
end

function H.send(k, ...)
    k:step(table.pack(...))
end

-- Process whatever real events are queued (timers, wakeups) for a moment.
function H.pump(k, seconds)
    local t = os.startTimer(seconds or 0.05)
    while true do
        local ev = table.pack(os.pullEventRaw())
        k:step(ev)
        if ev[1] == "timer" and ev[2] == t then break end
    end
end

function H.find(log, name)
    for i = #log, 1, -1 do
        if log[i][1] == name then return log[i] end
    end
end

function H.count(log, name)
    local n = 0
    for _, ev in ipairs(log) do if ev[1] == name then n = n + 1 end end
    return n
end

function H.paletteIsTheme(t)
    return theme.matches(t)
end

-- Text of screen row y from a window-backed parent.
function H.row(parent, y)
    return (parent.getLine(y))
end

return H
