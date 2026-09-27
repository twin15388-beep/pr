#!/usr/bin/env python3
"""
[project rain oss] single-file builder.

Flattens the src/ module tree + assets/ into one Lua file whose runtime provides:
  * require("@src/...")             -> module resolution with per-module caching
  * list_modules("glob/*")          -> module enumeration (one-level `*` wildcard)
  * inline_asset_b96("@assets/...") -> base64(zstd(asset_bytes))

The emitted script mirrors how the upstream (closed) loader shipped: one chunk,
modules compiled lazily through loadstring.

usage:
  python3 tools/build.py [--out dist/project-rain.lua]

deps:
  pip install zstandard
"""

from __future__ import annotations

import argparse
import base64
import re
import sys
import time
from pathlib import Path

import zstandard as zstd

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
ASSETS = ROOT / "assets"
DEFAULT_OUT = ROOT / "project-rain.lua"

RUNTIME = """-- ============================================================================
-- [project rain oss] single-file build
-- generated __TIME__ by tools/build.py (__NMODULES__ modules, __NASSETS__ assets)
-- based on github.com/project-rain-oss - keep credits intact if you fork/strip
-- ============================================================================

getgenv().PR_BUILD = getgenv().PR_BUILD or {};
local BUILD = getgenv().PR_BUILD;

BUILD.modules = BUILD.modules or {};
BUILD.assets = BUILD.assets or {};
BUILD.loaded = BUILD.loaded or {};
BUILD.id = "__BUILD_ID__";

local modules = BUILD.modules;
local assets = BUILD.assets;
local loaded = BUILD.loaded;

local unpack_ = table.unpack or unpack;

local function builder_require(path)
	assert(type(path) == "string", "require: string expected, got " .. type(path));

	local packed = loaded[path];
	if packed then
		return unpack_(packed, 1, packed.n);
	end;

	local source = modules[path];
	if not source then
		error(("[pr] module not found: %s"):format(tostring(path)), 2);
	end;

	local fn, compile_err = loadstring(source, "=" .. path);
	if not fn then
		error(("[pr] failed to compile %s: %s"):format(tostring(path), tostring(compile_err)), 2);
	end;

	packed = table.pack(fn());
	loaded[path] = packed;

	return unpack_(packed, 1, packed.n);
end;

-- route global require("...") through the module registry; everything else
-- (ModuleScripts etc.) falls through to the original require
local old_require = require;
getgenv().require = function(path, ...)
	if type(path) == "string" then
		if modules[path] then
			return builder_require(path);
		elseif path:sub(1, 5) == "@src/" then
			error(("[pr] module not found: %s"):format(path), 2);
		end;
	end;

	return old_require(path, ...);
end;

getgenv().builder_require = builder_require;

-- list_modules("ui/tabs/*") -> sorted array of "@src/..." keys, `*` matches one level
local function list_modules(pattern)
	assert(type(pattern) == "string", "list_modules: string expected");

	local body = pattern;
	if body:sub(1, 5) ~= "@src/" then
		body = "@src/" .. body;
	end;

	local results = {};

	if not body:find("*", 1, true) then
		if modules[body] then
			results[1] = body;
		end;
		return results;
	end;

	local matcher = "^" .. body:gsub("([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1"):gsub("%*", "[^/]*") .. "$";

	for key in pairs(modules) do
		if key:match(matcher) then
			results[#results + 1] = key;
		end;
	end;

	table.sort(results);
	return results;
end;
getgenv().list_modules = list_modules;

-- returns the base64(zstd(bytes)) blob init.lua's decode_asset() expects
getgenv().inline_asset_b96 = function(path)
	local blob = assets[path];
	assert(blob, "[pr] asset not embedded: " .. tostring(path));
	return blob;
end;

"""

BOOTSTRAP = """
-- ============================================================================
-- bootstrap: globals first (mirrors upstream preload), then the entrypoint
-- ============================================================================

do -- src/globals.lua
	builder_require("@src/globals");
end;

do -- src/init.lua (entrypoint)
	builder_require("@src/init");
end;
"""

REQUIRE_RE = re.compile(r'''require\(\s*(?:\(\s*)?(?:LPH_ENCSTR\(\s*)?"(@(?:src|assets)/[^"]+)"''')
ASSET_INLINE_RE = re.compile(r'''inline_asset_b96\(\s*"(@assets/[^"]+)"''')


def collect_modules() -> dict[str, Path]:
    modules: dict[str, Path] = {}
    for path in sorted(SRC.rglob("*.lua")):
        rel = path.relative_to(SRC).with_suffix("").as_posix()
        key = f"@src/{rel}"
        if key in modules:
            raise SystemExit(f"duplicate module key {key}")
        modules[key] = path
    return modules


def collect_assets() -> dict[str, Path]:
    assets: dict[str, Path] = {}
    for path in sorted(ASSETS.rglob("*")):
        if path.is_file():
            rel = path.relative_to(ASSETS).as_posix()
            assets[f"@assets/{rel}"] = path
    return assets


def long_string(data: bytes) -> str:
    """wrap bytes in a collision-free lua long bracket string.

    the payload is newline-wrapped: lua strips the first newline after the
    opening bracket, and the trailing newline guarantees a source ending in
    `]` can never fuse with the closing bracket into a premature `]]`.
    """
    payload = b"\n" + data + b"\n"
    level = 0
    while True:
        closer = b"]" + b"=" * level + b"]"
        if closer not in payload:
            break
        level += 1
    eq = b"=" * level
    return (b"[" + eq + b"[" + payload + b"]" + eq + b"]").decode("latin1")


def lua_name(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def compress_asset(raw: bytes) -> str:
    cctx = zstd.ZstdCompressor(level=12, write_content_size=True, write_checksum=False, write_dict_id=False)
    return base64.b64encode(cctx.compress(raw)).decode("ascii")


def verify_coverage(modules: dict[str, Path], assets: dict[str, Path]) -> list[str]:
    """static sanity: every literal @src/@assets reference must resolve"""
    problems: list[str] = []
    for key, path in modules.items():
        text = path.read_text(encoding="utf-8", errors="replace")
        for m in REQUIRE_RE.finditer(text):
            ref = m.group(1)
            if ref.startswith("@src/") and ref not in modules:
                problems.append(f"{key}: unresolved require {ref}")
        for m in ASSET_INLINE_RE.finditer(text):
            ref = m.group(1)
            if ref not in assets:
                problems.append(f"{key}: unresolved asset {ref}")
    return problems


def build(out_path: Path) -> None:
    modules = collect_modules()
    assets = collect_assets()

    problems = verify_coverage(modules, assets)
    if problems:
        print("!! unresolved references:")
        for p in problems:
            print("   ", p)
    else:
        print("static check: all @src/@assets references resolve")

    build_id = time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime())
    chunks: list[str] = []

    chunks.append(
        RUNTIME.replace("__TIME__", build_id)
        .replace("__NMODULES__", str(len(modules)))
        .replace("__NASSETS__", str(len(assets)))
        .replace("__BUILD_ID__", build_id)
    )

    chunks.append("-- module registry ---------------------------------------------------------\n")
    for key, path in modules.items():
        source = path.read_bytes()
        chunks.append(f'modules["{lua_name(key)}"] = {long_string(source)};\n')

    chunks.append("\n-- embedded assets (base64(zstd)) ------------------------------------------\n")
    total_raw = 0
    for key, path in assets.items():
        raw = path.read_bytes()
        total_raw += len(raw)
        chunks.append(f'assets["{lua_name(key)}"] = "{compress_asset(raw)}";\n')

    chunks.append(BOOTSTRAP)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("".join(chunks), encoding="latin1")

    # the build IS luau source - ship a .luau twin for tooling that wants it
    luau_path = out_path.with_suffix(".luau")
    luau_path.write_text("".join(chunks), encoding="latin1")

    print(f"modules : {len(modules)}")
    print(f"assets  : {len(assets)} ({total_raw / 1024:.0f} KiB raw)")
    print(f"output  : {out_path} ({out_path.stat().st_size / 1024 / 1024:.2f} MiB)")
    print(f"output  : {luau_path} ({luau_path.stat().st_size / 1024 / 1024:.2f} MiB)")


def main() -> None:
    parser = argparse.ArgumentParser(description="project rain oss single-file builder")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="output lua file")
    args = parser.parse_args()
    build(args.out)


if __name__ == "__main__":
    main()
