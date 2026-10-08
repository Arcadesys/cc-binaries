-- Daily Wordle screen, drawn in teletext subpixels (2 x 3 per character): bevelled
-- block tiles with 5x7 letters on a stone backdrop, a blocky WORDLE title, and the
-- animations (tiles flipping, a refused row shaking, a solved row bouncing, confetti).
-- Small screens fall back to flat tiles with text letters. The message line and the
-- button bar are always plain text.
local blittle=require('derby.vendor.betterblittle')
local M={}
-- Palette slots while the game runs. Tests and the app refer to these names.
M.C={bg=colors.black,stone=colors.purple,shadow=colors.brown,text=colors.white,
 hit=colors.green,hitLight=colors.magenta,near=colors.yellow,nearLight=colors.orange,
 miss=colors.gray,missLight=colors.pink,key=colors.lightGray,keyLight=colors.cyan,
 cursor=colors.lightBlue,cursorLight=colors.blue,bad=colors.red,grass=colors.lime}
local C=M.C
M.palette={[C.bg]=0x121213,[C.stone]=0x1e1e21,[C.shadow]=0x08080a,[C.text]=0xf8f8f8,
 [C.hit]=0x538d4e,[C.hitLight]=0x79b46c,[C.near]=0xb59f3b,[C.nearLight]=0xd8c15a,
 [C.miss]=0x3a3a3c,[C.missLight]=0x58585c,[C.key]=0x818384,[C.keyLight]=0xa6a7a9,
 [C.cursor]=0x3d7cc9,[C.cursorLight]=0x6fa6e8,[C.bad]=0xc0392b,[C.grass]=0x8fd14f}
-- Face and highlight for each kind of filled block.
local FACE={hit={C.hit,C.hitLight},near={C.near,C.nearLight},miss={C.miss,C.missLight},
 key={C.key,C.keyLight},cursor={C.cursor,C.cursorLight},bad={C.bad,C.bad}}
local G={
 A={'.###.','#...#','#...#','#####','#...#','#...#','#...#'},B={'####.','#...#','#...#','####.','#...#','#...#','####.'},
 C={'.###.','#...#','#....','#....','#....','#...#','.###.'},D={'####.','#...#','#...#','#...#','#...#','#...#','####.'},
 E={'#####','#....','#....','####.','#....','#....','#####'},F={'#####','#....','#....','####.','#....','#....','#....'},
 G={'.###.','#...#','#....','#.###','#...#','#...#','.####'},H={'#...#','#...#','#...#','#####','#...#','#...#','#...#'},
 I={'.###.','..#..','..#..','..#..','..#..','..#..','.###.'},J={'..###','...#.','...#.','...#.','...#.','#..#.','.##..'},
 K={'#...#','#..#.','#.#..','##...','#.#..','#..#.','#...#'},L={'#....','#....','#....','#....','#....','#....','#####'},
 M={'#...#','##.##','#.#.#','#.#.#','#...#','#...#','#...#'},N={'#...#','#...#','##..#','#.#.#','#..##','#...#','#...#'},
 O={'.###.','#...#','#...#','#...#','#...#','#...#','.###.'},P={'####.','#...#','#...#','####.','#....','#....','#....'},
 Q={'.###.','#...#','#...#','#...#','#.#.#','#..#.','.##.#'},R={'####.','#...#','#...#','####.','#.#..','#..#.','#...#'},
 S={'.####','#....','#....','.###.','....#','....#','####.'},T={'#####','..#..','..#..','..#..','..#..','..#..','..#..'},
 U={'#...#','#...#','#...#','#...#','#...#','#...#','.###.'},V={'#...#','#...#','#...#','#...#','#...#','.#.#.','..#..'},
 W={'#...#','#...#','#...#','#.#.#','#.#.#','#.#.#','.#.#.'},X={'#...#','#...#','.#.#.','..#..','.#.#.','#...#','#...#'},
 Y={'#...#','#...#','.#.#.','..#..','..#..','..#..','..#..'},Z={'#####','....#','...#.','..#..','.#...','#....','#####'},
 ENTER={'......#','......#','..#...#','.##...#','#######','.##....','..#....'},
 DEL={'.......','..#....','.##....','#######','.##....','..#....','.......'},
}
M.glyphs=G
-- Fixed speckle for the stone backdrop, the same on every screen.
local function speckle(x,y)
 local n=(x*73856093+y*19349663)%1000
 return n<90 and C.stone or n<100 and C.shadow or C.bg
end
function M.new(t)
 local view={}
 local w,h,W,H,buf
 local function resize()
  w,h=t.getSize(); W,H=w*2,h*3; buf={}
  for y=1,H do buf[y]={} end
 end
 resize()
 for slot,hex in pairs(M.palette) do t.setPaletteColor(slot,hex) end
 blittle.recomputeColorDistances(t)
 local function px(x,y,c) if x>=1 and x<=W and y>=1 and y<=H then buf[y][x]=c end end
 local function rect(x,y,rw,rh,c) for yy=y,y+rh-1 do for xx=x,x+rw-1 do px(xx,yy,c) end end end
 local function glyph(g,x,y,c) for r,line in ipairs(g) do for k=1,#line do if line:byte(k)==35 then px(x+k-1,y+r-1,c) end end end end
 -- One tile or key, rw x rh pixels at (x, y): style 'empty' (an outline), 'typed'
 -- (bright outline), 'pop' (white outline) or a FACE name (a bevelled block). squash
 -- 0..1 is how flat it is mid-flip. Big blocks are bevelled and carry their letter (a G
-- key) in pixels; small ones are flat so the app's text can sit on them.
 local function block(x,y,rw,rh,style,letter,big,squash)
  local hh=math.max(0,math.floor(rh*(1-(squash or 0))+.5))
  if hh==0 then return end
  local y0=y+math.floor((rh-hh)/2)
  local face=FACE[style]
  local g=big and letter and G[letter]
  local gx,gy=math.floor((rw-#(g and g[1] or '.....'))/2),math.floor((rh-7)/2)
  for row=0,hh-1 do
   local v=math.floor((row+.5)*rh/hh) -- source row in the unsquashed tile
   for u=0,rw-1 do
    local c
    if face and not big then c=face[1]
    elseif face then
     c=(v==0 or u==0) and face[2] or (v==rh-1 or u==rw-1) and C.shadow or face[1]
    else
     local edge=u==0 or v==0 or u==rw-1 or v==rh-1
     c=edge and (style=='pop' and C.text or style=='typed' and C.key or C.miss) or C.bg
    end
    if g and u>=gx then local line=g[v-gy+1]; if line and line:byte(u-gx+1)==35 then c=C.text end end
    px(x+u,y0+row,c)
   end
  end
 end
 -- s: everything the app knows; see wordle.app.
 function view:draw(s)
  local tw,th=t.getSize()
  if tw~=w or th~=h then resize() end
  local L=s.layout
  for y=1,H do local row=buf[y]; for x=1,W do row[x]=speckle(x,y) end end
  local texts={}
  local function text(cx,cy,str,fg,bg) texts[#texts+1]={cx,cy,str,fg,bg} end
  local function cell(cx,cy) return (cx-1)*2+1,(cy-1)*3+1 end
  -- Title band.
  rect(1,1,W,L.tt*3,C.bg)
  if L.tt==3 then
   local word,cols='WORDLE',{C.hit,C.near,C.key,C.hit,C.near,C.hit}
   local x=math.floor((W-(#word*6-1))/2)+1
   for k=1,#word do
    local g=G[word:sub(k,k)]
    glyph(g,x+1,2+1,C.shadow); glyph(g,x,2,cols[k])
    x=x+6
   end
   text(2,2,'DAILY #'..s.puzzle.number,C.key,C.bg)
   if w>=#s.puzzle.date+40 then text(w-#s.puzzle.date,2,s.puzzle.date,C.key,C.bg) end
  else
   local title=('DAILY WORDLE #%d'):format(s.puzzle.number)
   text(math.max(1,math.floor((w-#title)/2)+1),1,title,C.text,C.bg)
   if w>=#title+2*#s.puzzle.date+4 then text(w-#s.puzzle.date,1,s.puzzle.date,C.key,C.bg) end
  end
  -- Board.
  local big=L.th==3
  local TW,TH=L.tw*2,L.th*3
  for r=1,s.tries do
   local row=s.rows[r]
   local current=not row and r==#s.rows+1 and not s.done
   local dx=current and s.shake or 0
   for i=1,s.length do
    local cx,cy=L.gridX+(i-1)*(L.tw+1),L.gridY+(r-1)*(L.th+L.rg)
    local x,y=cell(cx,cy)
    local style,letter,squash='empty',nil,0
    local dy=0
    if row then
     letter=row.word:sub(i,i)
     local p=s.flip(r,i) -- 0 before turning, 1 once turned
     squash=math.sin(math.pi*p)
     style=p>=.5 and row.marks[i] or 'typed'
     dy=s.bounce(r,i)
     if not big then dy=dy>=2 and 3 or 0 end -- small tiles hop a whole row, letter and all
    elseif current then
     letter=s.typed:sub(i,i); if letter=='' then letter=nil end
     style=letter and (s.shake~=0 and 'bad' or s.pop==i and 'pop' or 'typed') or 'empty'
    end
    if not big and style~='empty' and FACE[style]==nil then
     -- Small tiles are flat, so their letter can be text.
     style=style=='typed' and 'key' or style=='pop' and 'cursor' or style
    end
    block(x+dx,y-dy,TW,TH,style,letter,big,squash)
    if letter and not big and squash<.5 and dy%3==0 and dx%2==0 then
     text(cx+dx/2+math.floor(L.tw/2),cy-dy/3,letter,C.text,FACE[style][1])
    end
   end
  end
  -- Keyboard.
  local bigKeys=L.kh==3
  for _,k in ipairs(s.keys) do
   local x,y=cell(k.x,k.y)
   local style=k.cursor and 'cursor' or k.mark or 'key'
   local label=k.value
   block(x,y,k.w*2,L.kh*3,style,label,bigKeys,0)
   if not bigKeys then
    if #label>k.w then label=label=='ENTER' and 'ENT' or label:sub(1,k.w) end
    local f=FACE[style]
    text(k.x+math.floor((k.w-#label)/2),k.y,label,C.text,f and f[1])
   end
  end
  -- Confetti.
  for _,p in ipairs(s.confetti) do px(math.floor(p.x),math.floor(p.y),p.c) end
  blittle.drawBuffer(buf,t)
  for _,tx in ipairs(texts) do
   t.setCursorPos(tx[1],tx[2]); t.setTextColor(tx[4]); t.setBackgroundColor(tx[5] or C.bg); t.write(tx[3])
  end
 end
 return view
end
return M
