#!/usr/bin/env python3
"""Write cc-arcade/manifest.json for get.lua: each installable program and exactly the
files it needs, found by following string-literal require() calls from its entry file."""
from pathlib import Path
import json, re
root = Path(__file__).resolve().parents[1]
repo = root.parent
# name: (title, entry, extra files, description)
PROGRAMS = {
    'pinearcade': ('Pine Arcade', 'pinearcade.lua', [], 'Pine3D menu of every installed game; picks what this computer boots into'),
    'pineslots': ('Pine Slots', 'pineslots.lua', [], 'Pine3D slot machine for a cabinet with a pull arm and three buttons'),
    'pinejack': ('Pine Jack', 'pinejack.lua', [], 'Pine3D blackjack on the three cabinet buttons'),
    'pinebox': ('Pine Shut the Box', 'pinebox.lua', [], 'Pine3D grand prize round with physically thrown dice'),
    'race': ('Pine3D Derby', 'race.lua', ['derby/odds.json'], 'House-run 3D horse race: display, betting station or exhibition'),
    # Tools installed with every program.
    'house': ('House setup', 'house.lua', [], 'House host, station, cashier and display roles (house setup ...)'),
    'config': ('Button setup', 'config.lua', [], 'Teach the LEFT / CENTER / RIGHT cabinet buttons'),
}
# Furball's Pine3D ports live in computercraft_scripts/<folder> and install into a folder
# of the same name. Their vendored Pine3D is the derby's copy byte for byte, so the
# arcade installs it once and the games fall back to derby/vendor when theirs is absent.
FURBALL = {
    'pineball': ('Pine Ball', 'pine-ball', 'ball.lua', 'Baseball against the CPU or a two-player duel'),
    'pinelinks': ('Pine Links', 'pine-links', 'golf.lua', 'Mini golf: a par 3 with a swing meter'),
    'pinelanes': ('Pine Lanes', 'pine-lanes', 'bowl.lua', 'Ten-frame bowling for one to four players'),
    'pinedungeon': ('Pine Dungeon', 'pine-dungeon', 'dungeon.lua', 'First-person dungeon crawler with a map'),
    'pineface': ('Pine Face', 'pine-face', 'face.lua', 'Faceball-style Smiley tag for four players over rednet'),
}
TOOLS = ['house', 'config']
LAUNCHER = 'pinearcade'
# Games whose entry does not take --monitor NAME.
NO_MONITOR = {'race'}
ORDER = [LAUNCHER, 'pineslots', 'pinejack', 'pinebox', 'race', *FURBALL, *TOOLS]
REQ = re.compile(r"""require\s*\(?\s*['"]([\w.\-]+)['"]""")
PINE = ['derby/vendor/Pine3D.lua', 'derby/vendor/betterblittle.lua', 'derby/vendor/LICENSE', 'derby/vendor/REVISION.txt']
def deps(base, entry):
    seen, todo = set(), [entry]
    while todo:
        rel = todo.pop()
        if rel in seen: continue
        seen.add(rel)
        for mod in REQ.findall((base / rel).read_text()):
            path = mod.replace('.', '/') + '.lua'
            if (base / path).exists(): todo.append(path)
    return seen
def entry(path, src=None):
    f = {'path': path, 'size': (repo / (src or f'cc-arcade/{path}')).stat().st_size}
    if src: f['src'] = src
    return f
out = {'programs': {}, 'tools': TOOLS, 'launcher': LAUNCHER, 'order': ORDER}
for name, (title, main, extra, desc) in PROGRAMS.items():
    files = deps(root, main) | set(extra)
    # Pine3D loads betterblittle through a computed path, and its licence travels with it.
    if 'derby/vendor/Pine3D.lua' in files: files |= set(PINE)
    out['programs'][name] = {'title': title, 'entry': main, 'description': desc,
        'files': [entry(f) for f in sorted(files)]}
for name, (title, folder, main, desc) in FURBALL.items():
    base = repo / 'computercraft_scripts' / folder
    found = deps(base, main)
    assert 'vendor/Pine3D.lua' in found, f'{folder} no longer uses vendor/Pine3D.lua'
    for v in PINE:
        mine = base / 'vendor' / Path(v).name
        assert mine.read_bytes() == (root / v).read_bytes(), f'{mine} differs from cc-arcade/{v}'
    files = [entry(f'{folder}/{f}', f'computercraft_scripts/{folder}/{f}') for f in sorted(found) if not f.startswith('vendor/')]
    out['programs'][name] = {'title': title, 'entry': f'{folder}/{main}', 'description': desc,
        'files': sorted(files + [entry(v) for v in PINE], key=lambda f: f['path'])}
for name in NO_MONITOR: out['programs'][name]['monitor'] = False
assert sorted(ORDER) == sorted(out['programs'])
(root / 'manifest.json').write_text(json.dumps(out, indent=1) + '\n')
for name in ORDER:
    p = out['programs'][name]
    print(f"{name:12} {len(p['files']):3} files {sum(f['size'] for f in p['files'])/1024:7.1f} KiB")
every = {f['path']: f['size'] for p in out['programs'].values() for f in p['files']}
print(f"{'all':12} {len(every):3} files {sum(every.values())/1024:7.1f} KiB")
