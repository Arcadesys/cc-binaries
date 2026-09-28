local theme = {}

-- EGA 16-color palette mapped onto CC color slots. Orange has no EGA
-- equivalent, so it keeps the CC default to avoid surprising legacy apps.
theme.palette = {
    [colors.white] = 0xFFFFFF,
    [colors.orange] = 0xF2B233,
    [colors.magenta] = 0xFF55FF,
    [colors.lightBlue] = 0x5555FF,
    [colors.yellow] = 0xFFFF55,
    [colors.lime] = 0x55FF55,
    [colors.pink] = 0xFF5555,
    [colors.gray] = 0x555555,
    [colors.lightGray] = 0xAAAAAA,
    [colors.cyan] = 0x00AAAA,
    [colors.purple] = 0xAA00AA,
    [colors.blue] = 0x0000AA,
    [colors.brown] = 0xAA5500,
    [colors.green] = 0x00AA00,
    [colors.red] = 0xAA0000,
    [colors.black] = 0x000000,
}

theme.desktops = {
    { name = "Teal", color = colors.cyan },
    { name = "Gray", color = colors.lightGray },
    { name = "Blue", color = colors.blue },
    { name = "Green", color = colors.green },
    { name = "Black", color = colors.black },
    { name = "Brown", color = colors.brown },
}

theme.role = {
    desktop = colors.cyan,
    desktopText = colors.black,
    titleActive = colors.blue,
    titleActiveText = colors.white,
    titleInactive = colors.white,
    titleInactiveText = colors.black,
    border = colors.black,
    menuBg = colors.white,
    menuText = colors.black,
    menuHiBg = colors.black,
    menuHiText = colors.white,
    menuDisabled = colors.lightGray,
    window = colors.white,
    text = colors.black,
    select = colors.black,
    selectText = colors.white,
    iconBg = colors.white,
    iconText = colors.black,
    iconActive = colors.blue,
    iconActiveText = colors.white,
    scroll = colors.lightGray,
    scrollThumb = colors.gray,
    button = colors.white,
    buttonText = colors.black,
    buttonDefault = colors.blue,
    buttonDefaultText = colors.white,
    shadow = colors.gray,
}

function theme.load()
    local d = settings.get("arcadeos.desktop")
    if type(d) == "number" and theme.palette[d] then
        theme.role.desktop = d
        theme.role.desktopText = (d == colors.black or d == colors.blue or d == colors.brown or d == colors.green)
            and colors.white or colors.black
    end
end

function theme.apply(t)
    if not (t.isColor and t.isColor()) then return end
    for c, rgb in pairs(theme.palette) do
        t.setPaletteColor(c, rgb)
    end
end

function theme.reset(t)
    if not (t.isColor and t.isColor()) then return end
    for c in pairs(theme.palette) do
        t.setPaletteColor(c, term.nativePaletteColor(c))
    end
end

function theme.matches(t)
    for c, rgb in pairs(theme.palette) do
        local r, g, b = t.getPaletteColor(c)
        local want = colors.packRGB(colors.unpackRGB(rgb))
        if colors.packRGB(r, g, b) ~= want then return false end
    end
    return true
end

return theme
