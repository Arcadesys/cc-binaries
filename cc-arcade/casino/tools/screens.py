#!/usr/bin/env python3
"""Turn *.screen.json dumps (term lines + palette) into PNGs, decoding teletext subpixels."""
import json, sys, pathlib
from PIL import Image, ImageDraw
HEX='0123456789abcdef'
def render(path, scale=4):
    d=json.loads(pathlib.Path(path).read_text())
    w,h=d['w'],d['h']; pal={k:((v>>16)&255,(v>>8)&255,v&255) for k,v in d['palette'].items()}
    img=Image.new('RGB',(w*2*scale,h*3*scale)); dr=ImageDraw.Draw(img)
    for y,line in enumerate(d['lines']):
        text=line['text']; text=text if isinstance(text,list) else [ord(c) for c in text]
        for x,ch in enumerate(text):
            fg,bg=pal[line['fg'][x]],pal[line['bg'][x]]
            for sy in range(3):
                for sx in range(2):
                    bit=sy*2+sx
                    if 128<=ch<160: on=bit<5 and (ch-128)>>bit&1
                    else: on=ch!=32 and (sy==1)
                    c=fg if on else bg
                    dr.rectangle([(x*2+sx)*scale,(y*3+sy)*scale,(x*2+sx+1)*scale-1,(y*3+sy+1)*scale-1],fill=c)
    out=str(path).replace('.screen.json','.png'); img.save(out); return out
for p in sys.argv[1:]:
    for f in sorted(pathlib.Path(p).glob('*.screen.json')) if pathlib.Path(p).is_dir() else [pathlib.Path(p)]:
        print(render(f))
