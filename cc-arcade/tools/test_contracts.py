#!/usr/bin/env python3
"""Run the isolated PineArcade contract harness with a real, local Lua VM.

Requires Python 3 and Lua 5.3/5.4 (or LuaTeX, which embeds Lua 5.3).
No packages, Minecraft instance, peripherals, network, or credentials are needed.
"""

from __future__ import annotations

import argparse
import math
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--lua",
        default=os.environ.get("PINE_LUA"),
        help="Lua executable or command (also configurable with PINE_LUA)",
    )
    parser.add_argument(
        "--suite",
        default="tests/rednet_contracts.lua",
        help="Lua test entry point, relative to cc-arcade (default: %(default)s)",
    )
    parser.add_argument(
        "--timeout", type=float, default=60,
        help="maximum test runtime in seconds (default: %(default)s)",
    )
    options = parser.parse_args()
    if not math.isfinite(options.timeout) or options.timeout <= 0:
        parser.error("--timeout must be finite and positive")

    command = shlex.split(options.lua) if options.lua else []
    if not command:
        for candidate in ("lua5.4", "lua54", "lua5.3", "lua53", "lua", "luatex"):
            executable = shutil.which(candidate)
            if executable:
                command = [executable]
                break
    if not command:
        print(
            "No Lua interpreter found. Install Lua 5.3/5.4 (for example: "
            "sudo apt-get install lua5.4), or select it with --lua/PINE_LUA. "
            "An existing LuaTeX installation is also supported.",
            file=sys.stderr,
        )
        return 2

    # Unlike standalone Lua, LuaTeX requires --luaonly before the script path.
    if Path(command[0]).stem == "luatex" and "--luaonly" not in command:
        command.append("--luaonly")
    suite = Path(options.suite)
    if not suite.is_absolute():
        suite = ROOT / suite
    if not suite.is_file():
        print(f"Missing Lua test suite: {suite}", file=sys.stderr)
        return 2

    print("PineArcade contracts: " + shlex.join(command + [str(suite)]), flush=True)
    environment = dict(os.environ)
    # Keep source-module resolution independent of the invoking directory.
    environment["LUA_PATH"] = "./?.lua;./?/init.lua;;"
    environment["LUA_PATH_5_3"] = environment["LUA_PATH"]
    environment["LUA_PATH_5_4"] = environment["LUA_PATH"]
    try:
        result = subprocess.run(
            command + [str(suite)], cwd=ROOT, env=environment,
            timeout=options.timeout, check=False,
        )
    except FileNotFoundError:
        print(f"Lua executable not found: {command[0]}", file=sys.stderr)
        return 2
    except OSError as error:
        print(f"Could not start Lua: {error}", file=sys.stderr)
        return 2
    except subprocess.TimeoutExpired:
        print(f"FAIL: suite exceeded {options.timeout:g}s", file=sys.stderr)
        return 1
    # Signal deaths also count as failures; avoid platform-dependent negative exits.
    return result.returncode if result.returncode >= 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
