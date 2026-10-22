#!/usr/bin/env python3
"""Copy the canonical Pine3D (cc-arcade/derby/vendor) into every Furball game's vendor/.

The copies are deliberate: each computercraft_scripts/pine-* folder is documented as a
self-contained copy-and-run install, and ArcadeOS installs each game's own vendor/.
cc-arcade/tools/manifest.py refuses to run while any copy differs, so after updating
derby/vendor run this, then derby/tools/bundle.py and arcadeos/tools/dev.py files."""
from pathlib import Path
import shutil
root = Path(__file__).resolve().parents[1]
canon = root / 'derby' / 'vendor'
FILES = ['Pine3D.lua', 'betterblittle.lua', 'LICENSE', 'REVISION.txt']
for vendor in sorted((root.parent / 'computercraft_scripts').glob('pine-*/vendor')):
    for name in FILES:
        src, dst = canon / name, vendor / name
        if dst.exists() and dst.read_bytes() == src.read_bytes(): continue
        shutil.copyfile(src, dst)
        print('updated', dst.relative_to(root.parent))
