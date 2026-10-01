#!/usr/bin/env python3
"""Run actual Lua modules with deterministic turtle/world doubles in CraftOS-PC."""
import os
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CRAFTOS = os.environ.get('CRAFTOS_BIN', '/Applications/CraftOS-PC.app/Contents/MacOS/craftos')

def main():
    if not Path(CRAFTOS).is_file():
        print('FAIL: CraftOS-PC unavailable; set CRAFTOS_BIN to its executable', file=sys.stderr)
        return 1
    with tempfile.TemporaryDirectory(prefix='safe-mining-emulator-') as data:
        result = Path(tempfile.mkdtemp(prefix='safe-mining-results-'))
        suite = 'screens.lua' if '--screens' in sys.argv else 'run.lua'
        selection = sys.argv[sys.argv.index('--filter') + 1] if '--filter' in sys.argv else None
        prefix = '_G.__SAFE_TEST_FILTER=' + json.dumps(selection) + ';' if selection else ''
        code = prefix + ('local ok,err=pcall(function() dofile("/src/tests/' + suite + '") end) '
                'if not ok then local f=fs.open("/results/crash.txt","w") f.write(tostring(err)) f.close() end os.shutdown()')
        try:
            proc = subprocess.run([CRAFTOS, '--headless', '--directory', data,
                '--mount-ro', f'/src={ROOT}', '--mount-rw', f'/results={result}', '--exec', code],
                capture_output=True, timeout=240)
        except subprocess.TimeoutExpired:
            print(f'FAIL emulator exceeded 240 seconds. Evidence directory: {result}')
            progress = result / 'progress.txt'
            if progress.exists(): print(progress.read_text())
            return 1
        report = result / 'tests.txt'
        print(f'Evidence directory: {result}')
        if report.exists():
            content = report.read_text(); print(content, end='')
            if proc.returncode == 0 and 'PASS all' in content and 'FAIL' not in content and not (result/'crash.txt').exists():
                return 0
        if (result/'crash.txt').exists(): print('FAIL crash: '+(result/'crash.txt').read_text())
        print(proc.stdout.decode('latin-1')[-1200:]); print(proc.stderr.decode('latin-1')[-1200:])
        return 1

if __name__ == '__main__':
    sys.exit(main())
