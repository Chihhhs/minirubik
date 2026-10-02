# Ex7: host bytes per guest byte. Stores N bytes with sw, one word at a time.
# Run: ./measure_mem.sh  (or Ripes --mode cli --src ex7_4m.s -t asm --proc RV32_ISS --iret)
# Expected instructions retired: N/4 * 3 + 6 = 3145734

.equ N, 4194304            # bytes written: 4096 (control), 1M, 2M, 4M

.text
main:
    li   t0, 0x10000000    # start: data segment
    li   t1, N
    add  t1, t0, t1        # end

    li t2, 0xffffffff
loop:
    sw t2, 0(t0)           # store one word (4 bytes)
    addi t0, t0, 4         # advance to the next word
    bltu t0, t1, loop      # unsigned compare: addresses
    li   a7, 10            # exit
    ecall
