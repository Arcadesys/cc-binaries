"""Render a CC terminal dump (tests/screens.lua output) to PNG with CraftOS-PC's font."""
import json
import os
import sys

from PIL import Image

FONT = os.environ.get("CRAFTOS_FONT", "/Applications/CraftOS-PC.app/Contents/Resources/hdfont.bmp")
PITCH_X, PITCH_Y, OFF, GW, GH = 16, 22, 2, 12, 18

_glyphs = {}


def glyph(code):
    if code not in _glyphs:
        atlas = _glyphs.setdefault("atlas", Image.open(FONT).convert("RGBA"))
        x, y = (code % 16) * PITCH_X + OFF, (code // 16) * PITCH_Y + OFF
        _glyphs[code] = atlas.crop((x, y, x + GW, y + GH)).split()[3]
    return _glyphs[code]


def rgb(v):
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


def render(screen):
    w, h = screen["w"], screen["h"]
    pal = {k: rgb(v) for k, v in screen["palette"].items()}
    img = Image.new("RGB", (w * GW, h * GH))
    for row, line in enumerate(screen["lines"]):
        text, fg, bg = line["text"], line["fg"], line["bg"]
        for col in range(min(w, len(text))):
            x0, y0 = col * GW, row * GH
            img.paste(pal.get(bg[col], (0, 0, 0)), (x0, y0, x0 + GW, y0 + GH))
            code = text[col]
            code = code if isinstance(code, int) else ord(code)
            if code != 32:
                img.paste(pal.get(fg[col], (255, 255, 255)), (x0, y0), glyph(code & 255))
    return img


def render_file(src, dst):
    with open(src, encoding="latin-1") as f:
        screen = json.load(f)
    render(screen).save(dst)


if __name__ == "__main__":
    render_file(sys.argv[1], sys.argv[2])
