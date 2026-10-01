#!/usr/bin/env python3
"""Write cc-arcade/manifest.json for get.lua: each installable program and exactly the
files it needs, found by following string-literal require() calls from its entry file."""
from pathlib import Path
import json, re
root = Path(__file__).resolve().parents[1]
# name: (title, entry, extra files, description)
PROGRAMS = {
    'pineslots': ('Pine Slots', 'pineslots.lua', [], 'Pine3D slot machine for a cabinet with a pull arm and three buttons'),
    'pinejack': ('Pine Jack', 'pinejack.lua', [], 'Pine3D blackjack on the three cabinet buttons'),
    'pinebox': ('Pine Shut the Box', 'pinebox.lua', [], 'Pine3D grand prize round with physically thrown dice'),
    'race': ('Pine3D Derby', 'race.lua', ['derby/odds.json'], 'House-run 3D horse race: display, betting station or exhibition'),
    # Tools installed with every program.
    'house': ('House setup', 'house.lua', [], 'House host, station, cashier and display roles (house setup ...)'),
    'config': ('Button setup', 'config.lua', [], 'Teach the LEFT / CENTER / RIGHT cabinet buttons'),
}
TOOLS = ['house', 'config']
REQ = re.compile(r"""require\s*\(?\s*['"]([\w.\-]+)['"]""")
def deps(entry):
    seen, todo = set(), [entry]
    while todo:
        rel = todo.pop()
        if rel in seen: continue
        seen.add(rel)
        for mod in REQ.findall((root / rel).read_text()):
            path = mod.replace('.', '/') + '.lua'
            if (root / path).exists(): todo.append(path)
    # Pine3D loads betterblittle through a computed path, and its licence travels with it.
    if 'derby/vendor/Pine3D.lua' in seen: seen |= {'derby/vendor/betterblittle.lua', 'derby/vendor/LICENSE', 'derby/vendor/REVISION.txt'}
    return seen
out = {'programs': {}, 'tools': TOOLS}
for name, (title, entry, extra, desc) in PROGRAMS.items():
    files = sorted(deps(entry) | set(extra))
    out['programs'][name] = {'title': title, 'entry': entry, 'description': desc,
        'files': [{'path': f, 'size': (root / f).stat().st_size} for f in files]}
(root / 'manifest.json').write_text(json.dumps(out, indent=1) + '\n')
for name, p in out['programs'].items():
    print(f"{name:10} {len(p['files']):3} files {sum(f['size'] for f in p['files'])/1024:7.1f} KiB")
