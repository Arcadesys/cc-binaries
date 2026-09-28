-- Runs inside each ArcadeOS process's shell: host.lua <app|file> <entry> [args...]
-- Keeps the window open after a crash (or after any plain program ends) so the
-- user can read the output, like multishell's "Press any key to continue".
local args = { ... }
local mode = table.remove(args, 1)
local entry = table.remove(args, 1)

local ok = shell.execute(entry, table.unpack(args))

if mode == "file" or not ok then
    if term.isColor() then term.setTextColor(ok and colors.lightGray or colors.red) end
    if not ok then print("Program ended with an error.") end
    write("Press any key to close.")
    term.setCursorBlink(false)
    while true do
        local ev = os.pullEvent()
        if ev == "key" or ev == "char" or ev == "mouse_click" then break end
    end
end
