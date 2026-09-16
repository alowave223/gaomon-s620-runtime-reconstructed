#!/usr/bin/env python3
"""Assemble the byte-exact S620 runtime reconstruction into a raw binary.

This intentionally assembles source, not the JSON reference blob.  The
reference is extracted separately and compared by verify-runtime.mjs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

try:
    from keystone import KS_ARCH_ARM, KS_MODE_LITTLE_ENDIAN, KS_MODE_THUMB, Ks, KsError
except ModuleNotFoundError as error:
    raise SystemExit(
        "Keystone is required. Install requirements.txt "
        "(for example: python3 -m pip install -r requirements.txt)."
    ) from error

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "firmware/runtime.S"
DEFAULT_OUTPUT = ROOT / "build/runtime-reconstructed.bin"
DEFAULT_METADATA = ROOT / "build/runtime-reconstructed.json"


def without_comments(line: str) -> str:
    line = re.sub(r"/\*.*?\*/", "", line)
    return line.split("@", 1)[0].strip()


def integer(text: str) -> int:
    return int(text.strip(), 0)


def assemble(source: Path) -> tuple[int, bytes]:
    assembler = Ks(KS_ARCH_ARM, KS_MODE_THUMB | KS_MODE_LITTLE_ENDIAN)
    symbols: dict[str, int] = {}
    output = bytearray()
    address: int | None = None

    # Preserve line numbers while removing C-style address annotations.
    source_text = source.read_text(encoding="utf-8")
    source_text = re.sub(r"/\*[\s\S]*?\*/", lambda match: "\n" * match.group(0).count("\n"), source_text)
    for line_number, original in enumerate(source_text.splitlines(), start=1):
        line = without_comments(original)
        if not line:
            continue
        if line.endswith(":"):
            if address is None:
                raise ValueError(f"{source}:{line_number}: label before .org")
            symbols[line[:-1].strip()] = address
            continue
        if line.startswith(".syntax") or line == ".thumb" or line.startswith(".global"):
            continue
        if line.startswith(".org"):
            if address is not None:
                raise ValueError(f"{source}:{line_number}: only one .org is permitted")
            address = integer(line.removeprefix(".org").strip())
            continue
        if line.startswith(".equ"):
            match = re.fullmatch(r"\.equ\s+([A-Za-z_][A-Za-z0-9_]*),\s*(.+)", line)
            if not match:
                raise ValueError(f"{source}:{line_number}: malformed .equ")
            symbols[match.group(1)] = integer(match.group(2))
            continue
        if address is None:
            raise ValueError(f"{source}:{line_number}: instruction before .org")

        if line.startswith(".hword"):
            values = [integer(value) for value in line.removeprefix(".hword").split(",")]
            if any(value < 0 or value > 0xFFFF for value in values):
                raise ValueError(f"{source}:{line_number}: .hword is outside uint16")
            encoded = b"".join(value.to_bytes(2, "little") for value in values)
        elif line.startswith(".byte"):
            values = [integer(value) for value in line.removeprefix(".byte").split(",")]
            if any(value < 0 or value > 0xFF for value in values):
                raise ValueError(f"{source}:{line_number}: .byte is outside uint8")
            encoded = bytes(values)
        else:
            for name, value in symbols.items():
                line = re.sub(rf"\b{re.escape(name)}\b", hex(value), line)
            try:
                encoded = bytes(assembler.asm(line, address)[0])
            except KsError as error:
                raise ValueError(f"{source}:{line_number}: cannot assemble {line!r}: {error}") from error
            if not encoded:
                raise ValueError(f"{source}:{line_number}: assembler emitted no bytes for {line!r}")
        output.extend(encoded)
        address += len(encoded)

    if address is None:
        raise ValueError(f"{source}: no .org")
    base = address - len(output)
    return base, bytes(output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    arguments = parser.parse_args()

    base, binary = assemble(arguments.source)
    arguments.out.parent.mkdir(parents=True, exist_ok=True)
    arguments.out.write_bytes(binary)
    metadata = {
        "base": base,
        "bytes": len(binary),
        "sha256": hashlib.sha256(binary).hexdigest(),
        "source": str(arguments.source.relative_to(ROOT)),
    }
    arguments.metadata.parent.mkdir(parents=True, exist_ok=True)
    arguments.metadata.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
