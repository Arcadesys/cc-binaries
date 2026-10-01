local M={values={0xf5f5f5,0xcd783c,0xaf52af,0x8cc5e0,0xffe36b,0x79bc51,0xeea0bc,0x455162,0xc6ced8,0x287e91,0x8751b5,0x17395e,0x886044,0x486b40,0xbc443a,0x10151c}}
function M.apply(t)
 for i,hex in ipairs(M.values) do t.setPaletteColor(2^(i-1),hex) end
end
function M.save(t)
 local p={}
 for i=0,15 do p[i]={t.getPaletteColor(2^i)} end
 return function() for i=0,15 do t.setPaletteColor(2^i,table.unpack(p[i])) end end
end
return M
