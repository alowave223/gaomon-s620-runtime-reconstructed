# GAOMON S620 runtime reconstruction

Byte-exact, annotated ARM Thumb-2 reconstruction of the 1,368-byte runtime
extension embedded in [`catears124/tablet.ears.cat`](https://github.com/catears124/tablet.ears.cat).

This is **not the original C source**. The executable logic is kept as assembly
because that is the honest representation recoverable from the binary. The
build reproduces the reference blob byte for byte:

```text
base:   0x0800CC00
size:   1368 bytes
sha256: 71c2db51c4421f0e54b47c6b939c7a8764e840df465247eb9e749c3db4751560
```

## Contents

- `firmware/runtime.S` — complete annotated reconstruction
- `firmware/*.h` — recovered protocol/config/stock ABI layouts
- `firmware/symbols.json` — function and address map
- `reference/runtime.json` — upstream reference blob, hooks and preimages
- `docs/analysis.md` — hook map, behaviour and remaining uncertainties
- `tools/` — deterministic build, disassembly and verification

## Build and verify

Python 3.10+ is sufficient. Use a virtual environment if desired:

```bash
python -m pip install -r requirements.txt
python tools/build_runtime.py
python tools/test_runtime.py
```

The test fails if the assembled binary differs from the reference, if a hook
resolves to the wrong target, or if the isolated settle-delay vectors differ.
Generated files go to `build/`.

To regenerate the annotated disassembly separately:

```bash
python tools/disassemble.py
```

## Scope

The repository documents and rebuilds only the injected S620 runtime. It does
not contain the web flasher, a complete tablet firmware image, or flashing
instructions. No hardware is accessed by the tools.

Read [`docs/analysis.md`](docs/analysis.md) before changing the assembly. In
particular, recovered names are descriptive, the exact MCU/compiler are still
unknown, and several stock-firmware types remain opaque.

## License

MIT. The reference runtime and surrounding project were published by
`catears124` under the same license; the original copyright notice is retained.
