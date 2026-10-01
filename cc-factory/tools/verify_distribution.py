#!/usr/bin/env python3
"""Verify generated modules, turtle package, and both installers in isolated CraftOS."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
CRAFTOS = os.environ.get("CRAFTOS_BIN", "/Applications/CraftOS-PC.app/Contents/MacOS/craftos")


def main():
    bundle = (ROOT / "dist/factory.lua").read_text()
    modules = dict(re.findall(r'bundled_modules\["([^"]+)"\] = \[===\[\n(.*?)\n\]===\]', bundle, re.S))
    expected = {p.stem: p.read_text() for p in ROOT.glob("*.lua")
                if p.name in ("factory.lua", "turtle_os.lua") or p.name.startswith(("lib_", "state_"))}
    assert modules == expected, "Bundled modules differ from current source"
    manifest = json.loads((REPO / "arcadeos/files.json").read_text())
    files = manifest["packages"]["turtle"]["files"]
    by_source = {entry["src"]: entry for entry in files}
    for name in expected:
        source = "cc-factory/" + name + ".lua"
        assert source in by_source, "Missing turtle module: " + source
        assert by_source[source]["size"] == (REPO / source).stat().st_size, "Stale size: " + source
    assert not any("/tests/" in f["src"] or "/tools/" in f["src"] for f in files)
    with tempfile.TemporaryDirectory(prefix="mining-distribution-") as tmp:
        base = Path(tmp)
        results = base / "results"
        results.mkdir()
        code = r'''
local ok,err=pcall(function()
  assert(shell.run("/src/cc-factory/dist/factory.lua"), "Standalone installer failed")
  for _,name in ipairs(fs.list("/src/cc-factory")) do
    if name=="factory.lua" or name=="turtle_os.lua" or name:match("^lib_.*%.lua$") or name:match("^state_.*%.lua$") then
      local a=assert(fs.open("/src/cc-factory/"..name,"r")); local expected=a.readAll();a.close()
      local b=assert(fs.open("/"..name,"r")); local installed=b.readAll();b.close()
      -- bundle.js adds one newline before the long-string closing delimiter.
      assert(installed==expected.."\n","Standalone content mismatch: "..name)
      assert(load(installed,"@"..name),"Invalid Lua: "..name)
    end
  end
  _G.turtle={} -- Select turtle package only; no world API is supplied.
  assert(shell.run("/src/arcadeos/install.lua","--local","/src","--yes"),"ArcadeOS installer failed")
  for _,name in ipairs({"factory","lib_safe_miner","lib_mine_policy","lib_mining_checkpoint","lib_mining_status"}) do
    local a=assert(fs.open("/src/cc-factory/"..name..".lua","r"));local expected=a.readAll();a.close()
    local b=assert(fs.open("/pkg/factory/"..name..".lua","r"));local installed=b.readAll();b.close()
    assert(installed==expected,"ArcadeOS content mismatch: "..name)
  end
  assert(not fs.exists("/pkg/factory/tests"),"Test helpers installed")
  assert(not fs.exists("/pkg/factory/tools"),"Developer tools installed")
end)
local f=assert(fs.open("/results/result.txt","w"));f.write(ok and "PASS both installers and source readback" or "FAIL "..tostring(err));f.close();os.shutdown()
'''
        proc = subprocess.run([CRAFTOS, "--headless", "--directory", str(base / "emulator"),
                               "--mount-ro", f"/src={REPO}", "--mount-rw", f"/results={results}",
                               "--exec", code], capture_output=True, timeout=60)
        result = results / "result.txt"
        assert proc.returncode == 0 and result.exists(), "Installer emulator failed"
        report = result.read_text()
        print(f"PASS {len(expected)} bundled modules match source and turtle manifest")
        print(report)
        assert report.startswith("PASS"), report


if __name__ == "__main__":
    main()
