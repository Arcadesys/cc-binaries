local Gallery = require('lib.launcher')
local H = require('helpers')
local function gallery()
    local g, items = Gallery.new(), {}
    for i = 1, 23 do items[i] = { app={ id='app' .. i, name='Program ' .. i, group='Games' } } end
    g:setItems(items)
    g:layout(51, 16)
    return g
end
return {
    { 'gallery keyboard reaches every app across pages', function(T)
        local g = gallery()
        for i = 1, 23 do
            T.eq(g:selected().app.id, 'app' .. i)
            local action, item = g:handle('key', keys.enter)
            T.eq(action, 'activate'); T.eq(item.app.id, 'app' .. i)
            g:handle('key', keys.right); g:layout(51, 16)
        end
        g:handle('key', keys.home); g:handle('key', keys.down)
        T.eq(g.sel, 4, 'down moves one grid row')
        g:handle('key', keys.pageDown); T.eq(g.sel, 10)
        g:handle('key', keys['end']); T.eq(g.sel, 23)
        g:handle('key', keys.left); T.eq(g.sel, 22)
    end },
    { 'gallery resize and refresh preserve selected identity', function(T)
        local g = gallery()
        g:move(17); g:layout(26, 12)
        T.eq(g:selected().app.id, 'app18'); T.eq(g.cols, 1)
        g:layout(15, 7); T.ok(g.compact); T.eq(g:selected().app.id, 'app18')
        local items = {g.items[18], g.items[1]}
        g:setItems(items, true); T.eq(g:selected().app.id, 'app18')
    end },
    { 'gallery mouse targets select before activating', function(T)
        local g = gallery()
        local old = term.redirect(window.create(term.current(), 1, 1, 51, 16, false))
        g:draw(51, 16)
        term.redirect(old)
        local action, item = g:handle('mouse_click', 1, 23, 4)
        T.eq(action, 'select'); T.eq(item.app.id, 'app2')
        action, item = g:handle('mouse_click', 1, 23, 4)
        T.eq(action, 'activate'); T.eq(item.app.id, 'app2')
        g:handle('mouse_scroll', 1); g:layout(51, 16)
        T.eq(g.sel, 8); T.eq(g.page, 2)
        g:handle('mouse_click', 2, 23, 4); T.eq(g.sel, 8, 'right click does not launch')
    end },
    { 'executive opens selected icon through kernel', function(T)
        H.withKernel({ first='executive' }, function(k)
            H.pump(k, 0.1)
            H.send(k, 'key', keys.home, false)
            H.send(k, 'key', keys.enter, false)
            H.pump(k, 0.1)
            T.eq(k.focus.app.id, 'race')
        end)
    end },
    { 'executive offers only the Pine3D games', function(T)
        H.withKernel({ first='executive' }, function(k, parent)
            H.pump(k, 0.1)
            local lines = {}
            for y = 1, select(2, parent.getSize()) do lines[#lines + 1] = H.row(parent, y) end
            local screen = table.concat(lines, '\n')
            -- Page one at 51x19; End reaches the rest (checked below).
            for _, name in ipairs({'Horse Race', 'Pine Ball', 'Pine Dungeon', 'Pine Jack', 'Pine Lanes', 'Pine Links'}) do
                T.ok(screen:find(name, 1, true), name .. ' visible')
            end
            for _, name in ipairs({'Calculator', 'Blackjack', 'Terminal', 'Paint', 'Notepad'}) do
                T.ok(not screen:find(name, 1, true), name .. ' excluded')
            end
            H.send(k, 'key', keys['end'], false)
            H.send(k, 'key', keys.enter, false)
            H.pump(k, 0.1)
            T.eq(k.focus.app.id, 'pineslots', 'last icon is Pine Slots')
        end)
    end },
    { 'empty gallery does not invent a launch target', function(T)
        local g = Gallery.new()
        g:layout(26, 12)
        local _, item = g:handle('key', keys.enter)
        T.eq(item, nil); T.eq(g.pages, 1)
    end },
}
