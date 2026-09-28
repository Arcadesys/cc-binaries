-- Calculator: four-function with memory, percent and square root.
local ui = arcadeos.lib("ui")
local R = ui.roles()

local KEYS = {
    { "MC", "MR", "M+", "M-", "C" },
    { "7", "8", "9", "/", "CE" },
    { "4", "5", "6", "*", "%" },
    { "1", "2", "3", "-", "sqrt" },
    { "0", ".", "+/-", "+", "=" },
}
local LABEL = { sqrt = "Sq" }

local display = "0"
local acc, op = nil, nil
local fresh = true
local memory = 0
local errorState = false
local rects = {}

local function num() return tonumber(display) or 0 end

local function show(n)
    if n ~= n or n == math.huge or n == -math.huge then
        display, errorState = "Error", true
        return
    end
    local s = ("%.10g"):format(n)
    if #s > 14 then s = ("%.6e"):format(n) end
    display = s
end

local function apply(a, b, o)
    if o == "+" then return a + b end
    if o == "-" then return a - b end
    if o == "*" then return a * b end
    if o == "/" then return b == 0 and 0 / 0 or a / b end
    return b
end

local function press(k)
    if errorState and k ~= "C" then return end
    if k:match("^%d$") then
        if fresh or display == "0" then display = k else display = display .. k end
        fresh = false
    elseif k == "." then
        if fresh then display = "0."; fresh = false
        elseif not display:find("%.") then display = display .. "." end
    elseif k == "C" then
        display, acc, op, fresh, errorState = "0", nil, nil, true, false
    elseif k == "CE" then
        display, fresh = "0", true
    elseif k == "+/-" then
        if display:sub(1, 1) == "-" then display = display:sub(2) elseif display ~= "0" then display = "-" .. display end
    elseif k == "sqrt" then
        show(math.sqrt(num())); fresh = true
    elseif k == "%" then
        show((acc or 0) * num() / 100); fresh = true
    elseif k == "MC" then memory = 0
    elseif k == "MR" then show(memory); fresh = true
    elseif k == "M+" then memory = memory + num(); fresh = true
    elseif k == "M-" then memory = memory - num(); fresh = true
    elseif k == "+" or k == "-" or k == "*" or k == "/" then
        if op and not fresh then show(apply(acc, num(), op)) end
        acc, op, fresh = num(), k, true
    elseif k == "=" then
        if op then show(apply(acc, num(), op)) end
        acc, op, fresh = nil, nil, true
    end
end

local function draw()
    local w, h = term.getSize()
    ui.fill(1, 1, w, h, R.window)
    local bw = math.max(3, math.floor((w - 1) / 5))
    local gridW = bw * 5
    local x0 = math.floor((w - gridW) / 2) + 1
    local gap = h >= 13 and 1 or 0
    local roomy = h >= 9
    local dispW = gridW - 1
    local shown = display
    if #shown > dispW - 2 then shown = shown:sub(-(dispW - 2)) end
    local mem = memory ~= 0 and "M" or " "
    ui.text(x0, roomy and 2 or 1, mem .. (" "):rep(dispW - 1 - #shown) .. shown, R.text, R.scroll)
    rects = {}
    local y = roomy and 4 or 2
    for _, row in ipairs(KEYS) do
        for c, k in ipairs(row) do
            local label = LABEL[k] or k
            local x = x0 + (c - 1) * bw
            local isOp = c >= 4 or not k:match("^[%d.]") and k ~= "+/-"
            local bg = isOp and R.titleActive or R.scroll
            local fg = isOp and R.titleActiveText or R.text
            ui.fill(x, y, bw - 1, 1, bg)
            ui.text(x + math.floor((bw - 1 - #label) / 2), y, label, fg, bg)
            rects[#rects + 1] = { x = x, y = y, w = bw - 1, h = 1, key = k }
        end
        y = y + 1 + gap
    end
end

local KEYMAP = {
    [keys.enter] = "=", [keys.numPadEnter] = "=", [keys.backspace] = "CE", [keys.delete] = "C",
}
local CHARMAP = { ["+"] = "+", ["-"] = "-", ["*"] = "*", ["/"] = "/", ["="] = "=", ["."] = ".",
    ["%"] = "%", r = "sqrt", c = "C" }

arcadeos.setMenus({
    { label = "Edit", items = { { id = "copy", label = "Copy" }, { id = "paste", label = "Paste" } } },
})

while true do
    draw()
    local ev = { os.pullEvent() }
    if ev[1] == "mouse_click" then
        for _, r in ipairs(rects) do
            if ui.inRect(r, ev[3], ev[4]) then press(r.key) end
        end
    elseif ev[1] == "char" then
        local c = ev[2]
        if c:match("%d") then press(c) elseif CHARMAP[c] then press(CHARMAP[c]) end
    elseif ev[1] == "key" and KEYMAP[ev[2]] then
        press(KEYMAP[ev[2]])
    elseif ev[1] == "arcadeos_menu" then
        if ev[2] == "copy" then arcadeos.setClipboard(display)
        elseif ev[2] == "paste" then
            local n = tonumber(arcadeos.getClipboard() or "")
            if n then show(n); fresh = true end
        end
    end
end
