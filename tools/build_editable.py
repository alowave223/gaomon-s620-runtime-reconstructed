#!/usr/bin/env python3
"""Build the editable C runtime and enforce its fixed flash budget."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

try:
    from elftools.elf.elffile import ELFFile
except ModuleNotFoundError as error:
    raise SystemExit("pyelftools is required; install requirements.txt") from error

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "firmware/editable"
BUILD = ROOT / "build/editable"
BASE = 0x0800CC00
LIMIT = 0x558


def zig_command() -> list[str]:
    explicit = os.environ.get("ZIG")
    if explicit:
        return [explicit]
    system = shutil.which("zig")
    if system:
        return [system]
    try:
        import ziglang  # noqa: F401
    except ModuleNotFoundError as error:
        raise SystemExit(
            "Zig is required for the editable build. Install Zig or run "
            "`python -m pip install ziglang`."
        ) from error
    return [sys.executable, "-m", "ziglang"]


def run(*arguments: str) -> None:
    subprocess.run([*zig_command(), *arguments], cwd=ROOT, check=True)


def main() -> None:
    BUILD.mkdir(parents=True, exist_ok=True)
    elf = BUILD / "runtime.elf"
    binary = BUILD / "runtime.bin"

    run(
        "cc", "-target", "thumb-freestanding-eabi", "-mcpu=cortex_m3",
        "-Oz", "-g", "-std=c11", "-ffreestanding", "-fno-builtin",
        "-fno-unwind-tables", "-fno-asynchronous-unwind-tables",
        "-fdata-sections", "-ffunction-sections", "-fomit-frame-pointer",
        "-nostdlib", "-Wl,--gc-sections", "-Wl,-e,runtime_feature_command_handler",
        f"-Wl,-T,{SOURCE / 'linker.ld'}", "-o", str(elf),
        str(SOURCE / "hooks.S"), str(SOURCE / "runtime.c"),
    )
    run("objcopy", "-O", "binary", str(elf), str(binary))

    size = binary.stat().st_size
    if size > LIMIT:
        raise SystemExit(f"editable runtime is {size} bytes; limit is {LIMIT}")
    with elf.open("rb") as stream:
        symbol_table = ELFFile(stream).get_section_by_name(".symtab")
        if symbol_table is None:
            raise SystemExit("editable ELF has no symbol table")
        symbols = {
            symbol.name: symbol.entry.st_value & ~1
            for symbol in symbol_table.iter_symbols()
            if symbol.name.startswith("runtime_") and symbol.entry.st_value
        }
    required_hooks = [
        "runtime_hook_get_feature", "runtime_hook_set_feature",
        "runtime_hook_dispatch_feature", "runtime_hook_ema_weight",
        "runtime_hook_average_window", "runtime_hook_settle_delay",
        "runtime_hook_barrel_rescan",
    ]
    missing = [name for name in required_hooks if name not in symbols]
    if missing:
        raise SystemExit(f"missing editable hook symbols: {', '.join(missing)}")

    metadata = {
        "base": BASE,
        "bytes": size,
        "limit": LIMIT,
        "free": LIMIT - size,
        "end": BASE + size,
        "symbols": {name: f"0x{address:08x}" for name, address in sorted(symbols.items())},
    }
    (BUILD / "runtime.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
