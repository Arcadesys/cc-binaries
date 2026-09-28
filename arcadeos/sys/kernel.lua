-- ArcadeOS kernel: process table, event routing, tiling window manager glue.
local theme = require("sys.theme")
local wm = require("sys.wm")
local chrome = require("sys.chrome")
local apps = require("sys.apps")
local idle = require("sys.idle")

local VERSION = "1.00"

local Kernel = {}
Kernel.__index = Kernel
Kernel.VERSION = VERSION

local INPUT = { key = true, key_up = true, char = true, paste = true, terminate = true, file_transfer = true }
local MOUSE = { mouse_click = true, mouse_up = true, mouse_drag = true, mouse_scroll = true }
local WAKE = "arcadeos_wake"

function Kernel.new(opts)
    local k = setmetatable({}, Kernel)
    k.root = fs.combine(opts.root or "arcadeos", "")
    k.parent = opts.parent or term.current()
    k.W, k.H = k.parent.getSize()
    k.shell = opts.shell
    k.env = opts.env or {}
    k.procs = {}
    k.nextId = 1
    k.clock = 0
    k.ownTimers = {}
    k.modals = {}
    k.lastInput = os.epoch("utc")
    k.dirty = true
    k.libs = {}
    k.appList = apps.scan(k.root, k.env)
    k.hostPath = "/" .. fs.combine(k.root, "sys/host.lua")
    k.api = k:makeApi()
    k.compat = k:makeCompat()
    return k
end

--------------------------------------------------------------------------
-- Process helpers

function Kernel:byId(id)
    for _, p in ipairs(self.procs) do
        if p.id == id then return p end
    end
end

function Kernel:post(p, ...)
    if p.dead then return end
    p.inbox[#p.inbox + 1] = table.pack(...)
    os.queueEvent(WAKE)
end

function Kernel:resume(p, ...)
    if p.dead or coroutine.status(p.co) ~= "suspended" then return end
    local prevRunning, prevTerm = self.running, term.current()
    self.running = p
    term.redirect(p.term)
    local ok, res = coroutine.resume(p.co, ...)
    if not p.dead then p.term = term.current() end
    term.redirect(prevTerm)
    self.running = prevRunning
    if p.killed then
        p.dead = true
    elseif not ok then
        p.dead, p.error = true, res
    elseif coroutine.status(p.co) == "dead" then
        p.dead = true
    else
        p.filter = res
    end
end

function Kernel:deliver(p, ev, ...)
    if p.dead then return end
    if coroutine.status(p.co) ~= "suspended" then
        return self:post(p, ev, ...)
    end
    if p.filter == nil or p.filter == ev or ev == "terminate" then
        self:resume(p, ev, ...)
    end
end

function Kernel:flushInboxes()
    local again = true
    while again do
        again = false
        for _, p in ipairs({ table.unpack(self.procs) }) do
            if #p.inbox > 0 and not p.dead and coroutine.status(p.co) == "suspended" then
                local ev = table.remove(p.inbox, 1)
                self:deliver(p, table.unpack(ev, 1, ev.n))
                again = true
            end
        end
    end
end

function Kernel:broadcast(ev)
    for _, p in ipairs({ table.unpack(self.procs) }) do
        self:deliver(p, table.unpack(ev, 1, ev.n))
    end
end

--------------------------------------------------------------------------
-- Spawning

function Kernel:spawn(spec)
    local W, H = self.W, self.H
    local p = {
        id = self.nextId,
        title = spec.title or "Untitled",
        icon = spec.icon or "EXE",
        app = spec.app,
        pref = spec.display or "tile",
        native = spec.native or false,
        inbox = {},
        lastFocus = 0,
    }
    self.nextId = self.nextId + 1
    local min = spec.min
    if min then
        if min[1] > W or min[2] > H - 1 then
            p.pref = "full"
        elseif p.pref == "tile" and min[2] > H - wm.ICON_ROWS - 1 then
            p.pref = "zoom"
        end
    end
    p.zoomed = p.pref ~= "tile"
    if spec.fixedTitle ~= false and spec.app then p.fixedTitle = true end

    theme.apply(self.parent)
    p.win = window.create(self.parent, 1, 1, W, H, false)
    theme.apply(p.win)
    p.win.setBackgroundColor(colors.black)
    p.win.setTextColor(colors.white)
    p.win.clear()
    p.term = p.win

    local k = self
    if spec.raw then
        local args = spec.args or { n = 0 }
        p.co = coroutine.create(function()
            os.run(spec.env or {}, spec.path, table.unpack(args, 1, args.n))
        end)
    else
        local args = spec.args or {}
        p.co = coroutine.create(function()
            local env = { shell = k.shell, multishell = k.compat }
            os.run(env, "/rom/programs/shell.lua", k.hostPath, spec.mode or "app", spec.entry, table.unpack(args))
        end)
    end

    table.insert(self.procs, p)
    if spec.focus == false then
        self.clock = self.clock + 1
        p.lastFocus = self.clock
        self:enforceCapacity(self.focus)
    else
        self:focusProc(p)
    end
    self:applyLayout()
    p.started = true
    self:resume(p)
    self.dirty = true
    return p
end

function Kernel:launch(id, ...)
    local m = apps.find(self.appList, id)
    if not m then return nil, "No such application: " .. tostring(id) end
    local why = apps.missing(m, self.env)
    if why then
        self:showModal(m.name, why, { "OK" })
        return nil, why
    end
    local args = { table.unpack(m.args) }
    for _, a in ipairs({ ... }) do args[#args + 1] = a end
    local p = self:spawn({
        app = m, title = m.name, icon = m.icon, display = m.display, min = m.min,
        native = m.native, entry = m.entry, args = args, mode = m.hold and "file" or "app",
    })
    return p.id
end

function Kernel:runFile(path, ...)
    return self:spawn({
        title = fs.getName(path), icon = "EXE", entry = path, args = { ... }, mode = "file",
    }).id
end

function Kernel:open(path)
    local ext = path:match("%.([^./]+)$")
    if ext then
        local m = apps.forExtension(self.appList, ext)
        if m then return self:launch(m.id, path) end
    end
    if not ext or ext:lower() == "lua" then return self:runFile(path) end
    local np = apps.find(self.appList, "notepad")
    if np then return self:launch("notepad", path) end
    return self:runFile(path)
end

--------------------------------------------------------------------------
-- Focus, tiling, iconize, zoom, close

function Kernel:tiles()
    local list = {}
    for _, p in ipairs(self.procs) do
        if not p.dead and not p.iconic and not p.zoomed then list[#list + 1] = p end
    end
    return list
end

function Kernel:enforceCapacity(keep)
    local tiles, max = self:tiles(), wm.maxTiles(self.W, self.H)
    while #tiles > max do
        local lru
        for _, t in ipairs(tiles) do
            if t ~= keep and (not lru or t.lastFocus < lru.lastFocus) then lru = t end
        end
        if not lru then break end
        lru.iconic = true
        tiles = self:tiles()
    end
end

function Kernel:focusProc(p)
    local old = self.focus
    if old and old ~= p and not old.dead and old.zoomed and not old.iconic then
        if old.pref == "tile" then old.zoomed = false else old.iconic = true end
    end
    self.clock = self.clock + 1
    if p then
        p.lastFocus = self.clock
        p.iconic = false
    end
    self.focus = p
    if p and not p.zoomed then self:enforceCapacity(p) end
    self.dirty = true
end

function Kernel:mostRecent(except)
    local best
    for _, p in ipairs(self.procs) do
        if p ~= except and not p.dead and not p.iconic and (not best or p.lastFocus > best.lastFocus) then
            best = p
        end
    end
    return best
end

function Kernel:iconize(p)
    p.iconic = true
    if p.pref == "tile" then p.zoomed = false end
    if self.focus == p then self.focus = nil; self:focusProc(self:mostRecent(p)) end
    self.dirty = true
end

function Kernel:toggleZoom(p)
    if p.pref ~= "tile" then return end
    p.zoomed = not p.zoomed
    self:focusProc(p)
end

function Kernel:cycle()
    local list = {}
    for _, p in ipairs(self.procs) do if not p.dead then list[#list + 1] = p end end
    if #list == 0 then return end
    local idx = 0
    for i, p in ipairs(list) do if p == self.focus then idx = i end end
    self:focusProc(list[idx % #list + 1])
end

function Kernel:kill(p)
    p.killed, p.dead = true, true
    self.dirty = true
end

function Kernel:close(p)
    if p.app and p.app.id == "executive" and not self.exiting then
        return self:requestExit()
    end
    self:deliver(p, "terminate")
    if not p.dead and not p.native then self:kill(p) end
    self.dirty = true
end

function Kernel:requestExit()
    self:showModal("ArcadeOS", "This will end your ArcadeOS session.", { "OK", "Cancel" }, function(i)
        if i == 1 then self:shutdown() end
    end)
end

function Kernel:shutdown()
    self.exiting = true
    for _, p in ipairs({ table.unpack(self.procs) }) do
        self:deliver(p, "terminate")
        self:kill(p)
    end
end

function Kernel:reap()
    local changed, wasMax = false, false
    for i = #self.procs, 1, -1 do
        local p = self.procs[i]
        if p.dead then
            table.remove(self.procs, i)
            p.win.setVisible(false)
            changed = true
            if p.zoomed then wasMax = true end
            if self.drag == p then self.drag = nil end
            if self.saver == p then self.saver = nil end
            if self.menu and self.menu.proc == p then self.menu = nil end
            if p.error and not self.exiting then
                self:showModal("Application Error",
                    (p.title or "Program") .. " has stopped.\n" .. tostring(p.error), { "OK" })
            end
            if self.focus == p then
                self.focus = nil
                local nextP = self:mostRecent(p)
                if nextP then self:focusProc(nextP) end
            end
            if p.app and p.app.id == "executive" and not self.exiting then
                self.respawnExecutive = true
            end
        end
    end
    if changed then
        if wasMax then theme.apply(self.parent) end
        self.dirty = true
    end
    if self.respawnExecutive then
        self.respawnExecutive = false
        if not self:launch("executive") then self:shutdown() end
    end
end

--------------------------------------------------------------------------
-- Layout and drawing

function Kernel:computeFrames()
    local W, H = self.W, self.H
    local frames, order = {}, {}
    local f = self.focus
    if f and not f.dead and not f.iconic and f.zoomed then
        local chromeOn = f.pref ~= "full"
        frames[f] = wm.frame({ x = 1, y = 1, w = W, h = H }, chromeOn and f.menus ~= nil, chromeOn)
        order[1] = f
        return frames, order, true
    end
    local tiles = self:tiles()
    local rects = wm.layout(#tiles, W, H)
    for i, p in ipairs(tiles) do
        frames[p] = wm.frame(rects[i], p.menus ~= nil, true)
        order[i] = p
    end
    return frames, order, false
end

function Kernel:icons()
    local list = {}
    for _, p in ipairs(self.procs) do
        if not p.dead and (p.iconic or (p.zoomed and p ~= self.focus)) then list[#list + 1] = p end
    end
    return list
end

function Kernel:applyLayout()
    local t, W, H = self.parent, self.W, self.H
    local frames, order, maxed = self:computeFrames()
    self.frames, self.order, self.maxed = frames, order, maxed

    for _, p in ipairs(self.procs) do
        if not frames[p] then p.win.setVisible(false) end
    end
    if not (maxed and self.focus.pref == "full") then theme.apply(t) end

    t.setCursorBlink(false)
    chrome.fill(t, 1, 1, W, H, theme.role.desktop)

    for _, p in ipairs(order) do
        local fr = frames[p]
        local c = fr.client
        local x, y = p.win.getPosition()
        local w, h = p.win.getSize()
        if x ~= c.x or y ~= c.y or w ~= c.w or h ~= c.h then
            p.win.reposition(c.x, c.y, c.w, c.h)
            if p.started and (w ~= c.w or h ~= c.h) then self:post(p, "term_resize") end
        end
        if p.win.isVisible() then p.win.redraw() else p.win.setVisible(true) end
    end

    if not maxed then
        for _, d in ipairs(wm.dividers(#order, W, H)) do
            chrome.fill(t, d.x, d.y, d.w, d.h, theme.role.border)
        end
        local icons = self:icons()
        for i, slot in ipairs(wm.iconSlots(#icons, W, H)) do
            chrome.drawIcon(t, slot, icons[i].icon, icons[i].title, false)
        end
        self.iconHits = { list = icons, slots = wm.iconSlots(#icons, W, H) }
    else
        self.iconHits = nil
    end
    for _, p in ipairs(order) do self:drawFrameChrome(p) end
    self.dirty = false
end

function Kernel:drawFrameChrome(p, openIndex)
    local fr = self.frames and self.frames[p]
    if not fr or not fr.title then return end
    chrome.drawTitle(self.parent, fr.title, p.title, p == self.focus, p.zoomed)
    if fr.menu then chrome.drawMenuBar(self.parent, fr.menu, p.menus, openIndex) end
end

function Kernel:restoreCursor()
    local f = self.focus
    if f and not f.dead and f.win.isVisible() and not self.menu and not self.modals[1] then
        f.win.restoreCursor()
    else
        self.parent.setCursorBlink(false)
    end
end

function Kernel:render()
    self:applyLayout()
    local t = self.parent
    if self.menu or self.modals[1] then
        for _, p in ipairs(self.procs) do p.win.setVisible(false) end
    end
    if self.menu then
        local m = self.menu
        if m.kind == "bar" then self:drawFrameChrome(m.proc, m.index) end
        chrome.drawDropdown(t, m.rect, m.items, m.sel, self.W, self.H)
    end
    if self.modals[1] then
        chrome.drawBox(t, self.modals[1].layout, self.modals[1].sel)
    end
    self:restoreCursor()
end

--------------------------------------------------------------------------
-- Modal boxes (kernel-level)

function Kernel:showModal(title, text, buttons, cb)
    self.modals[#self.modals + 1] = {
        layout = chrome.boxLayout(self.W, self.H, title, text, buttons),
        sel = 1, cb = cb, count = #buttons,
    }
    self.dirty = true
end

function Kernel:closeModal(index)
    local m = table.remove(self.modals, 1)
    self.dirty = true
    if m and m.cb then m.cb(index) end
end

function Kernel:modalInput(ev)
    local m = self.modals[1]
    local name = ev[1]
    if name == "key" then
        local key = ev[2]
        if key == keys.left or (key == keys.tab and self.shift) then
            m.sel = (m.sel - 2) % m.count + 1
        elseif key == keys.right or key == keys.tab then
            m.sel = m.sel % m.count + 1
        elseif key == keys.enter or key == keys.numPadEnter or key == keys.space then
            self:closeModal(m.sel)
        elseif key == keys.escape or key == keys.backspace then
            self:closeModal(m.count)
        end
        self.dirty = true
    elseif name == "mouse_click" then
        for i, b in ipairs(m.layout.buttons) do
            if ev[4] == b.y and ev[3] >= b.x and ev[3] < b.x + b.w then
                self:closeModal(i)
                return
            end
        end
    end
end

--------------------------------------------------------------------------
-- Menus

function Kernel:systemItems(p)
    return {
        { id = "restore", label = "Restore", disabled = not (p.iconic or (p.zoomed and p.pref == "tile")) },
        { id = "iconize", label = "Iconize" },
        { id = "zoom", label = p.zoomed and "Unzoom" or "Zoom", disabled = p.pref ~= "tile" },
        "-",
        { id = "close", label = "Close" },
    }
end

function Kernel:openMenu(p, kind, index)
    local fr = self.frames and self.frames[p]
    if not fr or not fr.title then return end
    local items, ax, ay
    if kind == "system" then
        items, ax, ay = self:systemItems(p), fr.title.x, fr.title.y + 1
    else
        if not (p.menus and fr.menu and p.menus[index]) then return end
        items = p.menus[index].items or {}
        for _, sp in ipairs(chrome.menuSpans(p.menus, fr.menu)) do
            if sp.index == index then ax = sp.x1 end
        end
        ax, ay = ax or fr.menu.x, fr.menu.y + 1
    end
    if #items == 0 then return end
    local sel = 1
    while items[sel] and (items[sel] == "-" or items[sel].disabled) do sel = sel + 1 end
    self.menu = {
        proc = p, kind = kind, index = index, items = items, sel = sel,
        rect = chrome.dropdownRect(items, ax, ay, self.W, self.H),
    }
    self.dirty = true
end

function Kernel:chooseMenu(i)
    local m = self.menu
    self.menu = nil
    self.dirty = true
    local it = m.items[i]
    if type(it) ~= "table" or it.disabled then return end
    local p = m.proc
    if m.kind == "system" then
        if it.id == "restore" then
            if p.zoomed and p.pref == "tile" then p.zoomed = false end
            self:focusProc(p)
        elseif it.id == "iconize" then self:iconize(p)
        elseif it.id == "zoom" then self:toggleZoom(p)
        elseif it.id == "close" then self:close(p) end
    else
        self:post(p, "arcadeos_menu", it.id)
    end
end

local function stepItem(items, sel, dir)
    local n = #items
    for _ = 1, n do
        sel = (sel - 1 + dir) % n + 1
        local it = items[sel]
        if it ~= "-" and not it.disabled then return sel end
    end
    return sel
end

function Kernel:menuInput(ev)
    local m = self.menu
    local name = ev[1]
    self.dirty = true
    if name == "key" then
        local key = ev[2]
        if key == keys.up then m.sel = stepItem(m.items, m.sel, -1)
        elseif key == keys.down then m.sel = stepItem(m.items, m.sel, 1)
        elseif key == keys.enter or key == keys.numPadEnter then self:chooseMenu(m.sel)
        elseif key == keys.escape or key == keys.backspace then self.menu = nil
        elseif (key == keys.left or key == keys.right) and m.kind == "bar" then
            local n = #m.proc.menus
            self:openMenu(m.proc, "bar", (m.index - 1 + (key == keys.right and 1 or -1)) % n + 1)
        end
    elseif name == "mouse_click" then
        local x, y = ev[3], ev[4]
        local hit = chrome.dropdownHit(m.rect, m.items, x, y)
        if hit then return self:chooseMenu(hit) end
        if hit == false then return end
        local fr = self.frames[m.proc]
        if m.kind == "bar" and fr.menu and y == fr.menu.y then
            for _, sp in ipairs(chrome.menuSpans(m.proc.menus, fr.menu)) do
                if x >= sp.x1 and x <= sp.x2 then
                    if sp.index == m.index then self.menu = nil
                    else self:openMenu(m.proc, "bar", sp.index) end
                    return
                end
            end
        end
        self.menu = nil
    end
end

--------------------------------------------------------------------------
-- Input routing

function Kernel:hitTest(x, y)
    for _, p in ipairs(self.order or {}) do
        local fr = self.frames[p]
        if fr.title and y == fr.title.y and x >= fr.title.x and x < fr.title.x + fr.title.w then
            return p, "title", fr
        end
        if fr.menu and y == fr.menu.y and x >= fr.menu.x and x < fr.menu.x + fr.menu.w then
            return p, "menu", fr
        end
        if wm.contains(fr.client, x, y) then return p, "client", fr end
    end
    if self.iconHits then
        for i, slot in ipairs(self.iconHits.slots) do
            if wm.contains(slot, x, y) then return self.iconHits.list[i], "icon" end
        end
    end
end

local function isCtrl(key) return key == keys.leftCtrl or key == keys.rightCtrl end
local function isShift(key) return key == keys.leftShift or key == keys.rightShift end

function Kernel:onKey(ev)
    local name, key = ev[1], ev[2]
    if name == "key" and isCtrl(key) then self.ctrl = true end
    if name == "key_up" and isCtrl(key) then self.ctrl = false end
    if name == "key" and isShift(key) then self.shift = true end
    if name == "key_up" and isShift(key) then self.shift = false end

    if name == "char" and self.swallowUntil and os.epoch("utc") <= self.swallowUntil then
        self.swallowUntil = nil
        return
    end
    if self.modals[1] then return self:modalInput(ev) end
    if self.menu then return self:menuInput(ev) end

    if name == "key" and self.ctrl then
        local chord
        if key == keys.tab then chord = function() self:cycle() end
        elseif key == keys.w then chord = function() if self.focus then self:close(self.focus) end end
        elseif key == keys.m then chord = function()
            local f = self.focus
            if f and f.menus and self.frames[f] and self.frames[f].menu then self:openMenu(f, "bar", 1)
            elseif f then self:openMenu(f, "system") end
        end
        end
        if chord then
            self.swallowUntil = os.epoch("utc") + 100
            chord()
            return
        end
    end
    if self.focus and not self.focus.dead then
        self:deliver(self.focus, table.unpack(ev, 1, ev.n))
    end
end

function Kernel:toClient(p, ev)
    local c = self.frames[p].client
    return ev[1], ev[2], ev[3] - c.x + 1, ev[4] - c.y + 1
end

function Kernel:onMouse(ev)
    if self.modals[1] then return self:modalInput(ev) end
    if self.menu then return self:menuInput(ev) end
    local name, x, y = ev[1], ev[3], ev[4]
    if name == "mouse_click" then
        local p, part, fr = self:hitTest(x, y)
        self.drag = nil
        if not p then return end
        if part == "icon" then
            if p.zoomed and p.pref == "tile" then p.zoomed = false end
            return self:focusProc(p)
        end
        local was = self.focus == p
        if not was then self:focusProc(p) end
        if part == "title" then
            local what = chrome.titleHit(fr.title, x)
            if what == "system" then self:openMenu(p, "system")
            elseif what == "iconize" then self:iconize(p)
            elseif what == "zoom" then self:toggleZoom(p) end
        elseif part == "menu" then
            for _, sp in ipairs(chrome.menuSpans(p.menus, fr.menu)) do
                if x >= sp.x1 and x <= sp.x2 then self:openMenu(p, "bar", sp.index) end
            end
        elseif part == "client" and (was or p.zoomed) then
            self.drag = p
            self:deliver(p, self:toClient(p, ev))
        end
    elseif name == "mouse_drag" or name == "mouse_up" then
        local p = self.drag
        if p and not p.dead and self.frames[p] then self:deliver(p, self:toClient(p, ev)) end
        if name == "mouse_up" then self.drag = nil end
    elseif name == "mouse_scroll" then
        local p, part = self:hitTest(x, y)
        if p and part == "client" then self:deliver(p, self:toClient(p, ev)) end
    end
end

function Kernel:handle(ev)
    local name = ev[1]
    if name == WAKE then return end
    if name == "term_resize" then
        self.W, self.H = self.parent.getSize()
        self:enforceCapacity(self.focus)
        self.dirty = true
    elseif name == "timer" and self.ownTimers[ev[2]] then
        local fn = self.ownTimers[ev[2]]
        self.ownTimers[ev[2]] = nil
        fn()
    elseif self.saver and (INPUT[name] or MOUSE[name]) then
        self.lastInput = os.epoch("utc")
        if idle.WAKE[name] or name == "terminate" then idle.stop(self) end
    elseif INPUT[name] then
        self.lastInput = os.epoch("utc")
        self:onKey(ev)
    elseif MOUSE[name] then
        self.lastInput = os.epoch("utc")
        self:onMouse(ev)
    else
        self:broadcast(ev)
    end
end

function Kernel:after(seconds, fn)
    self.ownTimers[os.startTimer(seconds)] = fn
end

--------------------------------------------------------------------------
-- APIs exposed to programs

function Kernel:makeApi()
    local k = self
    local api = { version = VERSION }
    api.root = "/" .. k.root
    function api.getVersion() return VERSION end
    function api.getCurrent() return k.running and k.running.id end
    function api.setTitle(title)
        local p = k.running
        if p then p.title = tostring(title); k.dirty = true end
    end
    function api.setIcon(text)
        local p = k.running
        if p and p.icon ~= text then
            p.icon = tostring(text)
            if p.iconic then k.dirty = true; os.queueEvent(WAKE) end
        end
    end
    function api.isIconic()
        local p = k.running
        return p and (p.iconic or (p.zoomed and k.focus ~= p)) or false
    end
    function api.setMenus(menus)
        local p = k.running
        if not p then return end
        p.menus = menus
        if k.frames and k.frames[p] then k:applyLayout() end
        k.dirty = true
    end
    function api.launch(id, ...) return k:launch(id, ...) end
    function api.run(path, ...) return k:runFile(path, ...) end
    function api.open(path) return k:open(path) end
    function api.apps()
        local out = {}
        for i, m in ipairs(k.appList) do out[i] = m end
        return out
    end
    function api.lib(name)
        if not k.libs[name] then
            local path = "/" .. fs.combine(k.root, "lib/" .. name .. ".lua")
            local fn, err = loadfile(path, nil, _G)
            if not fn then error(err, 2) end
            k.libs[name] = fn()
        end
        return k.libs[name]
    end
    function api.exit() k:requestExit() end
    function api.getSetting(key, default) return settings.get("arcadeos." .. key, default) end
    function api.setSetting(key, value)
        settings.set("arcadeos." .. key, value)
        settings.save()
        if key == "desktop" then theme.load(); k.dirty = true; os.queueEvent(WAKE) end
    end
    function api.freeplay() return settings.get("arcadeos.freeplay", true) end
    function api.getClipboard() return k.clipboard end
    function api.setClipboard(s) k.clipboard = s end
    function api.getScreenSize() return k.W, k.H end
    function api.screensavers() return idle.list(k.saverDir) end
    function api.previewScreensaver(name)
        k.lastInput = os.epoch("utc")
        return idle.start(k, name)
    end
    function api.theme() return theme end
    return api
end

function Kernel:makeCompat()
    local k = self
    return {
        getFocus = function() return k.focus and k.focus.id end,
        setFocus = function(id)
            local p = k:byId(id)
            if not p then return false end
            k:focusProc(p)
            return true
        end,
        getTitle = function(id) local p = k:byId(id); return p and p.title end,
        setTitle = function(id, title)
            local p = k:byId(id)
            if p and not p.fixedTitle then p.title = title; k.dirty = true end
        end,
        getCurrent = function() return k.running and k.running.id end,
        launch = function(env, path, ...)
            return k:spawn({ raw = true, env = env, path = path, args = table.pack(...),
                title = fs.getName(path), focus = false }).id
        end,
        getCount = function() return #k.procs end,
    }
end

--------------------------------------------------------------------------
-- Shims so legacy programs can't take the whole machine down.

function Kernel:installShims()
    local k = self
    self.realReboot, self.realShutdown = os.reboot, os.shutdown
    local function closeCaller(real)
        return function()
            local p = k.running
            if not p then return real() end
            p.killed = true
            while true do coroutine.yield() end
        end
    end
    os.reboot = closeCaller(self.realReboot)
    os.shutdown = closeCaller(self.realShutdown)
    self.prevApi = rawget(_G, "arcadeos")
    _G.arcadeos = self.api
end

function Kernel:removeShims()
    os.reboot, os.shutdown = self.realReboot, self.realShutdown
    _G.arcadeos = self.prevApi
end

--------------------------------------------------------------------------
-- Main loop

function Kernel:step(ev)
    self:flushInboxes()
    self:handle(ev)
    self:flushInboxes()
    self:reap()
    if self.dirty then self:render() else self:restoreCursor() end
end

function Kernel:start(first)
    theme.load()
    self:installShims()
    if first ~= false then idle.attach(self) end
    self.W, self.H = self.parent.getSize()
    theme.apply(self.parent)
    if first ~= false then
        if not self:launch(first or "executive") then
            self:launch("terminal")
        end
    end
    self:render()
end

function Kernel:finish()
    self:removeShims()
    theme.reset(self.parent)
    self.parent.setBackgroundColor(colors.black)
    self.parent.setTextColor(colors.white)
    self.parent.clear()
    self.parent.setCursorPos(1, 1)
    self.parent.setCursorBlink(true)
end

function Kernel:run(first)
    self:start(first)
    local ok, err = pcall(function()
        while not self.exiting or #self.procs > 0 do
            if self.exiting and #self.procs == 0 then break end
            self:step(table.pack(os.pullEventRaw()))
            if self.exiting and #self.procs == 0 then break end
        end
    end)
    self:finish()
    if not ok then error(err, 0) end
end

return Kernel
