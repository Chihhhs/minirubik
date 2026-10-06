# Minimal startup for Ripes: set sp, call main, exit with main's return value.
# Ripes ecall: a7 = 93 -> exit with code a0 (shown as "Program exited with code").
    .section .text.start
    .globl _start
_start:
    .option push
    .option norelax
    la   gp, __global_pointer$     # linker may relax small-data accesses to gp
    .option pop
    li   sp, 0x7ffffff0
    call main
    li   a7, 93
    ecall
