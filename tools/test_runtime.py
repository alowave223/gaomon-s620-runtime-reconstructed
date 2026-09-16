#!/usr/bin/env python3
"""Offline structural and isolated semantic checks for the reconstructed runtime."""
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

try:
    from unicorn import Uc, UC_ARCH_ARM, UC_MODE_THUMB
    from unicorn.arm_const import UC_ARM_REG_LR, UC_ARM_REG_PC, UC_ARM_REG_R0, UC_ARM_REG_R3
except ModuleNotFoundError as error:
    raise SystemExit("Unicorn is required; install requirements.txt") from error

ROOT = Path(__file__).resolve().parents[1]
BASE = 0x0800CC00
RAM = 0x20000000
STOCK_STUB = 0x08006000
RETURN = 0x08007000
HOOK_SETTLE = 0x0800CCC2
STOCK_WAIT = 0x08006B2E


def run_settle(binary: bytes, target_hz: int, stock_delay: int) -> int:
    emulator = Uc(UC_ARCH_ARM, UC_MODE_THUMB)
    emulator.mem_map(BASE & ~0xFFF, 0x2000)
    emulator.mem_write(BASE, binary)
    emulator.mem_map(RAM, 0x1000)
    emulator.mem_write(0x20000C24, target_hz.to_bytes(2, "little"))
    emulator.mem_map(STOCK_STUB, 0x2000)
    # BX LR at stock_wait_us: isolates the recovered arithmetic without modelling hardware timing.
    emulator.mem_write(STOCK_WAIT, b"\x70\x47")
    emulator.reg_write(UC_ARM_REG_R0, stock_delay)
    emulator.reg_write(UC_ARM_REG_R3, 0)
    emulator.reg_write(UC_ARM_REG_LR, RETURN | 1)
    emulator.emu_start(HOOK_SETTLE | 1, RETURN)
    assert emulator.reg_read(UC_ARM_REG_PC) == RETURN
    return emulator.reg_read(UC_ARM_REG_R0)


def main() -> None:
    subprocess.run([sys.executable, str(ROOT / "tools/build_runtime.py")], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    subprocess.run([sys.executable, str(ROOT / "tools/disassemble.py")], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    manifest = json.loads((ROOT / "reference/runtime.json").read_text())
    reference = bytes.fromhex(manifest["blob"])
    reconstructed = (ROOT / "build/runtime-reconstructed.bin").read_bytes()
    assert reference == reconstructed
    assert hashlib.sha256(reconstructed).hexdigest() == manifest["blobSha256"]
    hooks = json.loads((ROOT / "build/hooks.resolved.json").read_text())
    expected_targets = {
        "0x800b644": "0x0800cc04",
        "0x800b6a4": "0x0800cc32",
        "0x800b7b4": "0x0800cc64",
        "0x800c579": None,
        "0x8007782": "0x0800cc92",
        "0x8007792": "0x0800cc92",
        "0x80077a4": "0x0800cc92",
        "0x80077b4": "0x0800cc92",
        "0x800762a": "0x0800ccaa",
        "0x800763a": "0x0800ccaa",
        "0x8004d3e": "0x0800ccc2",
        "0x8004d4c": "0x0800ccc2",
        "0x8004d5a": "0x0800ccc2",
        "0x8004d9c": "0x0800ccc2",
        "0x8007e58": "0x0800cd26",
        "0x8007ed8": "0x0800cd26",
    }
    assert {hook["address"]: hook["target"] for hook in hooks} == expected_targets
    descriptor = next(hook for hook in hooks if hook["address"] == "0x800c579")
    assert descriptor["kind"] == "hid-report-descriptor-data"
    assert descriptor["before"] == "9507" and descriptor["after"] == "9520"

    # These vectors run the original reference and reconstructed code with the
    # stock delay routine replaced only by a BX LR return stub.
    vectors = [
        (0, [27, 20, 30, 150]),
        (294, [27, 20, 30, 150]),
        (530, [1, 0, 1, 4]),
        (531, [1, 0, 1, 4]),
    ]
    for target, expected in vectors:
        actual_reference = [run_settle(reference, target, delay) for delay in [27, 20, 30, 150]]
        actual_reconstructed = [run_settle(reconstructed, target, delay) for delay in [27, 20, 30, 150]]
        assert actual_reference == actual_reconstructed == expected, (target, actual_reference, actual_reconstructed)

    print("runtime structural checks and isolated settle-hook vectors passed")


if __name__ == "__main__":
    main()
