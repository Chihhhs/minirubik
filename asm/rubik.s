# minirubik on RV32I: optimal solver (IDA*), Stage 4.
# Search = explore/stage3/ida.h v1 (same tables, same move order).
# Ripes has no .include / .if / .space: build.sh appends tables.s,
# substitutes the input line and strips the renderer for CLI builds. Run: ./build.sh  (all tests)
#
# Contract: print the solution on one line, then exit (ecall 93) with
#   0 = solved and re-checked (T5), 1 = check failed, 2 = invalid input.

.equ RENDER, 0          # build.sh sets it: 0 for CLI, 1 for "full" (GUI).
                        # Renderer code goes between "# RENDER-BEGIN" and
                        # "# RENDER-END" lines (deleted in CLI builds).
.equ MAXD, 12           # 11 moves + the start state

.data
input:      .string "21345671111111"   # replaced by build.sh

# Per-depth search state (ida.h names). .half arrays: index g -> offset g*2.
.align 1
P:          .zero 24    # .half [MAXD] parent p at depth g
O:          .zero 24    # .half [MAXD] parent o
CP:         .zero 24    # .half [MAXD] p after CT turns (chained)
CO:         .zero 24    # .half [MAXD] o after CT turns
F:          .zero 12    # .byte [MAXD] face of the move into depth g (root: 0xFF)
CF:         .zero 12    # .byte [MAXD] face being tried (3 = done)
CT:         .zero 12    # .byte [MAXD] turns done on that face (0..3)
path:       .zero 12    # .byte [MAXD] solution moves 0..8
digits:     .zero 14    # input string to number (bytes).

# Move names, 4 bytes each (index m -> offset m*4), order as solver.c:
# R R2 R' B B2 B' D D2 D'
move_names: .byte 82,0,0,0,  82,50,0,0,  82,39,0,0
            .byte 66,0,0,0,  66,50,0,0,  66,39,0,0
            .byte 68,0,0,0,  68,50,0,0,  68,39,0,0

.text
main:
    # TODO 1  parse:  input string -> p rank, o rank; invalid -> exit 2
    #         (digits '1'..'7' / '1'..'3', bijection, sum o = 0 mod 3, length 14;
    #          p = Lehmer code by Horner, o = base 3 of o[0..5]; no mul/div)

# M1 step 1: digits[i] = input[i] - '1', i = 0..13
    la   t0, input          # t0 = &input[0]
    la   t1, digits         # t1 = &digits[0]
    li   t3, 14             # t3 = 還剩幾個字元

m1_copy:
    lbu t2, 0(t0)            # t2 = 讀 t0 指到的 1 個 byte
    addi t2, t2, -49        # t2 = t2 - '1'      (提示: '1' 的 ASCII 是 49)
    sb t2, 0(t1)            # 把 t2 存到 t1 指到的 1 個 byte
    addi t0, t0, 1          # t0 往下一格
    addi t1, t1, 1          # t1 往下一格
    addi t3, t3, -1         # 剩下的數量 - 1
    bne t3, x0, m1_copy    # 如果 t3 != 0，回到 m1_copy

# M1 step 2a: p[0..6] in 0..6 and all different 
    la   t1, digits         # t1 = &digits[0]
    li   t3, 7              # t3 = 還剩幾個
    li   t4, 0              # t4 = 看過的數字（bit 集合）
    li   t6, 7              # t6 = 上限 7（比較用）

m1_perm:
    lbu  t2, 0(t1)          # t2 = p[i]
    bgeu  t2, t6,  parse_fail # p[i] >= 7（無號）→ 不合法
    li   t5, 1
    sll t5, t5, t2         # t5 = 1 << p[i]
    and a0, t4, t5         # a0 = t4 & t5
    bne a0, x0, parse_fail # a0 != 0 → 重複 → 不合法
    or  t4, t4, t5         # t4 = t4 | t5
    addi t1, t1, 1
    addi t3, t3, -1
    bne  t3, x0, m1_perm

# M1 step 2b: o[0..6] in 0..2, t4 = sum of o
    li t3, 7 
    li t4, 0               # o sum
    li t6, 3               # upbound limit

m1_ori:
    lbu  t2, 0(t1)
    bgeu t2, t6, parse_fail # o[i] >= 3
    add  t4, t4, t2         # sum o += o[i]
    addi t1, t1, 1
    addi t3, t3, -1
    bne  t3, x0, m1_ori

m1_mod3:                       # mod 3 
    blt t4, t6, m1_mod3_done 
    addi t4, t4, -3
    j m1_mod3

m1_mod3_done:
    bne t4, x0, parse_fail

len_check:
    la t1, input
    lbu a0, 14(t1)
    bne a0, x0, parse_fail

# M1 Step 3 o Rank
    la t1, digits     # t1 = &digits[0]
    addi t1, t1, 7   # t1 = &digits[7]
    li s1, 0    # o rank
    li t3, 6    # loop o[0..5]

m1_orank:
    lbu   t2, 0(t1)       # t2 = o[i]
    slli t5, s1, 1       # s1 * 2 
    add  s1, t5, s1      # s1 = t5 + s1
    add  s1, s1, t2      # s1 = s1 + o[i]
    addi t1, t1, 1
    addi t3, t3, -1
    bne  t3, x0, m1_orank

#  M1 step 4: p rank (Lehmer)
#p = 0;
#for (i = 0; i < 7; i++) {
#    smaller = 0;
#    for (j = i + 1; j < 7; j++)       // 內層：數右邊比 p[i] 小的
#        if (p[j] < p[i]) smaller++;
#    p = p * (7 - i) + smaller;        // 乘數 7, 6, 5, ..., 1
#}
    la   t1, digits     # t1 = &p[0]
    li   s0, 0
    li   t3, 7       
m1_prank:
    lbu  t2, 0(t1)     # t2 = p[i]
    li   a0, 0          # smaller = 0
    addi t4, t1, 1      # t4 = t1 + 1   (&p[i+1])
    addi t5, t3, -1     # t5 = t3 - 1   (右邊 j)

m1_inner:
    beq  t5, x0, m1_inner_done      # j done
    lbu a1, 0(t4)                   # a1 = p[j]
    bgeu a1, t2, m1_not_smaller     # p[j] >= p[i] → 不算
    addi a0, a0, 1                  # smaller++

m1_not_smaller:
    addi t4, t4, 1         # t4 往下一格
    addi t5, t5, -1        # t5 - 1
    j    m1_inner

m1_inner_done:
    mv   a1, s0                 # a1 = s0 的備份
    addi t5, t3, -1             # t5 = t3 - 1
    
m1_mul:
    beq  t5, x0, m1_mul_done
    add  s0, s0, a1             # s0 = s0 + a1
    addi t5, t5, -1             # t5 - 1
    j    m1_mul

m1_mul_done:
    add s0, s0, a0              # s0 = s0 + smaller
    addi t1, t1, 1
    addi t3, t3, -1
    bne  t3, x0, m1_prank

# test
    mv   a0, s0
    li   a7, 1
    ecall
    li a0, 32
    li a7, 11
    ecall
    mv a0, s1
    li a7, 1 
    ecall




    # TODO 2  ida_solve(p, o) -> length, path[]   (ida.h dls_iter + ida_solve)
    # TODO 3  print path[0..len-1] with move_names, separated by spaces, '\n'
    # TODO 4  T5: re-apply path to (p, o) with pmove/omove; (0, 0) -> exit 0
    li   a0, 1
    li   a7, 93
    ecall

parse_fail:
    li      a0, 2               # exit 2 (invalid input)
    li      a7, 93              # ecall 93 = exit
    ecall
