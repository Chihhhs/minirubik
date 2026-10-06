/* Ripes ecall helpers for the RV32I build (no libc). */
#ifndef RV_H
#define RV_H

static inline void rv_ecall(int a7, int a0)
{
    register int r0 __asm__("a0") = a0;
    register int r7 __asm__("a7") = a7;
    __asm__ volatile("ecall" : : "r"(r0), "r"(r7) : "memory");
}

static inline void print_int(int v) { rv_ecall(1, v); }
static inline void print_str(const char *s) { rv_ecall(4, (int) s); }
static inline void print_char(char c) { rv_ecall(11, c); }

#endif
