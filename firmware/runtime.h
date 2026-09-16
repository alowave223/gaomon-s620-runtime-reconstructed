/* Known RAM state prefix recovered from the injected binary. */
#pragma once

#include <stddef.h>
#include <stdint.h>

#include "config.h"
#include "protocol.h"

enum {
  S620_RUNTIME_BASE = 0x0800cc00u,
  S620_RUNTIME_SIZE = 1368u,
  S620_RUNTIME_RAM = 0x20000c00u,
  S620_PERSISTENCE_BASE = 0x0800f800u,
};

/* Bytes at offsets 0x21..0x23 are not accessed by the runtime blob. */
typedef struct __attribute__((packed)) {
  S620RuntimeWireFrame wire;
  uint8_t unknown_21_to_23[3];
  uint16_t target_hz_le;
  uint8_t ema_weight;
  uint8_t average_window;
  uint8_t fast_barrel_buttons;
  uint8_t initialized_magic; /* observed value 0xa5 */
  uint8_t unsaved;
  uint8_t unknown_2b;
  uint32_t telemetry_counter; /* read by GET_TELEMETRY; never written by this blob */
} S620RuntimeRamPrefix;

_Static_assert(offsetof(S620RuntimeRamPrefix, target_hz_le) == 0x24, "target state offset");
_Static_assert(offsetof(S620RuntimeRamPrefix, ema_weight) == 0x26, "EMA state offset");
_Static_assert(offsetof(S620RuntimeRamPrefix, average_window) == 0x27, "average state offset");
_Static_assert(offsetof(S620RuntimeRamPrefix, fast_barrel_buttons) == 0x28, "barrel state offset");
_Static_assert(offsetof(S620RuntimeRamPrefix, initialized_magic) == 0x29, "init state offset");
_Static_assert(offsetof(S620RuntimeRamPrefix, unsaved) == 0x2a, "unsaved state offset");
_Static_assert(offsetof(S620RuntimeRamPrefix, telemetry_counter) == 0x2c, "counter offset");
