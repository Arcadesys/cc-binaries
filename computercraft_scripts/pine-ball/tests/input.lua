local input = require("lib.input")
local k = keys
assert(input.action({"key", k.space, false}, {}) == "swing")
assert(input.action({"key", k.space, true}, {}) == nil, "repeat never re-swings")
assert(input.action({"key", k.left, false}, {}) == "hold_left" and input.action({"key_up", k.left}, {}) == "release_left")
assert(input.action({"key", k.up, true}, {}) == "hold_up", "held arrows keep aiming")
assert(input.action({"key", k.three, false}, {}) == "pitch_3" and input.action({"key", k.e, false}, {}) == "throw")
local buttons = {{id = "swing", x = 1, y = 10, w = 10, h = 2}}
assert(input.action({"monitor_touch", "m", 2, 11}, buttons, "m") == "swing")
assert(input.action({"monitor_touch", "other", 2, 11}, buttons, "m") == nil)
assert(input.action({"mouse_click", 1, 2, 11}, buttons, nil) == "swing" and input.action({"mouse_click", 1, 2, 11}, buttons, "m") == nil)
return true
