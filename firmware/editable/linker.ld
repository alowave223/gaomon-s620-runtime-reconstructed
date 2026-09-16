ENTRY(runtime_feature_command_handler)

stock_usb_send_feature = 0x0800AF00;
stock_usb_receive_feature = 0x0800AEA4;
stock_usb_control_complete = 0x0800B6D0;
stock_feature_get_continue = 0x0800B64C;
stock_feature_dispatch_noncustom = 0x08018446;
stock_feature_dispatch_normal = 0x0800B7BC;
stock_feature_dispatch_continue = 0x0800B7C4;
stock_ema_interpolate_u32 = 0x08004A90;
stock_moving_average_u32 = 0x0800A04C;
stock_wait_us = 0x08006B2E;
stock_barrel_slot_rescan = 0x08006CB4;

MEMORY {
  RUNTIME (rx) : ORIGIN = 0x0800CC00, LENGTH = 0x558
}

SECTIONS {
  .text ORIGIN(RUNTIME) : ALIGN(4) {
    KEEP(*(.hooks))
    *(.text .text.*)
    *(.rodata .rodata.*)
    . = ALIGN(4);
  } > RUNTIME

  /DISCARD/ : {
    *(.ARM.exidx*) *(.ARM.extab*) *(.comment*) *(.note*)
  }

  __runtime_start = ORIGIN(RUNTIME);
  __runtime_end = .;
  ASSERT(__runtime_end <= ORIGIN(RUNTIME) + LENGTH(RUNTIME),
         "editable runtime exceeds the original 0x558-byte slot")
}
