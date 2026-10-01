-- A 3x5 pixel font for ranks and numbers, built from merged runs of cells so each row
-- costs few triangles. '1' is one column wide so "10" fits.
local mesh=require('casino.mesh')
local M={}
M.glyphs={
 A={'.#.','#.#','###','#.#','#.#'},['2']={'##.','..#','.#.','#..','###'},['3']={'##.','..#','.#.','..#','##.'},
 ['4']={'#.#','#.#','###','..#','..#'},['5']={'###','#..','##.','..#','##.'},['6']={'.##','#..','###','#.#','###'},
 ['7']={'###','..#','.#.','.#.','.#.'},['8']={'###','#.#','###','#.#','###'},['9']={'###','#.#','###','..#','##.'},
 ['1']={'#','#','#','#','#'},['0']={'###','#.#','#.#','#.#','###'},J={'..#','..#','..#','#.#','.#.'},
 Q={'.#.','#.#','#.#','#.#','.##'},K={'#.#','#.#','##.','#.#','#.#'},
}
-- Width of text in cells.
function M.width(text)
 local n=0; for ch in text:gmatch('.') do n=n+#M.glyphs[ch][1]+.6 end; return n-.6
end
-- Lay text out with point(u,v) mapping text-plane coordinates (u right, v up) to 3D.
-- (u0, v0) is the top-left corner; facing is the outward normal.
function M.draw(m,text,u0,v0,cell,color,point,facing)
 local u=u0
 for ch in text:gmatch('.') do
  local g=M.glyphs[ch]
  for row,line in ipairs(g) do
   local v=v0-(row-1)*cell; local c=1
   while c<=#line do
    if line:sub(c,c)=='#' then
     local e=c; while e<#line and line:sub(e+1,e+1)=='#' do e=e+1 end
     local a,b=u+(c-1)*cell,u+e*cell
     mesh.quad(m,point(a,v),point(b,v),point(b,v-cell),point(a,v-cell),color,facing)
     c=e+1
    else c=c+1 end
   end
  end
  u=u+(#g[1]+.6)*cell
 end
end
-- Text lying flat on the plane y, u along z and v along x.
function M.flat(m,y,text,u0,v0,cell,color)
 M.draw(m,text,u0,v0,cell,color,function(u,v) return {v,y,u} end,{0,1,0})
end
return M
