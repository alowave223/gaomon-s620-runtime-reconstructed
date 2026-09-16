/* Recovered S620 runtime wire layout; not claimed to be original source. */
#pragma once

#include <stddef.h>
#include <stdint.h>

enum {
  S620_RUNTIME_REPORT_ID = 0x16,
  S620_RUNTIME_HOST_FRAME_SIZE = 32,
  S620_RUNTIME_WIRE_SIZE = 33,
  S620_RUNTIME_PAYLOAD_SIZE = 24,
  S620_RUNTIME_CRC_OFFSET = 29,
};

/* Firmware includes the HID report ID at byte zero; WebHID does not. */
typedef struct __attribute__((packed)) {
  uint8_t report_id;
  uint8_t command;
  uint8_t sequence;
  uint8_t payload_length;
  uint8_t status;
  uint8_t payload[S620_RUNTIME_PAYLOAD_SIZE];
  uint32_t crc32_le;
} S620RuntimeWireFrame;

_Static_assert(sizeof(S620RuntimeWireFrame) == S620_RUNTIME_WIRE_SIZE, "wire frame size");
_Static_assert(offsetof(S620RuntimeWireFrame, command) == 1, "command offset");
_Static_assert(offsetof(S620RuntimeWireFrame, payload) == 5, "payload offset");
_Static_assert(offsetof(S620RuntimeWireFrame, crc32_le) == S620_RUNTIME_CRC_OFFSET, "CRC offset");
