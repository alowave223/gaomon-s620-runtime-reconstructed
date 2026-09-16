/* Recovered persistent configuration layout; not claimed to be original source. */
#pragma once

#include <stddef.h>
#include <stdint.h>

enum {
  S620_CONFIG_MAGIC = 0x31435443u, /* bytes: C T C 1 */
  S620_CONFIG_VERSION = 1,
  S620_CONFIG_SIZE = 24,
  S620_CONFIG_CRC_OFFSET = 20,
  S620_TARGET_HZ_MIN = 294,
  S620_TARGET_HZ_MAX = 530,
};

typedef struct __attribute__((packed)) {
  uint32_t magic_le;
  uint16_t version_le;
  uint16_t target_hz_le;
  uint8_t ema_weight;
  uint8_t average_window;
  uint8_t fast_barrel_buttons;
  uint8_t reserved[9];
  uint32_t crc32_le;
} S620PersistentConfig;

_Static_assert(sizeof(S620PersistentConfig) == S620_CONFIG_SIZE, "config size");
_Static_assert(offsetof(S620PersistentConfig, target_hz_le) == 6, "target offset");
_Static_assert(offsetof(S620PersistentConfig, ema_weight) == 8, "EMA offset");
_Static_assert(offsetof(S620PersistentConfig, average_window) == 9, "average offset");
_Static_assert(offsetof(S620PersistentConfig, fast_barrel_buttons) == 10, "barrel offset");
_Static_assert(offsetof(S620PersistentConfig, crc32_le) == S620_CONFIG_CRC_OFFSET, "CRC offset");
