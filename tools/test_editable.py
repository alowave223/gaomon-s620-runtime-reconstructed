#!/usr/bin/env python3
"""Compare editable C behaviour with the byte-exact runtime in Unicorn."""
from __future__ import annotations

import binascii
import json
import subprocess
import sys
from pathlib import Path

from unicorn import Uc, UC_ARCH_ARM, UC_HOOK_MEM_INVALID, UC_MODE_THUMB
from unicorn.arm_const import UC_ARM_REG_LR, UC_ARM_REG_PC, UC_ARM_REG_R0, UC_ARM_REG_SP

ROOT = Path(__file__).resolve().parents[1]
FLASH_BASE = 0x08000000
RUNTIME_BASE = 0x0800CC00
RAM_BASE = 0x20000000
RUNTIME_RAM = 0x20000C00
RETURN = 0x0801F000
REFERENCE_HANDLER = 0x0800CD3C


def crc32(data: bytes) -> int:
    return binascii.crc32(data) & 0xFFFFFFFF


def frame(command: int, payload: bytes = b"", sequence: int = 0x5A) -> bytes:
    if len(payload) > 24:
        raise ValueError("payload exceeds 24 bytes")
    result = bytearray(33)
    result[0] = 0x16
    result[1] = command
    result[2] = sequence
    result[3] = len(payload)
    result[5:5 + len(payload)] = payload
    result[29:33] = crc32(result[1:29]).to_bytes(4, "little")
    return bytes(result)


def valid_config(target: int = 503, ema: int = 255, window: int = 1, fast: int = 1) -> bytes:
    config = bytearray(24)
    config[0:4] = b"CTC1"
    config[4:6] = (1).to_bytes(2, "little")
    config[6:8] = target.to_bytes(2, "little")
    config[8] = ema
    config[9] = window
    config[10] = fast
    config[20:24] = crc32(config[:20]).to_bytes(4, "little")
    return bytes(config)


def emulator(binary: bytes) -> Uc:
    machine = Uc(UC_ARCH_ARM, UC_MODE_THUMB)
    machine.mem_map(FLASH_BASE, 0x20000)
    machine.mem_write(FLASH_BASE, b"\xff" * 0x20000)
    machine.mem_write(RUNTIME_BASE, binary)
    machine.mem_map(RAM_BASE, 0x2000)
    machine.mem_write(RAM_BASE, b"\x00" * 0x2000)
    machine.mem_map(0x40020000, 0x1000)
    machine.reg_write(UC_ARM_REG_SP, RAM_BASE + 0x1FF0)
    def invalid_memory(_machine, access, address, size, value, _user_data):
        print(
            f"invalid memory access={access} address=0x{address:08x} size={size} value={value}",
            file=sys.stderr,
        )
        return False
    machine.hook_add(UC_HOOK_MEM_INVALID, invalid_memory)
    machine.reg_write(UC_ARM_REG_LR, RETURN | 1)
    return machine


def call(machine: Uc, address: int) -> None:
    machine.reg_write(UC_ARM_REG_LR, RETURN | 1)
    machine.emu_start(address | 1, RETURN)
    assert machine.reg_read(UC_ARM_REG_PC) == RETURN


def run_command(binary: bytes, handler: int, request: bytes) -> bytes:
    machine = emulator(binary)
    machine.mem_write(RUNTIME_RAM, request)
    call(machine, handler)
    return bytes(machine.mem_read(RUNTIME_RAM, 0x30))


def run_settle(binary: bytes, function: int, target: int, delay: int) -> int:
    machine = emulator(binary)
    machine.mem_write(RUNTIME_RAM + 0x24, target.to_bytes(2, "little"))
    machine.reg_write(UC_ARM_REG_R0, delay)
    call(machine, function)
    return machine.reg_read(UC_ARM_REG_R0)


def main() -> None:
    subprocess.run([sys.executable, str(ROOT / "tools/build_runtime.py")], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    subprocess.run([sys.executable, str(ROOT / "tools/build_editable.py")], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)

    manifest = json.loads((ROOT / "reference/runtime.json").read_text())
    reference = bytes.fromhex(manifest["blob"])
    editable = (ROOT / "build/editable/runtime.bin").read_bytes()
    metadata = json.loads((ROOT / "build/editable/runtime.json").read_text())
    editable_handler = int(metadata["symbols"]["runtime_feature_command_handler"], 16)
    editable_settle = int(metadata["symbols"]["runtime_scale_settle_delay"], 16)

    for target in (0, 1, 293, 294, 400, 503, 530, 531, 65535):
        for delay in (20, 27, 30, 150):
            expected = delay if target == 0 else (
                0 if min(max(target, 294), 530) == 530 and delay == 20 else
                ((((530 - min(max(target, 294), 530)) * 221) // 236 + 6) * delay + 113) // 227
            )
            actual = run_settle(editable, editable_settle, target, delay)
            assert actual == expected, (target, delay, expected, actual)

    requests = [
        frame(1),
        frame(2),
        frame(3, valid_config()),
        frame(5),
        frame(6),
    ]
    for request in requests:
        exact_state = run_command(reference, REFERENCE_HANDLER, request)
        editable_state = run_command(editable, editable_handler, request)
        assert editable_state == exact_state, (
            request[1], exact_state.hex(), editable_state.hex()
        )

    print("editable C runtime matches reference command and settle vectors")


if __name__ == "__main__":
    main()
