.syntax unified
.thumb

.equ runtime_ram,                      0x20000c00
.section .hooks, "ax", %progbits
.align 2

.global runtime_hook_get_feature
.thumb_func
runtime_hook_get_feature:
  ldrb r0, [r4, #2]
  cmp r0, #0x16
  bne 1f
  ldr r1, =runtime_ram
  movs r2, #33
  mov r0, r5
  bl stock_usb_send_feature
  b.w stock_usb_control_complete
1:
  movs r0, #0x16
  strb r0, [sp]
  movs r0, #1
  strb r0, [sp, #1]
  b.w stock_feature_get_continue

.global runtime_hook_set_feature
.thumb_func
runtime_hook_set_feature:
  ldrb r0, [r4, #2]
  cmp r0, #0x16
  bne 2f
  movs r2, #33
  ldr r1, =runtime_ram
  mov r0, r5
  bl stock_usb_receive_feature
  b.w stock_usb_control_complete
2:
  movs r2, #8
  ldr r1, =0x20000046
  mov r0, r5
  bl stock_usb_receive_feature
  b.w stock_usb_control_complete

.global runtime_hook_dispatch_feature
.thumb_func
runtime_hook_dispatch_feature:
  ldr r0, =runtime_ram
  ldrb r1, [r0]
  cmp r1, #0x16
  beq 3f
  ldr r0, =0x20000046
  ldrb r0, [r0]
  cmp r0, #0x16
  bne.w stock_feature_dispatch_noncustom
  b.w stock_feature_dispatch_normal
3:
  bl runtime_feature_command_handler
  b.w stock_feature_dispatch_continue

.global runtime_hook_ema_weight
.thumb_func
runtime_hook_ema_weight:
  ldr ip, =runtime_ram
  ldrb r2, [ip, #0x26]
  cbnz r2, 4f
  movs r2, #64
4:
  b.w stock_ema_interpolate_u32

.global runtime_hook_average_window
.thumb_func
runtime_hook_average_window:
  ldr ip, =runtime_ram
  ldrb r3, [ip, #0x27]
  cbnz r3, 5f
  movs r3, #4
5:
  b.w stock_moving_average_u32

.global runtime_hook_settle_delay
.thumb_func
runtime_hook_settle_delay:
  push {lr}
  bl runtime_scale_settle_delay
  pop {lr}
  b.w stock_wait_us

.global runtime_hook_barrel_rescan
.thumb_func
runtime_hook_barrel_rescan:
  ldr ip, =runtime_ram
  ldrb r2, [ip, #0x28]
  cmp r2, #0
  beq 6f
  bx lr
6:
  b.w stock_barrel_slot_rescan

.ltorg
