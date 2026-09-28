#!/usr/bin/env python3
"""ArcadeOS developer tool.

  dev.py files            regenerate arcadeos/files.json from layout.json
  dev.py test [NAME...]   run headless tests in CraftOS-PC (all, or named suites)
  dev.py run [--quick]    open the CraftOS-PC GUI booted into ArcadeOS
  dev.py screens OUT_DIR  run the screenshot scenarios and render PNGs
"""
import fnmatch
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OS_DIR = os.path.dirname(HERE)
REPO = os.path.dirname(OS_DIR)
LAYOUT = os.path.join(OS_DIR, "layout.json")
CRAFTOS = os.environ.get("CRAFTOS_BIN", "/Applications/CraftOS-PC.app/Contents/MacOS/craftos")


def load_layout():
    with open(LAYOUT) as f:
        return json.load(f)


def matches(rel, patterns):
    return any(fnmatch.fnmatch(rel, p) for p in patterns)


def mount_files(m):
    src = os.path.join(REPO, m["src"])
    include = m.get("include", ["**"])
    exclude = m.get("exclude", [])
    out = []
    for dirpath, dirnames, filenames in os.walk(src):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith(".") and d != "__pycache__")
        for name in sorted(filenames):
            if name.startswith("."):
                continue
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, src).replace(os.sep, "/")
            if matches(rel, include) and not matches(rel, exclude):
                out.append({
                    "src": m["src"] + "/" + rel,
                    "dest": m["dest"].rstrip("/") + "/" + rel,
                    "size": os.path.getsize(full),
                })
    return out


def cmd_files():
    layout = load_layout()
    result = {"raw_base": layout["raw_base"], "packages": {}}
    for name, pkg in layout["packages"].items():
        files = []
        for m in pkg["mounts"]:
            files.extend(mount_files(m))
        result["packages"][name] = {
            "description": pkg.get("description", ""),
            "required": pkg.get("required", False),
            "size": sum(f["size"] for f in files),
            "files": files,
        }
    path = os.path.join(OS_DIR, "files.json")
    with open(path, "w") as f:
        json.dump(result, f, indent=1)
        f.write("\n")
    for name, pkg in result["packages"].items():
        print(f"{name:8} {len(pkg['files']):4} files {pkg['size'] / 1024:8.1f} KiB")
    return 0


def mount_args():
    seen, args = set(), []
    for pkg in load_layout()["packages"].values():
        for m in pkg["mounts"]:
            if m["dest"] in seen:
                continue
            seen.add(m["dest"])
            args += ["--mount-ro", f"{m['dest']}={os.path.join(REPO, m['src'])}"]
    return args


def craftos(extra, headless=True, data_dir=None):
    if not os.path.exists(CRAFTOS):
        sys.exit(f"CraftOS-PC not found at {CRAFTOS} (set CRAFTOS_BIN)")
    data_dir = data_dir or tempfile.mkdtemp(prefix="arcadeos-emu-")
    cmd = [CRAFTOS, "--directory", data_dir] + (["--headless"] if headless else []) + mount_args() + extra
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=600)


def cmd_test(names):
    results = tempfile.mkdtemp(prefix="arcadeos-results-")
    call_args = ", ".join(['"/arcadeos/tests/run.lua"'] + ['"%s"' % n for n in names])
    code = (
        "local ok, err = pcall(shell.run, " + call_args + ") "
        'if not ok then local h = fs.open("/results/tests.txt", "a") h.writeLine("FAIL runner: "..tostring(err)) h.close() end '
        "os.shutdown()"
    )
    proc = craftos(["--mount-rw", f"/results={results}", "--exec", code])
    out = os.path.join(results, "tests.txt")
    if not os.path.exists(out):
        print(proc.stdout.decode("latin-1")[-3000:])
        print("FAIL: no results written")
        return 1
    text = open(out).read()
    print(text, end="")
    return 0 if any(l.startswith("PASS all") for l in text.splitlines()) else 1


def cmd_run(argv):
    boot = "/arcadeos/boot.lua" + (" --quick" if "--quick" in argv else "")
    data_dir = os.path.join(tempfile.gettempdir(), "arcadeos-dev")
    os.makedirs(data_dir, exist_ok=True)
    subprocess.Popen([CRAFTOS, "--directory", data_dir] + mount_args() + ["--exec", f'shell.run("{boot}")'])
    print(f"CraftOS-PC started (data dir {data_dir})")
    return 0


def cmd_screens(argv):
    if not argv:
        sys.exit("usage: dev.py screens OUT_DIR [SCENARIO...]")
    out_dir = os.path.abspath(argv[0])
    os.makedirs(out_dir, exist_ok=True)
    results = tempfile.mkdtemp(prefix="arcadeos-screens-")
    names = ", ".join('"%s"' % n for n in argv[1:])
    code = ('local ok, err = pcall(shell.run, "/arcadeos/tests/screens.lua"' + (", " + names if names else "") + ') '
            'if not ok then local h = fs.open("/results/error.txt", "w") h.write(tostring(err)) h.close() end '
            'os.shutdown()')
    proc = craftos(["--mount-rw", f"/results={results}", "--exec", code])
    if os.path.exists(os.path.join(results, "error.txt")):
        print(open(os.path.join(results, "error.txt")).read())
    sys.path.insert(0, HERE)
    import render
    count = 0
    for name in sorted(os.listdir(results)):
        if name.endswith(".screen.json"):
            base = name[: -len(".screen.json")]
            render.render_file(os.path.join(results, name), os.path.join(out_dir, base + ".png"))
            count += 1
    for name in os.listdir(results):
        if name.endswith(".txt"):
            shutil.copy(os.path.join(results, name), out_dir)
    print(f"rendered {count} screens into {out_dir}")
    return 0 if count else 1


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    cmd, rest = argv[0], argv[1:]
    if cmd == "files":
        return cmd_files()
    if cmd == "test":
        return cmd_test(rest)
    if cmd == "run":
        return cmd_run(rest)
    if cmd == "screens":
        return cmd_screens(rest)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
