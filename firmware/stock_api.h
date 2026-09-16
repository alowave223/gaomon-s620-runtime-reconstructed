/*
 * Stock-firmware ABI declarations inferred from call sites.
 *
 * This header documents ABI boundaries; runtime.S uses the matching named
 * .equ symbols so the byte-exact raw-image build has no linker relocation.
 */
#pragma once

#include <stdint.h>

enum {
  STOCK_USB_SEND_FEATURE = 0x0800af00u,
  STOCK_USB_RECEIVE_FEATURE = 0x0800aea4u,
  STOCK_EMA_INTERPOLATE_U32 = 0x08004a90u,
  STOCK_MOVING_AVERAGE_U32 = 0x0800a04cu,
  STOCK_WAIT_US = 0x08006b2eu,
  STOCK_BARREL_SLOT_RESCAN = 0x08006cb4u,
};

/* Strongly supported signatures; parameter pointee types remain opaque. */
uint32_t stock_ema_interpolate_u32(uint32_t current, uint32_t previous, uint32_t weight);
uint32_t stock_moving_average_u32(uint32_t *history, uint32_t sample, uint32_t valid_count, uint32_t window);
void stock_wait_us(uint32_t microseconds);
void stock_barrel_slot_rescan(void *tablet_state, void *report_state);
void stock_usb_send_feature(void *transfer_state, const void *wire_bytes, uint32_t wire_length);
void stock_usb_receive_feature(void *transfer_state, void *wire_bytes, uint32_t wire_length);
