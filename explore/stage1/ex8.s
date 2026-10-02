# Ex8: retired instructions per second. A register-only loop, 2 instructions per iteration.
# Run: ./measure_ips.sh
# Expected instructions retired: COUNT * 2 + 4

.equ COUNT, 5000000        # RV32_ISS: 5,000,000; RV32_5S: 100,000

.text
main:
    li   t0, COUNT
loop:
    addi t0, t0, -1        # t0 = t0 - 1
    bne  t0, x0, loop      # t0 != 0 -> next iteration

    li   a7, 10            # exit
    ecall
