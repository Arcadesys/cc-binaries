-- Program gallery. Labels and a selection marker carry meaning without colour.
local ui, canvas
local Gallery = {}
Gallery.__index = Gallery

local pictures = {
    calculator = { ' ########## ', ' #        # ', ' ########## ', '            ', ' ## ## ## # ', '            ', ' ## ## ## # ', '            ', ' ## ## #### ' },
    clock = { '   ######   ', ' ##      ## ', ' #   #    # ', ' #   #    # ', ' #   #### # ', ' #        # ', ' #        # ', ' ##      ## ', '   ######   ' },
    control = { '   ##       ', '############', '   ##       ', '        ##  ', '############', '        ##  ', ' ##         ', '############', ' ##         ' },
    notepad = { ' ########## ', ' ## ## ## # ', ' #        # ', ' # ###### # ', ' #        # ', ' # ###### # ', ' #        # ', ' # ####   # ', ' ########## ' },
    paint = { '        ### ', '       #### ', '      ####  ', '     ####   ', '    ####    ', '   ####     ', '  ####      ', ' #####      ', ' ####       ' },
    cards = { '########    ', '#      #    ', '#  ##  #### ', '# #### #  # ', '#  ##  #  # ', '#      #  # ', '########  # ', '    #     # ', '    ####### ' },
    pineball = { '   ######   ', ' ## #  # ## ', ' #  #  #  # ', ' # #    # # ', ' # #    # # ', ' # #    # # ', ' #  #  #  # ', ' ## #  # ## ', '   ######   ' },
    pinelinks = { '     ###### ', '     #####  ', '     ###    ', '     #      ', '     #      ', '     #      ', ' ##  #      ', ' ##  #      ', '############' },
    pinelanes = { '  ##    ##  ', '  ##    ##  ', ' ####  #### ', ' ####  #### ', ' ####  #### ', '            ', '    ####    ', '   ######   ', '    ####    ' },
    pinedungeon = { ' ##  ##  ## ', ' ########## ', '  ########  ', '  ##    ##  ', '  ##    ##  ', '  ##    ##  ', '  ##    ##  ', '  ##    ##  ', '############' },
    music = { '    ########', '    ##    ##', '    ##    ##', '    ##    ##', '    ##    ##', '  ####  ####', ' ##### #####', ' ####  #### ', '            ' },
    terminal = { '############', '#          #', '# ##       #', '#   ##     #', '# ##       #', '#     #### #', '#          #', '#          #', '############' },
    reversi = { '##### ##### ', '##### #   # ', '##### ##### ', '            ', '##### ##### ', '#   # ##### ', '##### ##### ', '            ', '            ' },
    minesweeper = { '     ##     ', ' ##  ##  ## ', '  ########  ', '   ######   ', '############', '   ######   ', '  ########  ', ' ##  ##  ## ', '     ##     ' },
    pineslots = { '############', '#          #', '# ## ## ## #', '#  #  #  # #', '#  #  #  # #', '# #  #  #  #', '#          #', '############', '   ######   ' },
    pinejack = { ' #####      ', ' #   #####  ', ' # A #   #  ', ' #   # K #  ', ' #   #   #  ', ' ##### # #  ', '     #   #  ', '     #####  ', '            ' },
    pinebox = { '############', '# 1 2 3  5 #', '############', '            ', ' ###   ###  ', ' # #   #  # ', ' ###   ###  ', '            ', '############' },
    race = { '############', '##  ##  ##  ', '  ##  ##  ##', '##  ##  ##  ', '############', '##          ', '##          ', '##          ', '##          ' },
    game = { '   ######   ', '  ########  ', ' ### ## ### ', ' ########## ', '############', '##  ####  ##', '##   ##   ##', '###      ###', ' ##      ## ' },
}
local aliases = { blackjack='cards', solitaire='cards', euchre='cards', cantstop='cards',
    jukebox='music', midiplayer='music', designer='notepad', factory='control', turtleos='terminal' }

local function picture(app, x, y, fg, bg)
    local art = pictures[aliases[app.id] or app.id] or pictures[app.group == 'Games' and 'game' or 'terminal']
    local c = canvas.new(6, 3)
    for py, line in ipairs(art) do
        for px = 1, #line do if line:sub(px, px) == '#' then c:set(px, py, fg) end end
    end
    c:draw(x, y, bg)
end

function Gallery.new(uiLib, canvasLib)
    ui = uiLib or require('lib.ui')
    canvas = canvasLib or require('lib.canvas')
    return setmetatable({ items={}, sel=1, page=1, capacity=1, cols=1 }, Gallery)
end
function Gallery:selected() return self.items[self.sel] end
function Gallery:setItems(items, keep)
    local old = keep and self:selected()
    self.items, self.sel = items, 1
    if old then for i, it in ipairs(items) do if it.app.id == old.app.id then self.sel=i end end end
    self.lastClick = nil
end
function Gallery:layout(w, h)
    if w ~= self.w or h ~= self.h then self.lastClick = nil end
    self.w, self.h = w, h
    self.compact = w < 18 or h < 9
    self.cols = self.compact and 1 or math.max(1, math.floor(w / 17))
    self.cols = math.min(self.cols, math.max(1, math.ceil(math.sqrt(#self.items))))
    self.cellW = math.floor(w / self.cols)
    self.cellH = self.compact and 1 or 6
    self.rows = math.max(1, math.floor(math.max(1, h - 3) / self.cellH))
    self.capacity = self.cols * self.rows
    self.sel = math.max(1, math.min(self.sel, #self.items))
    self.page = math.floor((self.sel - 1) / self.capacity) + 1
    self.pages = math.max(1, math.ceil(#self.items / self.capacity))
end
function Gallery:move(n)
    self.sel = math.max(1, math.min(#self.items, self.sel + n))
    self.lastClick = nil
end
function Gallery:draw(w, h)
    self:layout(w, h)
    local R = ui.roles()
    ui.fill(1, 1, w, h, R.window)
    local pager = ('< %d/%d >'):format(self.page, self.pages)
    self.pagerX = math.max(1, w - #pager + 1)
    ui.text(1, 1, ui.pad(' Pine3D Games', w), R.titleActiveText, R.titleActive)
    ui.text(self.pagerX, 1, pager, R.titleActiveText, R.titleActive)
    self.hits = {}
    local first = (self.page - 1) * self.capacity + 1
    for offset = 0, self.capacity - 1 do
        local i, it = first + offset, self.items[first + offset]
        if not it then break end
        local x = (offset % self.cols) * self.cellW + 1
        local y = math.floor(offset / self.cols) * self.cellH + 2
        local cw = self.cellW
        local selected = i == self.sel
        local fg, bg = selected and R.selectText or R.text, selected and R.select or R.window
        ui.fill(x, y, cw, self.cellH, bg)
        if self.compact then
            ui.text(x, y, (selected and '> ' or '  ') .. it.app.name, fg, bg, cw)
        else
            picture(it.app, x + math.floor((cw - 6) / 2), y, fg, bg)
            local lines = ui.wrap(it.app.name, cw - 2)
            for n = 1, math.min(2, #lines) do
                ui.center(y + 2 + n, lines[n], fg, bg, x + 1, cw - 2)
            end
            if selected then ui.text(x, y + 3, '>', fg, bg) end
        end
        self.hits[#self.hits + 1] = { x=x, y=y, w=cw, h=self.cellH, index=i }
    end
    if #self.items == 0 then ui.text(1, 2, 'No programs installed.', R.text, R.window, w) end
    if h >= 4 then
        local it = self:selected()
        ui.text(1, h - 1, ui.pad(it and (it.app.name .. ' / ' .. it.app.group) or '', w), R.text, R.scroll)
        local hint = w >= 45 and 'Arrows: select  Enter: open  PgUp/Dn: more' or 'Enter: open  PgUp/Dn: more'
        ui.text(1, h, ui.pad(hint, w), R.text, R.window)
    end
end
function Gallery:handle(ev, a, x, y)
    if ev == 'key' then
        if a == keys.enter or a == keys.numPadEnter then return 'activate', self:selected()
        elseif a == keys.left then self:move(-1)
        elseif a == keys.right then self:move(1)
        elseif a == keys.up then self:move(-self.cols)
        elseif a == keys.down then self:move(self.cols)
        elseif a == keys.pageUp then self:move(-self.capacity)
        elseif a == keys.pageDown then self:move(self.capacity)
        elseif a == keys.home then self:move(-#self.items)
        elseif a == keys['end'] then self:move(#self.items) end
    elseif ev == 'mouse_scroll' then self:move(a * self.capacity)
    elseif ev == 'mouse_click' and a == 1 then
        if y == 1 and x >= self.pagerX then
            if x < self.pagerX + 2 then self:move(-self.capacity)
            elseif x >= self.w - 1 then self:move(self.capacity) end
            return
        end
        for _, hit in ipairs(self.hits or {}) do
            if ui.inRect(hit, x, y) then
                local now = ui.now()
                local double = self.lastClick and self.lastClick.index == hit.index and now - self.lastClick.time < 500
                self.sel = hit.index
                self.lastClick = { index=hit.index, time=now }
                return double and 'activate' or 'select', self:selected()
            end
        end
        self.lastClick = nil
    end
end
return Gallery
