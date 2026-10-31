-- Accessible factory launcher. Pine3D is decorative; all choices remain text.
local M = {}
local function line(y, text, fg, bg)
    local w, h = term.getSize()
    if y < 1 or y > h then return end
    term.setCursorPos(1, y)
    term.setBackgroundColor(bg or colors.black)
    term.setTextColor(fg or colors.white)
    term.write((text .. string.rep(" ", w)):sub(1, w))
end
local function scene(w, h, selected)
    if not term.isColor() or w < 30 or h < 15 then return end
    local ok = pcall(function()
        local pine = require("lib_pine3d")
        local mesh = require("lib_pine_mesh")
        local f = pine.newFrame(1, 3, w, h - 9)
        f:setBackgroundColor(colors.black)
        f:setFoV(55)
        mesh.look(f, -6, 2.4, -4, 0, 1, 0)
        local model = {}
        mesh.box(model, -1, 0, -1, 2, .3, 2, colors.gray)
        mesh.box(model, -.7, .3, -.7, 1.4, 1.2, 1.4, colors.lightGray)
        mesh.box(model, -.75, .75, -.5, .08, .45, 1, colors.blue)
        mesh.box(model, -.4, 1.5, -.4, .8, .25, .8, colors.yellow)
        local obj = f:newObject(model, 0, 0, 0, 0, (selected - 1) * 30, 0)
        f:drawObjects({obj}); f:drawBuffer()
    end)
    return ok
end
function M.run(items)
    local selected = 1
    while true do
        local w, h = term.getSize()
        term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear()
        local visual = scene(w, h, selected)
        line(1, " CC FACTORY", colors.white, colors.blue)
        local row = visual and h - 6 or 3
        line(row, " SELECT A SECTION")
        line(row + 1, " < " .. items[selected].text .. " >", colors.black, colors.white)
        line(row + 2, " " .. selected .. " / " .. #items)
        line(row + 4, " Arrows: choose   Enter: open")
        line(row + 5, " Q: exit")
        local event, a, x, y = os.pullEvent()
        if event == "key" then
            if a == keys.left or a == keys.up then selected = (selected - 2) % #items + 1
            elseif a == keys.right or a == keys.down then selected = selected % #items + 1
            elseif a == keys.q or a == keys.escape then return "exit"
            elseif a == keys.enter then
                local result = items[selected].callback()
                if result == "exit" then return result end
            end
        elseif event == "mouse_click" and y == row + 1 then
            local result = items[selected].callback()
            if result == "exit" then return result end
        end
    end
end
return M
