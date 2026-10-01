-- Dump a terminal's text, colours and palette for casino/tools/screens.py.
return function(t,name)
 local w,h=t.getSize(); local pal={}; local lines={}; local hex='0123456789abcdef'
 for i=0,15 do pal[hex:sub(i+1,i+1)]=colors.packRGB(t.getPaletteColor(2^i)) end
 for y=1,h do local text,fg,bg=t.getLine(y); lines[y]={text={text:byte(1,-1)},fg=fg,bg=bg} end
 local f=fs.open('/results/'..name..'.screen.json','w'); f.write(textutils.serializeJSON({w=w,h=h,palette=pal,lines=lines})); f.close()
end
