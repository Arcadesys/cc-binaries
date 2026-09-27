#!/usr/bin/env python3
"""Render the canonical hole JSON as a labeled, high-contrast top-down SVG."""
import html
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "courses/pebble_beach/hole_07.json"
DEST = ROOT / "docs/preview/hole-07-top-down.svg"
RUNTIME = ROOT / "courses/pebble_beach/hole_07.lua"
COLORS = {"rough":"#52764B", "fairway":"#79A95C", "green":"#B9D976", "bunker":"#E8D59B"}

def validate(data):
    assert data["par"] == 3 and data["listed_yards"] == 107 and data["tee_set"] == "Blue"
    assert (data["tee"]["x"],data["tee"]["z"]) == (0,0)
    assert (data["cup"]["x"],data["cup"]["z"]) == (107,0)
    found=set()
    for i,tri in enumerate(data["triangles"]):
        assert tri["material"] in COLORS, "unknown material in triangle %d"%i
        assert all(abs(tri[k]["z"]) <= 22.0-14.0*tri[k]["x"]/107.0+1e-8 for k in ("a","b","c")), "triangle crosses the peninsula shoreline: %d"%i
        a,b,c=(tri[k] for k in ("a","b","c"))
        area=(b["x"]-a["x"])*(c["z"]-a["z"])-(b["z"]-a["z"])*(c["x"]-a["x"])
        assert area < -1e-8, "triangle %d is degenerate or wound away from its upward-facing render normal"%i
        found.add(tri["material"])
    assert found == set(COLORS), "all four terrain materials must appear"

def render(data):
    width, height, margin = 1200, 820, 80
    b = data["bounds"]
    scale = min((width-2*margin)/(b["maxX"]-b["minX"]), (height-2*margin)/(b["maxZ"]-b["minZ"]))
    def xy(p):
        return (margin+(p["x"]-b["minX"])*scale, height-margin-(p["z"]-b["minZ"])*scale)
    pieces=[]
    for tri in data["triangles"]:
        pts=[xy(tri[k]) for k in ("a","b","c")]
        points=" ".join("%.1f,%.1f" % p for p in pts)
        pieces.append('<polygon points="%s" fill="%s" stroke="#243524" stroke-width="0.55"/>' % (points,COLORS[tri["material"]]))
    tee, cup=xy(data["tee"]),xy(data["cup"])
    pieces.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#111" stroke-width="3" stroke-dasharray="9 8"/>'%(tee+cup))
    for p,label,color in ((tee,"TEE • 107 yd", "#101820"),(cup,"CUP • pin inferred", "#101820")):
        x,y=p
        if label.startswith("CUP"):
            pieces.append('<circle cx="%.1f" cy="%.1f" r="8" fill="#fff" stroke="%s" stroke-width="4"/><text x="%.1f" y="%.1f" text-anchor="end" font-size="23" font-weight="700" fill="%s">%s</text>'%(x,y,color,x-13,y-13,color,label))
        else:
            pieces.append('<circle cx="%.1f" cy="%.1f" r="8" fill="#fff" stroke="%s" stroke-width="4"/><text x="%.1f" y="%.1f" font-size="23" font-weight="700" fill="%s">%s</text>'%(x,y,color,x+13,y-13,color,label))
    # Blue ocean is labeled explicitly; land ends at the mesh edge.
    pieces += ['<text x="120" y="155" font-size="28" font-weight="700" fill="#101820">PACIFIC OCEAN</text>',
      '<text x="905" y="275" font-size="20" font-weight="700" fill="#101820">WATER • no ground mesh</text>',
      '<text x="80" y="48" font-size="30" font-weight="700" fill="#101820">PEBBLE BEACH • HOLE 7 • BLUE • PAR 3 • 107 YARDS</text>',
      '<text x="80" y="790" font-size="19" font-weight="700" fill="#101820">TOP-DOWN • north is +z • slopes/pin/shore boundary authored approximations</text>']
    lx,ly=90,730
    for i,(mat,col) in enumerate(COLORS.items()):
        x=lx+i*190
        pieces.append('<rect x="%d" y="%d" width="24" height="24" fill="%s" stroke="#101820" stroke-width="2"/><text x="%d" y="%d" font-size="19" font-weight="700" fill="#101820">%s</text>'%(x,ly,col,x+34,ly+19,html.escape(mat.upper())))
    return '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d"><rect width="100%%" height="100%%" fill="#F5F7F4"/>%s</svg>'%(width,height,width,height,"".join(pieces))

def lua(value):
    if isinstance(value, bool): return "true" if value else "false"
    if isinstance(value, str): return json.dumps(value)
    if isinstance(value, (int,float)): return str(value)
    if isinstance(value, list): return "{"+",".join(lua(v) for v in value)+"}"
    if isinstance(value, dict): return "{"+",".join("["+json.dumps(k)+"]="+lua(v) for k,v in value.items())+"}"
    raise TypeError(value)

def runtime_table(data):
    keys=("schema_version","id","geometry_revision","par","listed_yards","tee_set","units","verification_status","source_refs","tee","cup","playing_line","waterLevel","bounds","surface_regions","approximation_notes")
    lines=["-- Generated from hole_07.json by tools/preview_course.py.","-- Regenerate this runtime table and the top-down preview together.","return {"]
    lines += ["  %s=%s,"%(key,lua(data[key])) for key in keys]
    lines.append("  triangles={")
    for tri in data["triangles"]:
        def pt(p): return "{x=%s,y=%s,z=%s}"%(p["x"],p["y"],p["z"])
        lines.append("    {a=%s,b=%s,c=%s,material=%s},"%(pt(tri["a"]),pt(tri["b"]),pt(tri["c"]),json.dumps(tri["material"])))
    lines += ["  },","}"]
    return "\n".join(lines)+"\n"

if __name__ == "__main__":
    source=Path(sys.argv[1]) if len(sys.argv)>1 else SOURCE
    dest=Path(sys.argv[2]) if len(sys.argv)>2 else DEST
    data=json.loads(source.read_text())
    validate(data)
    dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_text(render(data))
    RUNTIME.write_text(runtime_table(data))
    print("wrote %s and %s (%d triangles)"%(dest,RUNTIME,len(data["triangles"])))
