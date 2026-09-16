#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "../config.h"
#include "../protocol.h"
#include "../runtime.h"

enum {
  COMMAND_GET_INFO = 1,
  COMMAND_GET_CONFIG = 2,
  COMMAND_SET_CONFIG = 3,
  COMMAND_SAVE_CONFIG = 4,
  COMMAND_FACTORY_DEFAULTS = 5,
  COMMAND_GET_TELEMETRY = 6,

  STATUS_OK = 0,
  STATUS_BAD_CRC = 1,
  STATUS_BAD_LENGTH = 2,
  STATUS_UNKNOWN_COMMAND = 3,
  STATUS_BAD_CONFIG = 4,

  INITIALIZED_MAGIC = 0xa5,
  STOCK_EMA_WEIGHT = 64,
  STOCK_AVERAGE_WINDOW = 4,

  FLASH_STATUS = 0x40020000u,
  FLASH_KEY = 0x40020004u,
  FLASH_CONTROL = 0x40020010u,
  FLASH_ADDRESS = 0x40020014u,
};

static volatile S620RuntimeRamPrefix *const runtime =
    (volatile S620RuntimeRamPrefix *)S620_RUNTIME_RAM;
static const S620PersistentConfig *const saved_config =
    (const S620PersistentConfig *)S620_PERSISTENCE_BASE;

static uint16_t clamp_u16(uint16_t value, uint16_t low, uint16_t high) {
  if (value < low) return low;
  if (value > high) return high;
  return value;
}

static void clear_bytes(uint8_t *bytes, uint32_t count) {
  while (count--) *bytes++ = 0;
}

uint32_t runtime_crc32(const void *data, uint32_t length) {
  const uint8_t *bytes = data;
  uint32_t crc = UINT32_MAX;

  while (length--) {
    crc ^= *bytes++;
    for (uint32_t bit = 0; bit < 8; ++bit) {
      crc = (crc >> 1) ^ ((crc & 1u) ? 0xedb88320u : 0u);
    }
  }
  return ~crc;
}

static void install_defaults(bool mark_unsaved) {
  runtime->target_hz_le = S620_TARGET_HZ_MIN;
  runtime->ema_weight = STOCK_EMA_WEIGHT;
  runtime->average_window = STOCK_AVERAGE_WINDOW;
  runtime->fast_barrel_buttons = 0;
  runtime->initialized_magic = INITIALIZED_MAGIC;
  runtime->unsaved = mark_unsaved;
}

static bool config_valid(const S620PersistentConfig *config) {
  return config->magic_le == S620_CONFIG_MAGIC &&
         config->version_le == S620_CONFIG_VERSION &&
         runtime_crc32(config, S620_CONFIG_CRC_OFFSET) == config->crc32_le &&
         config->target_hz_le >= S620_TARGET_HZ_MIN &&
         config->target_hz_le <= S620_TARGET_HZ_MAX &&
         config->ema_weight != 0 &&
         config->average_window >= 1 && config->average_window <= 4;
}

static void load_config(const S620PersistentConfig *config) {
  runtime->target_hz_le = config->target_hz_le;
  runtime->ema_weight = config->ema_weight;
  runtime->average_window = config->average_window;
  runtime->fast_barrel_buttons = config->fast_barrel_buttons != 0;
  runtime->initialized_magic = INITIALIZED_MAGIC;
  runtime->unsaved = 0;
}

void runtime_config_initialize(void) {
  if (runtime->initialized_magic == INITIALIZED_MAGIC) return;
  if (config_valid(saved_config)) load_config(saved_config);
  else install_defaults(false);
}

static void export_config(S620PersistentConfig *config) {
  config->magic_le = S620_CONFIG_MAGIC;
  config->version_le = S620_CONFIG_VERSION;
  config->target_hz_le = runtime->target_hz_le;
  config->ema_weight = runtime->ema_weight;
  config->average_window = runtime->average_window;
  config->fast_barrel_buttons = runtime->fast_barrel_buttons;
  clear_bytes(config->reserved, sizeof(config->reserved));
  config->crc32_le = runtime_crc32(config, S620_CONFIG_CRC_OFFSET);
}

static void flash_wait(void) {
  while (*(volatile uint32_t *)FLASH_STATUS & 1u) {}
}

static void flash_begin_program(void) {
  *(volatile uint32_t *)FLASH_KEY = 0x45670123u;
  *(volatile uint32_t *)FLASH_KEY = 0xcdef89abu;
  *(volatile uint32_t *)FLASH_CONTROL |= 2u;
  *(volatile uint32_t *)FLASH_ADDRESS = S620_PERSISTENCE_BASE;
  *(volatile uint32_t *)FLASH_CONTROL |= 0x40u;
  flash_wait();
  *(volatile uint32_t *)FLASH_CONTROL &= ~2u;
}

static void flash_lock(void) {
  *(volatile uint32_t *)FLASH_CONTROL |= 0x80u;
}

static void save_config(void) {
  S620PersistentConfig config;
  export_config(&config);
  flash_begin_program();

  volatile uint16_t *destination =
      (volatile uint16_t *)S620_PERSISTENCE_BASE;
  const uint16_t *source = (const uint16_t *)&config;
  for (uint32_t index = 0; index < sizeof(config) / 2; ++index) {
    destination[index] = source[index];
  }
  flash_lock();
  runtime->unsaved = 0;
}

uint32_t runtime_scale_settle_delay(uint32_t stock_delay) {
  uint16_t target = runtime->target_hz_le;
  if (target == 0) return stock_delay;

  target = clamp_u16(target, S620_TARGET_HZ_MIN, S620_TARGET_HZ_MAX);
  uint32_t budget = ((uint32_t)(S620_TARGET_HZ_MAX - target) * 221u) / 236u + 6u;
  if (budget == 6u && stock_delay == 20u) return 0;
  return (budget * stock_delay + 113u) / 227u;
}

static uint8_t command_get_info(uint8_t *payload) {
  const uint8_t info[21] = {
      1, 0, 1, 1, 0x20, 0x06, 0x30, 0x10, 0x24, 0x00, 0x0b,
      0, 0, 0, 0x26, 0x01, 0x12, 0x02, 24, 0, 1,
  };
  for (uint32_t i = 0; i < sizeof(info); ++i) payload[i] = info[i];
  return sizeof(info);
}

static uint8_t command_get_config(uint8_t *payload) {
  export_config((S620PersistentConfig *)payload);
  return sizeof(S620PersistentConfig);
}

static bool command_set_config(const uint8_t *payload, uint8_t length) {
  if (length != sizeof(S620PersistentConfig)) return false;
  const S620PersistentConfig *config = (const S620PersistentConfig *)payload;
  if (config->magic_le != S620_CONFIG_MAGIC ||
      config->version_le != S620_CONFIG_VERSION ||
      runtime_crc32(config, S620_CONFIG_CRC_OFFSET) != config->crc32_le) {
    return false;
  }

  runtime->target_hz_le = clamp_u16(
      config->target_hz_le, S620_TARGET_HZ_MIN, S620_TARGET_HZ_MAX);
  runtime->ema_weight = config->ema_weight ? config->ema_weight : STOCK_EMA_WEIGHT;
  uint8_t window = config->average_window;
  runtime->average_window = (window >= 1 && window <= 4) ? window : STOCK_AVERAGE_WINDOW;
  runtime->fast_barrel_buttons = config->fast_barrel_buttons != 0;
  runtime->initialized_magic = INITIALIZED_MAGIC;
  runtime->unsaved = 1;
  return true;
}

static uint8_t command_get_telemetry(uint8_t *payload) {
  const uint16_t target = runtime->target_hz_le;
  clear_bytes(payload, S620_RUNTIME_PAYLOAD_SIZE);
  payload[0] = (uint8_t)target;
  payload[1] = (uint8_t)(target >> 8);
  const uint16_t target_times_ten = (uint16_t)(target * 10u);
  payload[2] = (uint8_t)target_times_ten;
  payload[3] = (uint8_t)(target_times_ten >> 8);
  const uint32_t counter = runtime->telemetry_counter;
  payload[4] = (uint8_t)counter;
  payload[5] = (uint8_t)(counter >> 8);
  payload[6] = (uint8_t)(counter >> 16);
  payload[7] = (uint8_t)(counter >> 24);
  payload[16] = 227;
  payload[17] = 20;
  payload[18] = 30;
  payload[19] = 150;
  payload[21] = runtime->unsaved;
  return S620_RUNTIME_PAYLOAD_SIZE;
}

void runtime_feature_command_handler(void) {
  runtime_config_initialize();
  volatile S620RuntimeWireFrame *wire = &runtime->wire;
  const uint8_t command = wire->command;
  const uint8_t length = wire->payload_length;
  uint8_t status = STATUS_OK;
  uint8_t response_length = 0;

  if (length > S620_RUNTIME_PAYLOAD_SIZE) status = STATUS_BAD_LENGTH;
  else if (runtime_crc32((const void *)&wire->command, 28) != wire->crc32_le)
    status = STATUS_BAD_CRC;
  else if (command == COMMAND_SET_CONFIG) {
    if (!command_set_config((const uint8_t *)wire->payload, length))
      status = length == sizeof(S620PersistentConfig) ? STATUS_BAD_CONFIG : STATUS_BAD_LENGTH;
  } else {
    clear_bytes((uint8_t *)wire->payload, S620_RUNTIME_PAYLOAD_SIZE);
    if (length != 0) status = STATUS_BAD_LENGTH;
    else if (command == COMMAND_GET_INFO)
      response_length = command_get_info((uint8_t *)wire->payload);
    else if (command == COMMAND_GET_CONFIG)
      response_length = command_get_config((uint8_t *)wire->payload);
    else if (command == COMMAND_GET_TELEMETRY)
      response_length = command_get_telemetry((uint8_t *)wire->payload);
    else if (command == COMMAND_SAVE_CONFIG)
      save_config();
    else if (command == COMMAND_FACTORY_DEFAULTS)
      install_defaults(true);
    else
      status = STATUS_UNKNOWN_COMMAND;
  }

  wire->status = status;
  wire->payload_length = status == STATUS_OK ? response_length : 0;
  wire->crc32_le = runtime_crc32((const void *)&wire->command, 28);
}
