# S620 runtime reverse engineering

This is a reconstruction of the injected runtime stored in
`reference/runtime.json`; it is not the original author’s source code.
Names in this document are descriptive. Statements labelled **proven** are
directly demonstrated by the reference bytes. **Strongly supported** means the
call site and the adjacent stock code establish it, but an opaque stock type
remains. **Inferred** is deliberately not treated as fact elsewhere.

## Reference and reproduction

| Property | Value |
| --- | --- |
| Reference source | `reference/runtime.json` `blob` |
| Load address | `0x0800CC00` |
| Length | 1,368 bytes (`0x558`) |
| Reference SHA-256 | `71c2db51c4421f0e54b47c6b939c7a8764e840df465247eb9e749c3db4751560` |
| Exact source | `firmware/runtime.S` |
| Generated reference binary | `build/runtime-reference.bin`, extracted from JSON by `tools/disassemble.py` |
| Generated reconstructed binary | `build/runtime-reconstructed.bin`, assembled only from `runtime.S` |

`runtime.S` is the executable reconstruction. It has a source address beside
every instruction and named stock ABI boundaries. It is assembly rather than
invented decompiled C: the original C compiler and source conventions cannot
be established from this blob, while the exact control flow and unsigned
integer behaviour can be represented honestly in Thumb assembly.

The source has 1,340 bytes of reachable assembly and 28 bytes of seven
unreachable `MOVW r12,#0xA10n` marker words. Thus 1,368/1,368 bytes are
reconstructed as assembly/data and 0 bytes of executable logic are claimed as
compiler-recovered C. `protocol.h`, `config.h` and `runtime.h` provide audited
packed C ABI layouts with compile-time assertions; they are not substituted for
the exact assembly in the binary build.

## Architecture and ABI

| Finding | Evidence | Confidence |
| --- | --- | --- |
| Instruction set | 16- and 32-bit Thumb instructions, including `MOVW`, `MOVT`, `B.W`, `BL`, `TBB`, and `UDIV` | Proven |
| Minimum compatible target | ARMv7-M-or-later compatible Thumb-2 profile with hardware unsigned divide; a Cortex-M3/M4-class target is sufficient | Proven for ISA requirements |
| Exact MCU/core | The blob does not identify it. DFU branding says GD32, but does not prove a part number. | Unknown |
| Endianness | `0x31435443` is stored as bytes `43 54 43 31` (`CTC1`), and all protocol fields use byte/halfword/word little-endian layout | Proven |
| Alignment | Thumb entry points and all decoded instructions are halfword aligned; the one descriptor patch is deliberately byte-addressed and not executable code | Proven |
| Calling convention | Runtime non-leaf functions preserve `r4`–`r7` with `PUSH`/`POP`; arguments/results use `r0`–`r3`; `r12` is volatile | Strongly supported AAPCS-like ABI |
| Literal pools | None in the extension. Addresses and constants are formed with `MOVW`/`MOVT`; the only non-code words are seven unreachable marker instructions. | Proven |
| Direct MMIO | Config save accesses `0x40020000`, `0x40020004`, `0x40020010`, and `0x40020014` directly. | Proven addresses; peripheral name unknown |
| Compiler | Thumb-2 code generation is compatible with common ARM embedded toolchains, but no compiler/version attribution is justified. | Unknown |

No FPU or DSP instruction is used. No claim is made that this identifies a
specific Cortex-M SKU, flash-controller model, or compiler.

## Control-flow recovery

`tools/disassemble.py` verifies the JSON SHA-256, decodes every
reachable function with Capstone at the correct load address, follows direct
calls/branches from each hook entry, and refuses any non-marker instruction
that remains outside this CFG. It emits `build/runtime.disasm.txt` and
`build/hooks.resolved.json`. `symbols.json` is the checked-in machine-readable
function map.

The seven words at `0x0800CC00`, `0x0800CC2E`, `0x0800CC60`,
`0x0800CC8E`, `0x0800CCA6`, `0x0800CCBE`, and `0x0800CD22` encode
`MOVW r12,#0xA101` through `#0xA107`. All known hook branches land immediately
after them, so they are excluded from the reachable CFG. Their original
meaning is unknown. `0x0800CD3C` similarly writes `r12 = 0xA108`, but that
word is executed before the feature-command handler and is therefore part of
that function.

## Function map

| Runtime address | Size | Recovered name | Purpose | Confidence |
| --- | ---: | --- | --- | --- |
| `0x0800CC04` | 42 | `runtime_hook_get_feature` | HID GET_REPORT interception for report ID `0x16` | Proven |
| `0x0800CC32` | 46 | `runtime_hook_set_feature` | HID SET_REPORT reception interception for report ID `0x16` | Proven |
| `0x0800CC64` | 42 | `runtime_hook_dispatch_feature` | Route report `0x16` to runtime command processing | Proven |
| `0x0800CC92` | 20 | `runtime_hook_ema_weight` | Replace stock EMA weight argument | Proven |
| `0x0800CCAA` | 20 | `runtime_hook_average_window` | Replace stock moving-average window argument | Proven |
| `0x0800CCC2` | 96 | `runtime_hook_settle_delay` | Map target Hz to each stock delay and tail-call stock wait | Proven |
| `0x0800CD26` | 22 | `runtime_hook_barrel_rescan` | Conditionally skip stock five-slot barrel rescan | Proven |
| `0x0800CD3C` | 582 | `runtime_feature_command_handler` | Validate and service commands 1–6 | Proven |
| `0x0800CF82` | 194 | `runtime_config_initialize` | One-time flash load/validation/default setup | Proven |
| `0x0800D044` | 58 | `runtime_crc32` | Reflected CRC-32/ISO-HDLC | Proven |
| `0x0800D07E` | 102 | `runtime_config_save` | Build record and persist it to flash | Proven |
| `0x0800D0E4` | 94 | `runtime_flash_program_page` | Direct flash unlock/erase/program sequence | Proven |
| `0x0800D142` | 22 | `runtime_flash_lock` | Set flash-control lock bit | Proven |

## Hook map

Every branch destination below is decoded from the *patched* bytes, not copied
from a comment. `r0`–`r3` and `r12` are volatile across each call/tail-call;
callee-saved registers are not written by the small hook wrappers unless the
stock ABI itself does so.

| Runtime hook | Inputs | Output / explicit wrapper clobbers |
| --- | --- | --- |
| GET feature | `r4` stock setup-request pointer, `r5` stock transfer state | No standalone return: tail branches into stock. Uses `r0`–`r2`; writes stack bytes only on the retained stock path. |
| SET feature | `r4` stock setup-request pointer, `r5` stock transfer state | No standalone return: tail branches into stock. Uses `r0`–`r2`. |
| Feature dispatch | Stock caller has zero `r1`/`r2` for normal service path | Calls command handler only for ID `0x16`, then branches to stock continuation; uses `r0`/`r1`. |
| EMA | `r0=current`, `r1=previous`, `r2=stock weight` | `r0=stock EMA result`; wrapper changes `r2`, then stock routine may clobber normal volatile registers. |
| Moving average | `r0=history`, `r1=sample`, `r2=valid count`, `r3=stock window` | `r0=stock average`; wrapper changes `r3`, then tail-calls stock routine. |
| Settle delay | `r0=original delay` | Replaces `r0` and tail-calls stock wait; uses `r0`–`r3` and `r12`. |
| Barrel rescan | `r0`/`r1` opaque stock pointers | Directly returns without writing registers when fast flag is set; otherwise tail-calls stock rescan. |

| Stock site | Original bytes/instruction | Patched target/effect | Return and side effects |
| --- | --- | --- | --- |
| `0x0800B644` | `movs r0,#0x16; strb.w r0,[sp]; movs r0,#1` | `B.W 0x0800CC04` | For ID `0x16`, calls stock feature-send with `r0=r5`, `r1=0x20000C00`, `r2=33`, then branches to stock completion. Otherwise reproduces all overwritten stores, including the following `strb [sp,#1]`, and branches to `0x0800B64C`. |
| `0x0800B6A4` | `movs r2,#8; ldr r1,[pc,#0xe8]; mov r0,r5` | `B.W 0x0800CC32` | For ID `0x16`, receives 33 bytes into `0x20000C00`. Otherwise supplies the original 8-byte buffer `0x20000046`; both paths branch to stock completion. |
| `0x0800B7B4` | load/check report ID and conditional branch | `B.W 0x0800CC64` | Runtime report ID calls the handler and continues at `0x0800B7C4`. Other control flow returns to stock, including the stock non-custom destination `0x08018446`. |
| `0x0800C579` | HID descriptor item `95 07` | descriptor data `95 20` | This is deliberately **not code** and is at an odd address. It changes Report ID `0x16` Report Count from 7 to 32 bytes. |
| `0x08007782`, `0x08007792`, `0x080077A4`, `0x080077B4` | `BL 0x08004A90` | `BL 0x0800CC92` | Wrapper reads RAM `+0x26`; zero becomes stock `64`, otherwise it is passed as `r2` to stock EMA. It tail-calls stock EMA and returns to the original caller. |
| `0x0800762A`, `0x0800763A` | `BL 0x0800A04C` | `BL 0x0800CCAA` | Wrapper reads RAM `+0x27`; zero becomes stock `4`, otherwise it becomes `r3`, then tail-calls stock moving average. |
| `0x08004D3E`, `0x08004D4C`, `0x08004D5A`, `0x08004D9C` | `BL 0x08006B2E` | `BL 0x0800CCC2` | Wrapper receives each stock delay in `r0`, calculates a replacement, and always tail-calls the stock wait—even if the result is zero. |
| `0x08007E58`, `0x08007ED8` | `BL 0x08006CB4` | `BL 0x0800CD26` | If RAM `+0x28` is nonzero, `BX LR` skips only the stock rescan. The surrounding stock `CPSID I`/`CPSIE I` instructions remain, so interrupt masking side effects are retained. |

## Stock firmware ABI used by the extension

| Address | Recovered external symbol | Evidence / inferred contract |
| --- | --- | --- |
| `0x08004A90` | `stock_ema_interpolate_u32` | Three register arguments and a `uint32_t` result; stock code implements the EMA arithmetic below. |
| `0x08006B2E` | `stock_wait_us` | Takes `r0` microseconds, programs a hardware timer and busy-waits for completion. |
| `0x08006CB4` | `stock_barrel_slot_rescan` | Called with stock tablet/report pointers in `r0`/`r1`; loops five candidate slots. Pointee types are unknown. |
| `0x0800A04C` | `stock_moving_average_u32` | `(history, sample, valid_count, window)` in `r0`–`r3`, returns a `uint32_t`. |
| `0x0800AEA4` | `stock_usb_receive_feature` | Stock feature transfer state in `r0`, destination in `r1`, byte count in `r2`. |
| `0x0800AF00` | `stock_usb_send_feature` | Stock feature transfer state in `r0`, source in `r1`, byte count in `r2`. |
| `0x0800B64C`, `0x0800B6D0`, `0x0800B7BC`, `0x0800B7C4`, `0x08018446` | stock continuations | Branch-only control-flow destinations, not independently typed functions. |

The C declarations in `stock_api.h` are ABI documentation. The exact build
uses named assembly `.equ` values instead of pretending these stock functions
have link-time relocations.

## Recovered data layouts

The wire frame in RAM includes a HID report-ID byte that WebHID handles
separately. Its exact 33-byte layout is asserted in `protocol.h`.

| RAM offset from `0x20000C00` | Width | Meaning | Confidence |
| --- | ---: | --- | --- |
| `+0x00..+0x20` | 33 | `S620RuntimeWireFrame`: report ID, 32-byte host frame | Proven |
| `+0x21..+0x23` | 3 | Not accessed by this blob | Proven non-use; meaning unknown |
| `+0x24` | 2 | Target rate in Hz, little-endian | Proven |
| `+0x26` | 1 | EMA weight | Proven |
| `+0x27` | 1 | Moving-average window | Proven |
| `+0x28` | 1 | Fast barrel-button flag (normalized to 0/1) | Proven |
| `+0x29` | 1 | Initialization magic `0xA5` | Proven |
| `+0x2A` | 1 | Unsaved flag: set by config/default change, cleared at initialization/save | Proven |
| `+0x2B` | 1 | Never accessed | Unknown |
| `+0x2C` | 4 | Returned as telemetry counter, never written by this blob | Proven access; semantics unknown |

The persistent record at `0x0800F800` is exactly the 24-byte packed
`S620PersistentConfig` in `config.h`: magic `CTC1`, version 1, target rate,
EMA, window, boolean barrel flag, nine zero reserved bytes, and little-endian
CRC-32 over offsets 0–19. Every offset and size has a C `_Static_assert`.

## Protocol and command behaviour

The runtime operates on `report-id | command | sequence | payload length |
status | payload[24] | crc32`, verifies CRC over the 28 bytes beginning at
`command`, and writes the response in place. CRC is CRC-32/ISO-HDLC: initial
`0xFFFFFFFF`, reflected polynomial `0xEDB88320`, eight LSB-first rounds per
byte, and final bitwise complement.

| Command | Actual byte | Observed result |
| --- | ---: | --- |
| Get info | `1` | Protocol 1, firmware version `1.1`, model `0x0620`, stock ID `0x00241030`, capabilities `0x0B`, range 294–530, config size 24, persistence 1. |
| Get config | `2` | Returns the exact 24-byte config record generated from runtime RAM. |
| Set config | `3` | Requires 24 bytes plus matching magic/version/CRC; clamps target to 294–530, zero EMA to 64, window to 1–4, normalizes barrel flag, then marks unsaved. Reserved input bytes are not inspected or retained. |
| Save config | `4` | Writes RAM configuration to `0x0800F800` and clears unsaved without a hardware-error result. |
| Factory defaults | `5` | Restores 294 Hz, EMA 64, window 4, barrel false, marks unsaved. |
| Get telemetry | `6` | Returns target Hz, target×10, RAM word `+0x2C`, zero counters, static bytes `[227,20,30,150]`, mode 0, unsaved byte, and zero loop time. |

The command mapping above was verified by executing all six commands against
the blob; earlier notes had commands 5 and 6 reversed. The blob advertises capability bit 3 but does **not**
measure loop time: its returned loop-time field is always zero. It also does
not implement adaptive scanning, report/full-scan/tracking-loss counters, or a
live four-element settle telemetry vector. Those host-side interpretations are
not part of this binary.

## Filter path

The runtime does not use the old fixed bypass at `0x0800760E`. It leaves the
stock path alive and replaces only its parameters through six call hooks.

Stock moving average (`0x0800A04C`) uses unsigned 32-bit samples and history
words. If `valid_count > window`, it shifts history left, writes the sample at
`window - 1`, sums `window` values and performs unsigned `UDIV`. Otherwise it
sums `valid_count - 1` existing values plus the sample, writes at
`valid_count - 1`, and divides by `valid_count`. Addition wraps at 32 bits;
there is no saturation or rounding beyond truncating unsigned division.

Stock EMA (`0x08004A90`) compares `current` and `previous` unsigned. For a
difference `d`, it computes `q = ((weight * d) + 128) >> 8` using the low
32-bit product, then returns `previous - q` or `previous + q`; equal inputs
return `previous`. There is no float conversion and no saturation.

`emaWeight == 255` has no special branch in the runtime. It is passed to this
routine exactly like any nonzero weight, so it is a near-bypass in many cases,
not an exact “EMA off” mode. `emaWeight == 0` is converted to 64. The average
window accepts 1–4; zero becomes 4.

## Polling-rate and settle logic

The device, not `timing.ts`, converts target rate at every delay hook. Let
`h` be the little-endian RAM target and `d` the original delay in `r0`:

```text
if h == 0:                 output = d
else:
    h = clamp(h, 294, 530)
    budget = floor((530 - h) * 221 / 236) + 6
    if budget == 6 and d == 20:
        output = 0
    else:
        output = floor((budget * d + 113) / 227)
stock_wait_us(output)      # always called
```

For the stock `d = [27,20,30,150]`, target 294 returns exactly the stock
profile. Target 530 yields exactly `[1,0,1,4]`. The zero is passed to
`stock_wait_us`; the call is not skipped. No loop-time measurement, closed
loop calibration, fixed-work optimization, or target above 530 exists in the
runtime. The host’s historical timing model is explicitly marked as such.

## Fast barrel buttons

At both stock sites, `fastBarrelButtons != 0` returns before calling
`stock_barrel_slot_rescan` at `0x08006CB4`. The original routine scans five
candidate slots and can update the supplied stock structures. Fast mode skips
all of those writes. It does not bypass the caller’s interrupt disable/enable
pair or alter later barrel-state handling.

## Persistence and MMIO

Initialization first checks RAM `+0x29` for `0xA5`. Otherwise it validates
flash `0x0800F800`: magic, version, CRC, target range, nonzero EMA, and
average-window range. It normalizes, rather than validates, the barrel flag;
the nine reserved bytes are not inspected. Any failure installs defaults.
Successful load and fallback both set `+0x29 = 0xA5` and clear unsaved.

Save builds the record in RAM, then writes two keys (`0x45670123` and
`0xCDEF89AB`) to `0x40020004`, selects erase/program control bits at
`0x40020010`, places `0x0800F800` in `0x40020014`, polls bit 0 at
`0x40020000`, writes 12 halfwords to flash, and finally sets bit 7 at
`0x40020010`. The exact peripheral name and register semantics are not
established from the blob alone.

**Strongly supported power-loss behaviour:** save erases before programming
the single record, and boot rejects records whose magic/version/CRC/ranges do
not validate. Therefore an interrupted erase/program falls back to defaults
rather than accepting a partial record. There is no wear levelling, error
status, retry, or readback verification in this blob.

## Remaining uncertainties

- The exact GD32 part, clock setup, and compiler/toolchain are not recoverable
  from the extension and are not guessed here.
- Types and full side effects of stock USB transfer, acquisition, and barrel
  structures are opaque; only register contracts at runtime call sites are
  documented.
- The purpose of marker values `0xA101`–`0xA108` is unknown. Seven are outside
  the known CFG; the eighth executes as a volatile `r12` write before command
  handling.
- The `+0x2C` telemetry word’s producer is absent from the blob. It may be
  zeroed by system startup or written elsewhere, but that is not established.
- Actual report rate, jitter, pen quality, and flash-controller error handling
  require hardware observation. No device was flashed or emulated as hardware
  for this reconstruction.

## Commands

Create an isolated analysis environment once:

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

Then run:

```sh
python tools/build_runtime.py
python tools/disassemble.py
python tools/test_runtime.py

# Requires Zig; tested with 0.16.0.
python tools/build_editable.py
python tools/test_editable.py
```

`test_runtime.py` verifies the exact assembly, CFG/hook map, and isolated
settle-hook execution. `test_editable.py` builds the size-optimized C version
and compares its command responses and settle calculations with the original
blob under Unicorn. The linker rejects an editable image larger than the
original 1,368-byte slot.
