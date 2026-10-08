-- Run the menu in a 39x13 window, the size of a real turtle's screen:
--   turtlesim/turtle --root cc-turtleos --world empty --key enter cc-turtleos/tests/preview.lua
local win = window.create(term.current(), 1, 1, 39, 13)
term.current().clear()
term.redirect(win)
shell.run("/turtleos/menu.lua")
