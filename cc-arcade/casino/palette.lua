-- Casino palette. Saved and restored by the app like the derby palette.
local M={values={
 0xf4eedf, -- white: reel faces
 0xe8862a, -- orange
 0x8a1c25, -- magenta: shaded die sides
 0x86dcf2, -- lightBlue: diamond crown
 0xf6c933, -- yellow: gold trim, bells
 0x6cc24a, -- lime: stems and leaves
 0xf29bb0, -- pink
 0x45404c, -- gray
 0xbdb8b0, -- lightGray: chrome
 0x2aa0c4, -- cyan: diamond pavilion
 0x7b3fa0, -- purple: plums
 0x1f3a7a, -- blue
 0x6b3a1f, -- brown
 0x2e6b3a, -- green: felt
 0xcf2630, -- red
 0x121016, -- black
}}
function M.apply(t)
 for i,hex in ipairs(M.values) do t.setPaletteColor(2^(i-1),hex) end
end
return M
