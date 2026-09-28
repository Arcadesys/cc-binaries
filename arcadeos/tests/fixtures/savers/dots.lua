local w, h = term.getSize()
term.setBackgroundColor(colors.black)
term.clear()
while true do
    term.setCursorPos(math.random(w), math.random(h))
    term.setTextColor(2 ^ math.random(0, 15))
    term.write("*")
    sleep(0.05)
end
