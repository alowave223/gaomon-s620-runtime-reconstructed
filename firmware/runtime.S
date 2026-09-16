/*
 * Reconstructed from reference/runtime.json, not original source.
 *
 * This file is a byte-exact, annotated Thumb-2 reconstruction.  Instruction
 * addresses are part of the source because stock hook branches target them.
 * Assemble with tools/build_runtime.py; it uses Keystone only for
 * ordinary instructions and records raw encodings where Keystone 0.9.2 cannot
 * encode the observed Thumb-2 instruction.
 */
.syntax unified
.thumb
.org 0x0800cc00

.equ stock_usb_send_feature,          0x0800af00
.equ stock_usb_control_complete,      0x0800b6d0
.equ stock_feature_get_continue,      0x0800b64c
.equ stock_usb_receive_feature,       0x0800aea4
.equ stock_feature_dispatch_noncustom,0x08018446
.equ stock_feature_dispatch_normal,   0x0800b7bc
.equ stock_feature_dispatch_continue, 0x0800b7c4
.equ stock_ema_interpolate_u32,        0x08004a90
.equ stock_moving_average_u32,         0x0800a04c
.equ stock_wait_us,                    0x08006b2e
.equ stock_barrel_slot_rescan,         0x08006cb4


@ Unreachable 32-bit build marker 0xA101.  No known hook enters here.
.global runtime_marker_a101
runtime_marker_a101:
  /* 0x0800cc00 */ movw ip, #0xa101

@ Hook 0x0800B644: vendor GET_REPORT interception.
@ Input follows the stock USB control dispatcher (r4 points at request, r5 at
@ transfer state).  For report ID 0x16 it sends 33 bytes from runtime_io; for
@ all other report IDs it reproduces every overwritten instruction and returns
@ to the stock continuation.  Tail calls preserve the stock ABI.
.global runtime_hook_get_feature
runtime_hook_get_feature:
  /* 0x0800cc04 */ ldrb r0, [r4, #2]
  /* 0x0800cc06 */ cmp r0, #0x16
  /* 0x0800cc08 */ bne #0x800cc1e
  /* 0x0800cc0a */ movw r1, #0xc00
  /* 0x0800cc0e */ movt r1, #0x2000
  /* 0x0800cc12 */ movs r2, #0x21
  /* 0x0800cc14 */ mov r0, r5
  /* 0x0800cc16 */ bl #stock_usb_send_feature
  /* 0x0800cc1a */ b.w #stock_usb_control_complete
  /* 0x0800cc1e */ movs r0, #0x16
  /* 0x0800cc20 */ strb.w r0, [sp]
  /* 0x0800cc24 */ movs r0, #1
  /* 0x0800cc26 */ strb.w r0, [sp, #1]
  /* 0x0800cc2a */ b.w #stock_feature_get_continue

@ Unreachable 32-bit build marker 0xA102.  No known hook enters here.
.global runtime_marker_a102
runtime_marker_a102:
  /* 0x0800cc2e */ movw ip, #0xa102

@ Hook 0x0800B6A4: vendor SET_REPORT reception interception.
@ Report 0x16 is received into runtime_io (33 bytes); all other reports retain
@ stock's 8-byte destination and path.
.global runtime_hook_set_feature
runtime_hook_set_feature:
  /* 0x0800cc32 */ ldrb r0, [r4, #2]
  /* 0x0800cc34 */ cmp r0, #0x16
  /* 0x0800cc36 */ bne #0x800cc4c
  /* 0x0800cc38 */ movs r2, #0x21
  /* 0x0800cc3a */ movw r1, #0xc00
  /* 0x0800cc3e */ movt r1, #0x2000
  /* 0x0800cc42 */ mov r0, r5
  /* 0x0800cc44 */ bl #stock_usb_receive_feature
  /* 0x0800cc48 */ b.w #stock_usb_control_complete
  /* 0x0800cc4c */ movs r2, #8
  /* 0x0800cc4e */ movw r1, #0x46
  /* 0x0800cc52 */ movt r1, #0x2000
  /* 0x0800cc56 */ mov r0, r5
  /* 0x0800cc58 */ bl #stock_usb_receive_feature
  /* 0x0800cc5c */ b.w #stock_usb_control_complete

@ Unreachable 32-bit build marker 0xA103.  No known hook enters here.
.global runtime_marker_a103
runtime_marker_a103:
  /* 0x0800cc60 */ movw ip, #0xa103

@ Hook 0x0800B7B4: feature-report dispatch interception.
@ It invokes runtime_feature_command_handler only when runtime_io[0] is 0x16.
@ Non-runtime dispatch remains in the stock control flow.
.global runtime_hook_dispatch_feature
runtime_hook_dispatch_feature:
  /* 0x0800cc64 */ movw r0, #0xc00
  /* 0x0800cc68 */ movt r0, #0x2000
  /* 0x0800cc6c */ ldrb r1, [r0]
  /* 0x0800cc6e */ cmp r1, #0x16
  /* 0x0800cc70 */ beq #0x800cc86
  /* 0x0800cc72 */ movw r0, #0x46
  /* 0x0800cc76 */ movt r0, #0x2000
  /* 0x0800cc7a */ ldrb r0, [r0]
  /* 0x0800cc7c */ cmp r0, #0x16
  /* 0x0800cc7e */ .hword 0xf04b, 0x83e2  @ bne.w stock_feature_dispatch_noncustom (Keystone 0.9.2 emits a different encoding)
  /* 0x0800cc82 */ b.w #stock_feature_dispatch_normal
  /* 0x0800cc86 */ bl #0x800cd3c
  /* 0x0800cc8a */ b.w #stock_feature_dispatch_continue

@ Unreachable 32-bit build marker 0xA104.  No known hook enters here.
.global runtime_marker_a104
runtime_marker_a104:
  /* 0x0800cc8e */ movw ip, #0xa104

@ Hooks 0x08007782, 0x08007792, 0x080077A4, 0x080077B4.
@ r0=current coordinate, r1=previous filtered coordinate, r2=stock EMA
@ weight.  Substitute runtime_config.ema_weight only when nonzero, otherwise
@ preserve stock weight 64; tail-call the stock integer EMA routine.
.global runtime_hook_ema_weight
runtime_hook_ema_weight:
  /* 0x0800cc92 */ movw ip, #0xc00
  /* 0x0800cc96 */ movt ip, #0x2000
  /* 0x0800cc9a */ ldrb.w r2, [ip, #0x26]
  /* 0x0800cc9e */ cbnz r2, #0x800cca2
  /* 0x0800cca0 */ movs r2, #0x40
  /* 0x0800cca2 */ b.w #stock_ema_interpolate_u32

@ Unreachable 32-bit build marker 0xA105.  No known hook enters here.
.global runtime_marker_a105
runtime_marker_a105:
  /* 0x0800cca6 */ movw ip, #0xa105

@ Hooks 0x0800762A and 0x0800763A.
@ r3 is the stock moving-average window.  Substitute
@ runtime_config.average_window only when nonzero and tail-call stock's exact
@ unsigned moving-average implementation.
.global runtime_hook_average_window
runtime_hook_average_window:
  /* 0x0800ccaa */ movw ip, #0xc00
  /* 0x0800ccae */ movt ip, #0x2000
  /* 0x0800ccb2 */ ldrb.w r3, [ip, #0x27]
  /* 0x0800ccb6 */ cbnz r3, #0x800ccba
  /* 0x0800ccb8 */ movs r3, #4
  /* 0x0800ccba */ b.w #stock_moving_average_u32

@ Unreachable 32-bit build marker 0xA106.  No known hook enters here.
.global runtime_marker_a106
runtime_marker_a106:
  /* 0x0800ccbe */ movw ip, #0xa106

@ Hooks 0x08004D3E, 0x08004D4C, 0x08004D5A, 0x08004D9C.
@ r0 is one stock settle delay (27, 20, 30, or 150 us).  Convert configured
@ target Hz to a shared settle budget with unsigned arithmetic, scale this
@ individual delay, then tail-call stock_wait_us.  Zero target means leave
@ stock delay unchanged.  The r3=20/total=6 special case is deliberate.
.global runtime_hook_settle_delay
runtime_hook_settle_delay:
  /* 0x0800ccc2 */ mov r3, r0
  /* 0x0800ccc4 */ movw r1, #0xc00
  /* 0x0800ccc8 */ movt r1, #0x2000
  /* 0x0800cccc */ ldrh r0, [r1, #0x24]
  /* 0x0800ccce */ cmp r0, #0
  /* 0x0800ccd0 */ beq #0x800cd1c
  /* 0x0800ccd2 */ cmp.w r0, #0x126
  /* 0x0800ccd6 */ bhs #0x800ccdc
  /* 0x0800ccd8 */ movw r0, #0x126
  /* 0x0800ccdc */ movw r1, #0x212
  /* 0x0800cce0 */ cmp r0, r1
  /* 0x0800cce2 */ bls #0x800cce8
  /* 0x0800cce4 */ movw r0, #0x212
  /* 0x0800cce8 */ movw r1, #0x212
  /* 0x0800ccec */ subs r1, r1, r0
  /* 0x0800ccee */ movw r2, #0xdd
  /* 0x0800ccf2 */ muls r1, r2, r1
  /* 0x0800ccf4 */ movw r2, #0xec
  /* 0x0800ccf8 */ .hword 0xfbb1, 0xf1f2  @ udiv r1, r1, r2 (Keystone 0.9.2 lacks Thumb UDIV)
  /* 0x0800ccfc */ adds r1, #6
  /* 0x0800ccfe */ cmp r1, #6
  /* 0x0800cd00 */ bne #0x800cd06
  /* 0x0800cd02 */ cmp r3, #0x14
  /* 0x0800cd04 */ beq #0x800cd16
  /* 0x0800cd06 */ muls r3, r1, r3
  /* 0x0800cd08 */ adds r3, #0x71
  /* 0x0800cd0a */ movw r2, #0xe3
  /* 0x0800cd0e */ .hword 0xfbb3, 0xf0f2  @ udiv r0, r3, r2 (Keystone 0.9.2 lacks Thumb UDIV)
  /* 0x0800cd12 */ b.w #stock_wait_us
  /* 0x0800cd16 */ movs r0, #0
  /* 0x0800cd18 */ b.w #stock_wait_us
  /* 0x0800cd1c */ mov r0, r3
  /* 0x0800cd1e */ b.w #stock_wait_us

@ Unreachable 32-bit build marker 0xA107.  No known hook enters here.
.global runtime_marker_a107
runtime_marker_a107:
  /* 0x0800cd22 */ movw ip, #0xa107

@ Hooks 0x08007E58 and 0x08007ED8.
@ If runtime_config.fast_barrel_buttons is nonzero, return directly and skip
@ stock's five-slot rescan.  Otherwise tail-call the stock rescan unchanged.
.global runtime_hook_barrel_rescan
runtime_hook_barrel_rescan:
  /* 0x0800cd26 */ movw ip, #0xc00
  /* 0x0800cd2a */ movt ip, #0x2000
  /* 0x0800cd2e */ ldrb.w r2, [ip, #0x28]
  /* 0x0800cd32 */ cmp r2, #0
  /* 0x0800cd34 */ beq #0x800cd38
  /* 0x0800cd36 */ bx lr
  /* 0x0800cd38 */ b.w #stock_barrel_slot_rescan

@ Runtime feature-report command handler.
@ Parses and validates the 32-byte frame in runtime_io, dispatches commands
@ 1..6, and writes the response in-place.  r4-r7 are saved per AAPCS.
.global runtime_feature_command_handler
runtime_feature_command_handler:
  /* 0x0800cd3c */ movw ip, #0xa108
  /* 0x0800cd40 */ push {r4, r5, r6, r7, lr}
  /* 0x0800cd42 */ movw r4, #0xc00
  /* 0x0800cd46 */ movt r4, #0x2000
  /* 0x0800cd4a */ bl #0x800cf82
  /* 0x0800cd4e */ ldrb r5, [r4, #1]
  /* 0x0800cd50 */ ldrb r7, [r4, #2]
  /* 0x0800cd52 */ ldrb r6, [r4, #3]
  /* 0x0800cd54 */ cmp r6, #0x18
  /* 0x0800cd56 */ bhi #0x800cda2
  /* 0x0800cd58 */ add.w r0, r4, #1
  /* 0x0800cd5c */ movs r1, #0x1c
  /* 0x0800cd5e */ bl #0x800d044
  /* 0x0800cd62 */ ldr.w r1, [r4, #0x1d]
  /* 0x0800cd66 */ cmp r0, r1
  /* 0x0800cd68 */ bne #0x800cd9e
  /* 0x0800cd6a */ cmp r5, #3
  /* 0x0800cd6c */ beq #0x800ce3e
  /* 0x0800cd6e */ movs r0, #0
  /* 0x0800cd70 */ movs r1, #0x18
  /* 0x0800cd72 */ add.w r2, r4, #5
  /* 0x0800cd76 */ strb r0, [r2]
  /* 0x0800cd78 */ adds r2, #1
  /* 0x0800cd7a */ subs r1, #1
  /* 0x0800cd7c */ bne #0x800cd76
  /* 0x0800cd7e */ cmp r5, #1
  /* 0x0800cd80 */ beq #0x800cdb0
  /* 0x0800cd82 */ cmp r5, #2
  /* 0x0800cd84 */ beq #0x800cdf2
  /* 0x0800cd86 */ cmp r5, #3
  /* 0x0800cd88 */ beq #0x800ce3e
  /* 0x0800cd8a */ cmp r5, #4
  /* 0x0800cd8c */ .hword 0xf000, 0x80c7  @ beq.w runtime_command_get_telemetry
  /* 0x0800cd90 */ cmp r5, #5
  /* 0x0800cd92 */ .hword 0xf000, 0x80aa  @ beq.w runtime_command_save_config
  /* 0x0800cd96 */ cmp r5, #6
  /* 0x0800cd98 */ .hword 0xf000, 0x80ce  @ beq.w runtime_command_factory_defaults
  /* 0x0800cd9c */ b #0x800cda6
  /* 0x0800cd9e */ movs r0, #1
  /* 0x0800cda0 */ b #0x800cda8
  /* 0x0800cda2 */ movs r0, #2
  /* 0x0800cda4 */ b #0x800cda8
  /* 0x0800cda6 */ movs r0, #3
  /* 0x0800cda8 */ strb r0, [r4, #4]
  /* 0x0800cdaa */ movs r0, #0
  /* 0x0800cdac */ strb r0, [r4, #3]
  /* 0x0800cdae */ b #0x800ceda
  /* 0x0800cdb0 */ cmp r6, #0
  /* 0x0800cdb2 */ bne #0x800cda2
  /* 0x0800cdb4 */ add.w r1, r4, #5
  /* 0x0800cdb8 */ movs r0, #1
  /* 0x0800cdba */ strh r0, [r1]
  /* 0x0800cdbc */ movw r0, #0x101
  /* 0x0800cdc0 */ strh r0, [r1, #2]
  /* 0x0800cdc2 */ movw r0, #0x620
  /* 0x0800cdc6 */ strh r0, [r1, #4]
  /* 0x0800cdc8 */ movw r0, #0x1030
  /* 0x0800cdcc */ movt r0, #0x24
  /* 0x0800cdd0 */ str.w r0, [r1, #6]
  /* 0x0800cdd4 */ movs r0, #0xb
  /* 0x0800cdd6 */ str.w r0, [r1, #0xa]
  /* 0x0800cdda */ movw r0, #0x126
  /* 0x0800cdde */ strh r0, [r1, #0xe]
  /* 0x0800cde0 */ movw r0, #0x212
  /* 0x0800cde4 */ strh r0, [r1, #0x10]
  /* 0x0800cde6 */ movs r0, #0x18
  /* 0x0800cde8 */ strh r0, [r1, #0x12]
  /* 0x0800cdea */ movs r0, #1
  /* 0x0800cdec */ strb r0, [r1, #0x14]
  /* 0x0800cdee */ movs r0, #0x15
  /* 0x0800cdf0 */ b #0x800ced4
  /* 0x0800cdf2 */ cmp r6, #0
  /* 0x0800cdf4 */ bne #0x800cda2
  /* 0x0800cdf6 */ add.w r1, r4, #5
  /* 0x0800cdfa */ movw r0, #0x5443
  /* 0x0800cdfe */ movt r0, #0x3143
  /* 0x0800ce02 */ str r0, [r1]
  /* 0x0800ce04 */ movs r0, #1
  /* 0x0800ce06 */ strh r0, [r1, #4]
  /* 0x0800ce08 */ movw r2, #0xc00
  /* 0x0800ce0c */ movt r2, #0x2000
  /* 0x0800ce10 */ ldrh r0, [r2, #0x24]
  /* 0x0800ce12 */ strh r0, [r1, #6]
  /* 0x0800ce14 */ ldrb.w r0, [r2, #0x26]
  /* 0x0800ce18 */ strb r0, [r1, #8]
  /* 0x0800ce1a */ ldrb.w r0, [r2, #0x27]
  /* 0x0800ce1e */ strb r0, [r1, #9]
  /* 0x0800ce20 */ ldrb.w r0, [r2, #0x28]
  /* 0x0800ce24 */ strb r0, [r1, #0xa]
  /* 0x0800ce26 */ movs r0, #0
  /* 0x0800ce28 */ str r0, [r1, #0xc]
  /* 0x0800ce2a */ str r0, [r1, #0x10]
  /* 0x0800ce2c */ mov r0, r1
  /* 0x0800ce2e */ movs r1, #0x14
  /* 0x0800ce30 */ bl #0x800d044
  /* 0x0800ce34 */ add.w r1, r4, #5
  /* 0x0800ce38 */ str r0, [r1, #0x14]
  /* 0x0800ce3a */ movs r0, #0x18
  /* 0x0800ce3c */ b #0x800ced4
  /* 0x0800ce3e */ cmp r6, #0x18
  /* 0x0800ce40 */ bne #0x800cda2
  /* 0x0800ce42 */ add.w r0, r4, #5
  /* 0x0800ce46 */ ldr r1, [r0]
  /* 0x0800ce48 */ movw r2, #0x5443
  /* 0x0800ce4c */ movt r2, #0x3143
  /* 0x0800ce50 */ cmp r1, r2
  /* 0x0800ce52 */ bne #0x800cece
  /* 0x0800ce54 */ ldrh r1, [r0, #4]
  /* 0x0800ce56 */ cmp r1, #1
  /* 0x0800ce58 */ bne #0x800cece
  /* 0x0800ce5a */ mov r1, r0
  /* 0x0800ce5c */ movs r1, #0x14
  /* 0x0800ce5e */ bl #0x800d044
  /* 0x0800ce62 */ add.w r1, r4, #5
  /* 0x0800ce66 */ ldr r2, [r1, #0x14]
  /* 0x0800ce68 */ cmp r0, r2
  /* 0x0800ce6a */ bne #0x800cece
  /* 0x0800ce6c */ movw r2, #0xc00
  /* 0x0800ce70 */ movt r2, #0x2000
  /* 0x0800ce74 */ ldrh r0, [r1, #6]
  /* 0x0800ce76 */ cmp.w r0, #0x126
  /* 0x0800ce7a */ bhs #0x800ce80
  /* 0x0800ce7c */ movw r0, #0x126
  /* 0x0800ce80 */ movw r2, #0x212
  /* 0x0800ce84 */ cmp r0, r2
  /* 0x0800ce86 */ bls #0x800ce8c
  /* 0x0800ce88 */ movw r0, #0x212
  /* 0x0800ce8c */ movw r2, #0xc00
  /* 0x0800ce90 */ movt r2, #0x2000
  /* 0x0800ce94 */ strh r0, [r2, #0x24]
  /* 0x0800ce96 */ ldrb r0, [r1, #8]
  /* 0x0800ce98 */ cmp r0, #0
  /* 0x0800ce9a */ bne #0x800ce9e
  /* 0x0800ce9c */ movs r0, #0x40
  /* 0x0800ce9e */ strb.w r0, [r2, #0x26]
  /* 0x0800cea2 */ ldrb r0, [r1, #9]
  /* 0x0800cea4 */ cmp r0, #1
  /* 0x0800cea6 */ bhs #0x800ceaa
  /* 0x0800cea8 */ movs r0, #4
  /* 0x0800ceaa */ cmp r0, #4
  /* 0x0800ceac */ bls #0x800ceb0
  /* 0x0800ceae */ movs r0, #4
  /* 0x0800ceb0 */ strb.w r0, [r2, #0x27]
  /* 0x0800ceb4 */ ldrb r0, [r1, #0xa]
  /* 0x0800ceb6 */ cmp r0, #0
  /* 0x0800ceb8 */ beq #0x800cebc
  /* 0x0800ceba */ movs r0, #1
  /* 0x0800cebc */ strb.w r0, [r2, #0x28]
  /* 0x0800cec0 */ movs r0, #0xa5
  /* 0x0800cec2 */ strb.w r0, [r2, #0x29]
  /* 0x0800cec6 */ movs r0, #1
  /* 0x0800cec8 */ strb.w r0, [r2, #0x2a]
  /* 0x0800cecc */ b #0x800ced2
  /* 0x0800cece */ movs r0, #4
  /* 0x0800ced0 */ b #0x800cda8
  /* 0x0800ced2 */ movs r0, #0
  /* 0x0800ced4 */ movs r1, #0
  /* 0x0800ced6 */ strb r1, [r4, #4]
  /* 0x0800ced8 */ strb r0, [r4, #3]
  /* 0x0800ceda */ add.w r0, r4, #1
  /* 0x0800cede */ movs r1, #0x1c
  /* 0x0800cee0 */ bl #0x800d044
  /* 0x0800cee4 */ str.w r0, [r4, #0x1d]
  /* 0x0800cee8 */ pop {r4, r5, r6, r7, pc}
  /* 0x0800ceea */ cmp r6, #0
  /* 0x0800ceec */ .hword 0xf47f, 0xaf59  @ bne.w runtime_command_error_bad_length
  /* 0x0800cef0 */ movw r2, #0xc00
  /* 0x0800cef4 */ movt r2, #0x2000
  /* 0x0800cef8 */ movw r0, #0x126
  /* 0x0800cefc */ strh r0, [r2, #0x24]
  /* 0x0800cefe */ movs r0, #0x40
  /* 0x0800cf00 */ strb.w r0, [r2, #0x26]
  /* 0x0800cf04 */ movs r0, #4
  /* 0x0800cf06 */ strb.w r0, [r2, #0x27]
  /* 0x0800cf0a */ movs r0, #0
  /* 0x0800cf0c */ strb.w r0, [r2, #0x28]
  /* 0x0800cf10 */ movs r0, #0xa5
  /* 0x0800cf12 */ strb.w r0, [r2, #0x29]
  /* 0x0800cf16 */ movs r0, #1
  /* 0x0800cf18 */ strb.w r0, [r2, #0x2a]
  /* 0x0800cf1c */ b #0x800ced2
  /* 0x0800cf1e */ cmp r6, #0
  /* 0x0800cf20 */ .hword 0xf47f, 0xaf3f  @ bne.w runtime_command_error_bad_length
  /* 0x0800cf24 */ bl #0x800d07e
  /* 0x0800cf28 */ movw r2, #0xc00
  /* 0x0800cf2c */ movt r2, #0x2000
  /* 0x0800cf30 */ movs r0, #0
  /* 0x0800cf32 */ strb.w r0, [r2, #0x2a]
  /* 0x0800cf36 */ b #0x800ced2
  /* 0x0800cf38 */ cmp r6, #0
  /* 0x0800cf3a */ .hword 0xf47f, 0xaf32  @ bne.w runtime_command_error_bad_length
  /* 0x0800cf3e */ add.w r1, r4, #5
  /* 0x0800cf42 */ movw r2, #0xc00
  /* 0x0800cf46 */ movt r2, #0x2000
  /* 0x0800cf4a */ ldrh r0, [r2, #0x24]
  /* 0x0800cf4c */ strh r0, [r1]
  /* 0x0800cf4e */ mov r3, r0
  /* 0x0800cf50 */ movs r0, #0xa
  /* 0x0800cf52 */ muls r3, r0, r3
  /* 0x0800cf54 */ strh r3, [r1, #2]
  /* 0x0800cf56 */ ldr r0, [r2, #0x2c]
  /* 0x0800cf58 */ str r0, [r1, #4]
  /* 0x0800cf5a */ movs r0, #0
  /* 0x0800cf5c */ str r0, [r1, #8]
  /* 0x0800cf5e */ str r0, [r1, #0xc]
  /* 0x0800cf60 */ movs r0, #0
  /* 0x0800cf62 */ strb r0, [r1, #0x14]
  /* 0x0800cf64 */ ldrb.w r0, [r2, #0x2a]
  /* 0x0800cf68 */ strb r0, [r1, #0x15]
  /* 0x0800cf6a */ movs r0, #0
  /* 0x0800cf6c */ strh r0, [r1, #0x16]
  /* 0x0800cf6e */ movs r0, #0xe3
  /* 0x0800cf70 */ strb r0, [r1, #0x10]
  /* 0x0800cf72 */ movs r0, #0x14
  /* 0x0800cf74 */ strb r0, [r1, #0x11]
  /* 0x0800cf76 */ movs r0, #0x1e
  /* 0x0800cf78 */ strb r0, [r1, #0x12]
  /* 0x0800cf7a */ movs r0, #0x96
  /* 0x0800cf7c */ strb r0, [r1, #0x13]
  /* 0x0800cf7e */ movs r0, #0x18
  /* 0x0800cf80 */ b #0x800ced4

@ One-time config initialization and flash persistence load.
@ Validates magic, schema and CRC, validates configuration ranges, otherwise
@ installs defaults.  Marks runtime state initialized regardless of outcome.
.global runtime_config_initialize
runtime_config_initialize:
  /* 0x0800cf82 */ push {lr}
  /* 0x0800cf84 */ movw r2, #0xc00
  /* 0x0800cf88 */ movt r2, #0x2000
  /* 0x0800cf8c */ ldrb.w r0, [r2, #0x29]
  /* 0x0800cf90 */ cmp r0, #0xa5
  /* 0x0800cf92 */ beq #0x800d042
  /* 0x0800cf94 */ movw r0, #0xf800
  /* 0x0800cf98 */ movt r0, #0x800
  /* 0x0800cf9c */ ldr r1, [r0]
  /* 0x0800cf9e */ movw r3, #0x5443
  /* 0x0800cfa2 */ movt r3, #0x3143
  /* 0x0800cfa6 */ cmp r1, r3
  /* 0x0800cfa8 */ bne #0x800d01a
  /* 0x0800cfaa */ ldrh r1, [r0, #4]
  /* 0x0800cfac */ cmp r1, #1
  /* 0x0800cfae */ bne #0x800d01a
  /* 0x0800cfb0 */ mov r1, r0
  /* 0x0800cfb2 */ movs r1, #0x14
  /* 0x0800cfb4 */ bl #0x800d044
  /* 0x0800cfb8 */ movw r2, #0xf800
  /* 0x0800cfbc */ movt r2, #0x800
  /* 0x0800cfc0 */ ldr r1, [r2, #0x14]
  /* 0x0800cfc2 */ cmp r0, r1
  /* 0x0800cfc4 */ bne #0x800d01a
  /* 0x0800cfc6 */ movw r2, #0xc00
  /* 0x0800cfca */ movt r2, #0x2000
  /* 0x0800cfce */ ldrh r0, [r2, #0x24]
  /* 0x0800cfd0 */ cmp.w r0, #0x126
  /* 0x0800cfd4 */ bhs #0x800cfd8
  /* 0x0800cfd6 */ b #0x800d01a
  /* 0x0800cfd8 */ movw r2, #0x212
  /* 0x0800cfdc */ cmp r0, r2
  /* 0x0800cfde */ bls #0x800cfe2
  /* 0x0800cfe0 */ b #0x800d01a
  /* 0x0800cfe2 */ movw r2, #0xc00
  /* 0x0800cfe6 */ movt r2, #0x2000
  /* 0x0800cfea */ strh r0, [r2, #0x24]
  /* 0x0800cfec */ movw r0, #0xf800
  /* 0x0800cff0 */ movt r0, #0x800
  /* 0x0800cff4 */ ldrb r1, [r0, #8]
  /* 0x0800cff6 */ cmp r1, #0
  /* 0x0800cff8 */ beq #0x800d01a
  /* 0x0800cffa */ strb.w r1, [r2, #0x26]
  /* 0x0800cffe */ ldrb r1, [r0, #9]
  /* 0x0800d000 */ cmp r1, #1
  /* 0x0800d002 */ blo #0x800d01a
  /* 0x0800d004 */ cmp r1, #4
  /* 0x0800d006 */ bhi #0x800d01a
  /* 0x0800d008 */ strb.w r1, [r2, #0x27]
  /* 0x0800d00c */ ldrb r1, [r0, #0xa]
  /* 0x0800d00e */ cmp r1, #0
  /* 0x0800d010 */ beq #0x800d014
  /* 0x0800d012 */ movs r1, #1
  /* 0x0800d014 */ strb.w r1, [r2, #0x28]
  /* 0x0800d018 */ b #0x800d036
  /* 0x0800d01a */ movw r2, #0xc00
  /* 0x0800d01e */ movt r2, #0x2000
  /* 0x0800d022 */ movw r0, #0x126
  /* 0x0800d026 */ strh r0, [r2, #0x24]
  /* 0x0800d028 */ movs r0, #0x40
  /* 0x0800d02a */ strb.w r0, [r2, #0x26]
  /* 0x0800d02e */ movs r0, #4
  /* 0x0800d030 */ strb.w r0, [r2, #0x27]
  /* 0x0800d034 */ movs r0, #0
  /* 0x0800d036 */ movs r0, #0xa5
  /* 0x0800d038 */ strb.w r0, [r2, #0x29]
  /* 0x0800d03c */ movs r0, #0
  /* 0x0800d03e */ strb.w r0, [r2, #0x2a]
  /* 0x0800d042 */ pop {pc}

@ CRC-32/ISO-HDLC update for r0=bytes, r1=count; returns ~crc.
@ Exact reflected polynomial 0xEDB88320, initial state 0xffffffff.
.global runtime_crc32
runtime_crc32:
  /* 0x0800d044 */ movw r2, #0xffff
  /* 0x0800d048 */ movt r2, #0xffff
  /* 0x0800d04c */ cmp r1, #0
  /* 0x0800d04e */ beq #0x800d07a
  /* 0x0800d050 */ ldrb r3, [r0]
  /* 0x0800d052 */ eor.w r2, r2, r3
  /* 0x0800d056 */ movs.w ip, #8
  /* 0x0800d05a */ lsrs r3, r2, #1
  /* 0x0800d05c */ blo #0x800d06c
  /* 0x0800d05e */ movw r2, #0x8320
  /* 0x0800d062 */ movt r2, #0xedb8
  /* 0x0800d066 */ eor.w r2, r2, r3
  /* 0x0800d06a */ b #0x800d06e
  /* 0x0800d06c */ mov r2, r3
  /* 0x0800d06e */ subs.w ip, ip, #1
  /* 0x0800d072 */ bne #0x800d05a
  /* 0x0800d074 */ adds r0, #1
  /* 0x0800d076 */ subs r1, #1
  /* 0x0800d078 */ b #0x800d04c
  /* 0x0800d07a */ mvns r0, r2
  /* 0x0800d07c */ bx lr

@ Persist runtime configuration to 0x0800F800.
@ Builds a 24-byte record in RAM, CRCs its first 20 bytes, erases/programs its
@ containing 1 KiB flash page, then locks the controller.
.global runtime_config_save
runtime_config_save:
  /* 0x0800d07e */ push {r4, r5, r6, lr}
  /* 0x0800d080 */ movw r4, #0xc00
  /* 0x0800d084 */ movt r4, #0x2000
  /* 0x0800d088 */ add.w r5, r4, #4
  /* 0x0800d08c */ movw r0, #0x5443
  /* 0x0800d090 */ movt r0, #0x3143
  /* 0x0800d094 */ str r0, [r5]
  /* 0x0800d096 */ movs r0, #1
  /* 0x0800d098 */ strh r0, [r5, #4]
  /* 0x0800d09a */ ldrh r0, [r4, #0x24]
  /* 0x0800d09c */ strh r0, [r5, #6]
  /* 0x0800d09e */ ldrb.w r0, [r4, #0x26]
  /* 0x0800d0a2 */ strb r0, [r5, #8]
  /* 0x0800d0a4 */ ldrb.w r0, [r4, #0x27]
  /* 0x0800d0a8 */ strb r0, [r5, #9]
  /* 0x0800d0aa */ ldrb.w r0, [r4, #0x28]
  /* 0x0800d0ae */ strb r0, [r5, #0xa]
  /* 0x0800d0b0 */ movs r0, #0
  /* 0x0800d0b2 */ str r0, [r5, #0xc]
  /* 0x0800d0b4 */ str r0, [r5, #0x10]
  /* 0x0800d0b6 */ mov r0, r5
  /* 0x0800d0b8 */ movs r1, #0x14
  /* 0x0800d0ba */ bl #0x800d044
  /* 0x0800d0be */ str r0, [r5, #0x14]
  /* 0x0800d0c0 */ bl #0x800d0e4
  /* 0x0800d0c4 */ movw r5, #0xf800
  /* 0x0800d0c8 */ movt r5, #0x800
  /* 0x0800d0cc */ add.w r4, r4, #4
  /* 0x0800d0d0 */ movs r6, #0xc
  /* 0x0800d0d2 */ ldrh r0, [r4]
  /* 0x0800d0d4 */ strh r0, [r5]
  /* 0x0800d0d6 */ adds r4, #2
  /* 0x0800d0d8 */ adds r5, #2
  /* 0x0800d0da */ subs r6, #1
  /* 0x0800d0dc */ bne #0x800d0d2
  /* 0x0800d0de */ bl #0x800d142
  /* 0x0800d0e2 */ pop {r4, r5, r6, pc}

@ Direct flash-controller erase/program sequence.
@ Uses MMIO 0x40020400 and its neighbouring registers.  Peripheral block is
@ not named more specifically because the blob alone does not establish it.
.global runtime_flash_program_page
runtime_flash_program_page:
  /* 0x0800d0e4 */ movw r0, #4
  /* 0x0800d0e8 */ movt r0, #0x4002
  /* 0x0800d0ec */ movw r1, #0x123
  /* 0x0800d0f0 */ movt r1, #0x4567
  /* 0x0800d0f4 */ str r1, [r0]
  /* 0x0800d0f6 */ movw r1, #0x89ab
  /* 0x0800d0fa */ movt r1, #0xcdef
  /* 0x0800d0fe */ str r1, [r0]
  /* 0x0800d100 */ adds r0, #0xc
  /* 0x0800d102 */ ldr r1, [r0]
  /* 0x0800d104 */ movw r2, #2
  /* 0x0800d108 */ orr.w r1, r1, r2
  /* 0x0800d10c */ str r1, [r0]
  /* 0x0800d10e */ adds r0, #4
  /* 0x0800d110 */ movw r1, #0xf800
  /* 0x0800d114 */ movt r1, #0x800
  /* 0x0800d118 */ str r1, [r0]
  /* 0x0800d11a */ subs r0, #4
  /* 0x0800d11c */ ldr r1, [r0]
  /* 0x0800d11e */ movw r2, #0x40
  /* 0x0800d122 */ orr.w r1, r1, r2
  /* 0x0800d126 */ str r1, [r0]
  /* 0x0800d128 */ subs r0, #0x10
  /* 0x0800d12a */ ldr r1, [r0]
  /* 0x0800d12c */ tst.w r1, #1
  /* 0x0800d130 */ bne #0x800d128
  /* 0x0800d132 */ adds r0, #0x10
  /* 0x0800d134 */ ldr r1, [r0]
  /* 0x0800d136 */ movw r2, #2
  /* 0x0800d13a */ bic.w r1, r1, r2
  /* 0x0800d13e */ str r1, [r0]
  /* 0x0800d140 */ bx lr

@ Set bit 7 at MMIO 0x40020210, then return (flash-controller lock).
.global runtime_flash_lock
runtime_flash_lock:
  /* 0x0800d142 */ movw r0, #0x10
  /* 0x0800d146 */ movt r0, #0x4002
  /* 0x0800d14a */ ldr r1, [r0]
  /* 0x0800d14c */ movw r2, #0x80
  /* 0x0800d150 */ orr.w r1, r1, r2
  /* 0x0800d154 */ str r1, [r0]
  /* 0x0800d156 */ bx lr
