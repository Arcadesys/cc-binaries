-- Test fixture: records every event it receives into the `log` table from its env.
if menus then arcadeos.setMenus(menus) end
if palette then
    for c, v in pairs(palette) do term.setPaletteColor(c, v) end
end
term.setBackgroundColor(colors.white)
term.setTextColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
term.write(label or "echo")
while true do
    local ev = table.pack(os.pullEventRaw())
    log[#log + 1] = ev
    if ev[1] == "terminate" and not stubborn then return end
    if ev[1] == "do_reboot" then os.reboot() end
    if ev[1] == "do_error" then error("boom") end
    if ev[1] == "term_resize" then
        term.clear()
        term.setCursorPos(1, 1)
        term.write(label or "echo")
    end
end
