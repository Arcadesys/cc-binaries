-- Dig a staircase down N steps (default 5), placing torches every 4 steps.
-- Try: turtlesim/turtle --world quarry --trace turtlesim/examples/stairs.lua 8
local steps = tonumber(... or 5)

local function refuelIfNeeded()
    if turtle.getFuelLevel() == "unlimited" or turtle.getFuelLevel() > 10 then
        return
    end
    for slot = 1, 16 do
        turtle.select(slot)
        if turtle.refuel(0) then
            turtle.refuel(1)
            return
        end
    end
    error("out of fuel")
end

local function findItem(name)
    for slot = 1, 16 do
        local d = turtle.getItemDetail(slot)
        if d and d.name == name then
            return slot
        end
    end
end

for i = 1, steps do
    refuelIfNeeded()
    while turtle.detect() do turtle.dig() end
    assert(turtle.forward())
    turtle.digUp()
    turtle.digDown()
    assert(turtle.down())
    if i % 4 == 0 then
        local torch = findItem("minecraft:torch")
        if torch then
            turtle.select(torch)
            turtle.placeUp()
        end
    end
    print(string.format("step %d/%d, fuel %s", i, steps, turtle.getFuelLevel()))
end
print("Done.")
