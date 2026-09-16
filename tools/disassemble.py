#!/usr/bin/env python3
"""Regenerate the annotated S620 runtime disassembly and hook-resolution map."""
from __future__ import annotations

import argparse
import hashlib
import json
from collections import deque
from pathlib import Path

try:
    from capstone import CS_ARCH_ARM, CS_GRP_CALL, CS_GRP_JUMP, CS_MODE_LITTLE_ENDIAN, CS_MODE_THUMB, Cs
    from capstone.arm import ARM_OP_IMM
except ModuleNotFoundError as error:
    raise SystemExit("Capstone is required; install requirements.txt") from error

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "reference/runtime.json"
SYMBOLS = ROOT / "firmware/symbols.json"
REFERENCE = ROOT / "build/runtime-reference.bin"
DEFAULT_DISASSEMBLY = ROOT / "build/runtime.disasm.txt"
DEFAULT_HOOKS = ROOT / "build/hooks.resolved.json"

def parse_address(value: str | int) -> int:
    return int(value, 0) if isinstance(value, str) else value


def load_reference() -> tuple[dict, bytes]:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    blob = bytes.fromhex(manifest["blob"])
    actual = hashlib.sha256(blob).hexdigest()
    if actual != manifest["blobSha256"]:
        raise ValueError(f"manifest blob SHA-256 is {actual}, expected {manifest['blobSha256']}")
    REFERENCE.parent.mkdir(parents=True, exist_ok=True)
    REFERENCE.write_bytes(blob)
    return manifest, blob


def decode_at(disassembler: Cs, address: int, blob: bytes, base: int):
    offset = address - base
    return list(disassembler.disasm(blob[offset:], address, count=1))[0]


def is_unconditional_branch(instruction) -> bool:
    return instruction.mnemonic in {"b", "b.w"}


def is_return(instruction) -> bool:
    return instruction.mnemonic == "bx" and instruction.op_str == "lr" or instruction.mnemonic == "pop" and "pc" in instruction.op_str


def reachable_from_entries(instruction_map: dict[int, object], entries: list[int]) -> set[int]:
    reachable: set[int] = set()
    pending = deque(entries)
    while pending:
        address = pending.popleft()
        if address in reachable or address not in instruction_map:
            continue
        instruction = instruction_map[address]
        reachable.add(address)
        next_address = address + instruction.size
        target = next((operand.imm for operand in instruction.operands if operand.type == ARM_OP_IMM), None)
        if instruction.group(CS_GRP_CALL):
            if target in instruction_map:
                pending.append(target)
            pending.append(next_address)
        elif instruction.group(CS_GRP_JUMP):
            if target in instruction_map:
                pending.append(target)
            if not is_unconditional_branch(instruction) and not is_return(instruction):
                pending.append(next_address)
        elif not is_return(instruction):
            pending.append(next_address)
    return reachable


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--disassembly", type=Path, default=DEFAULT_DISASSEMBLY)
    parser.add_argument("--hooks", type=Path, default=DEFAULT_HOOKS)
    arguments = parser.parse_args()
    manifest, blob = load_reference()
    base = manifest["base"]
    symbols = json.loads(SYMBOLS.read_text(encoding="utf-8"))
    functions = sorted(symbols["functions"], key=lambda function: parse_address(function["address"]))
    runtime_names = {parse_address(function["address"]): function["name"] for function in functions}
    stock_names = {parse_address(symbol["address"]): symbol["name"] for symbol in symbols["stockSymbols"]}
    disassembler = Cs(CS_ARCH_ARM, CS_MODE_THUMB | CS_MODE_LITTLE_ENDIAN)
    disassembler.detail = True

    instruction_map: dict[int, object] = {}
    for function in functions:
        address = parse_address(function["address"])
        size = function["size"]
        code = blob[address - base:address - base + size]
        for instruction in disassembler.disasm(code, address):
            instruction_map[instruction.address] = instruction
    entries = [parse_address(function["address"]) for function in functions if function["callers"] and function["callers"][0].startswith("hook:")]
    reachable = reachable_from_entries(instruction_map, entries)
    if set(instruction_map) != reachable:
        missing = sorted(set(instruction_map) - reachable)
        raise ValueError("unreachable non-marker instructions: " + ", ".join(hex(address) for address in missing))

    hook_rows = []
    for address_text, patched_hex in manifest["hooks"].items():
        address = int(address_text, 16)
        before = bytes.fromhex(manifest["hookPreimages"][address_text])
        after = bytes.fromhex(patched_hex)
        is_feature_length = address == manifest.get("featureReportLengthAddress")
        before_lines = [f"{item.mnemonic} {item.op_str}".strip() for item in disassembler.disasm(before, address)]
        after_items = list(disassembler.disasm(after, address))
        after_lines = [f"{item.mnemonic} {item.op_str}".strip() for item in after_items]
        target = None
        for item in after_items:
            if item.group(CS_GRP_CALL) or item.group(CS_GRP_JUMP):
                target = next((operand.imm for operand in item.operands if operand.type == ARM_OP_IMM), None)
                if target is not None:
                    break
        hook_rows.append({
            "address": address_text,
            "kind": "hid-report-descriptor-data" if is_feature_length else "instruction-patch",
            "before": before.hex(),
            "beforeDisassembly": ["HID item 0x95 (Report Count), value 7"] if is_feature_length else before_lines,
            "after": after.hex(),
            "afterDisassembly": ["HID item 0x95 (Report Count), value 32"] if is_feature_length else after_lines,
            "target": f"0x{target:08x}" if target is not None else None,
            "targetSymbol": runtime_names.get(target) or stock_names.get(target),
        })

    lines = [
        "; Generated by tools/disassemble.py. Do not hand-edit.\n",
        f"; base=0x{base:08x} bytes={len(blob)} sha256={hashlib.sha256(blob).hexdigest()}\n\n",
    ]
    marker_by_address = {parse_address(marker["address"]): marker for marker in symbols["unreachableMarkers"]}
    for function in functions:
        address = parse_address(function["address"])
        lines.append(f"{function['name']} @ 0x{address:08x}, {function['size']} bytes\n")
        for instruction_address in range(address, address + function["size"]):
            instruction = instruction_map.get(instruction_address)
            if instruction is None:
                continue
            target = next((operand.imm for operand in instruction.operands if operand.type == ARM_OP_IMM), None)
            target_name = runtime_names.get(target) or stock_names.get(target)
            suffix = f" ; -> {target_name}" if target_name else ""
            lines.append(
                f"  {instruction.address:08x}: {instruction.bytes.hex():<10} {instruction.mnemonic:<8} {instruction.op_str}{suffix}\n"
            )
        lines.append("\n")
    lines.append("Known unreachable marker words (excluded from CFG):\n")
    for address, marker in marker_by_address.items():
        lines.append(f"  {address:08x}: {marker['bytes']} ; marker {marker['value']}\n")
    arguments.disassembly.parent.mkdir(parents=True, exist_ok=True)
    arguments.disassembly.write_text("".join(lines), encoding="utf-8")
    arguments.hooks.parent.mkdir(parents=True, exist_ok=True)
    arguments.hooks.write_text(json.dumps(hook_rows, indent=2) + "\n", encoding="utf-8")
    print(f"{arguments.disassembly}\n{arguments.hooks}\nfunctions={len(functions)} reachableInstructions={len(reachable)}")


if __name__ == "__main__":
    main()
