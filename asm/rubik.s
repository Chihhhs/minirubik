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
digits:     .zero 14    # .bytes 14 elements, input string to number

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

#   test m1, print rank p,o
#    mv   a0, s0
#    li   a7, 1
#    ecall
#    li a0, 32
#    li a7, 11
#    ecall
#    mv a0, s1
#    li a7, 1 
#    ecall

# ------------------------------------------------------------------------------
# |   TODO 2  ida_solve(p, o) -> length, path[]   (ida.h dls_iter + ida_solve) |
# ------------------------------------------------------------------------------
#     輸入 s0 = p、s1 = o，輸出 a0 = h, 四次查表
#     h = big[p * 9 + otab[o]];
#     if (odist[o] > h) h = odist[o];

    mv a1, s0
    mv a2, s1
    jal ra, h_of

# ---- M2b-2: IDA* outer loop ----
    mv   s2, a0                 # bound = h(root)
ida_loop:
    li   t0, 11
    blt  t0, s2, ida_fail       # bound > 11 → 不可能，失敗
    jal  ra, dls                # a0 = 1 找到 / 0 沒找到
    bne  a0, x0, ida_found      # 找到 → 跳出
    addi s2, s2, 1              # bound + 1
    j    ida_loop

#  M3: 印出 path[0..s2-1]，格式 "R B' D2 ...\n"
ida_found:
    la   t1, path               # t1 = &path[0]
    mv   t3, s2                 # t3 = 還剩幾步要印（長度 = bound）
m3_loop:
    beq  t3, x0, m3_done        # 印完了（solved 長度 0，直接結束）
    lbu  t2, 0(t1)              # t2 = path[k]   (path 是 .byte)
    slli t2, t2, 2              # t2 = m * 4     (左移幾位？)
    la   t4, move_names
    add  t4, t4, t2             # t4 = &move_names[m]
    lbu  a0, 0(t4)              # 第 1 個字元（R / B / D）
    li   a7, 11
    ecall
    lbu  a0, 1(t4)              # 第 2 個字元（'2'、'\'' 或 0）
    beq  a0, x0, m3_space       # 是 0 → 沒有第 2 個字元
    ecall                       # a7 還是 11
m3_space:                       # (Ripes 的 ecall 4 會連 '\0' 一起印出，所以改用 ecall 11)
    li   a0, 32
    li   a7, 11
    ecall                       # 印空格
    addi t1, t1, 1              # 下一步
    addi t3, t3, -1             # 剩下的 - 1
    j    m3_loop
m3_done:
    li   a0, 10                 # '\n'
    li   a7, 11
    ecall
    j    ida_done

ida_fail:
    li   a0, 1                  # 不應該發生 → exit 1
    li   a7, 93
    ecall
ida_done:

    li a0, 1 
    li a7, 93 
    ecall

    # TODO 3  print path[0..len-1] with move_names, separated by spaces, '\n'
    # TODO 4  T5: re-apply path to (p, o) with pmove/omove; (0, 0) -> exit 0
    li   a0, 1
    li   a7, 93
    ecall

parse_fail:
    li      a0, 2               # exit 2 (invalid input)
    li      a7, 93              # ecall 93 = exit
    ecall

#   h_of:  輸入 a1 = p, a2 = o
#       輸出 a0 = h
#       會用到 t0, t1, t2
h_of:
#   M2a-1: 讀出 otab[o]
    la   t0, otab          # t0 = otab 的起始位址
    add  t0, t0, a2        # t0 = otab + o, o in a2
    lbu  t1, 0(t0)         # t1 = 讀 1 個 byte

    # M2a-2: a0 = big[p*9 + otab[o]]
    slli t2, a1, 3          # t2 = p << 3, p in a1
    add  t2, t2, a1         # t2 = p*8 + p  = p*9
    add  t2, t2, t1         # t2 = p*9 + otab[o], otab[o] in t1
    
    la   t0, big            # t0 = big 的起始位址
    add  t0, t0, t2         # t0 = big + idx
    lbu  a0, 0(t0)          # a0 = big[idx]

#   M2a-3：和 odist[o] 取 max , finish h
#   if (odist[o] > h) h = odist[o];     // h 在 a0
    la   t0, odist          # odist 的起始位址
    add  t0, t0, a2         # + o, o in a2
    lbu  t1, 0(t0)          # t1 = odist[o]
    bge  a0, t1, h_done     # 如果 a0 >= t1，a0 已經是 max，跳過
    mv   a0, t1             # 否則 a0 = odist[o]
h_done:
    ret


#   M2b-1 轉一次 turn
turn:
    la   t0, pmove
    la   t1, omove
    li   t2, 10080              # pmove 一面的 bytes
    li   t3, 1458               # omove 一面的 bytes
turn_face:
    beq  a1, x0, turn_go        # f 數到 0 就停
    add  t0, t0, t2             # pmove 跳到下一面
    add  t1, t1, t3             # omove 跳到下一面
    addi a1, a1, -1             # f - 1
    j    turn_face
turn_go:
    slli t4, a2, 1              # t4 = p * 2
    add  t0, t0, t4             # t0 = &pmove[f][p]
    lhu   a0, 0(t0)             # a0 = pmove[f][p]   (2 bytes)
    slli t4, a3, 1              # t4 = o * 2
    add  t1, t1, t4             # t1 = &omove[f][o]
    lhu  a1, 0(t1)              # a1 = omove[f][o]   (2 bytes)
    ret

dls:
    addi sp, sp, -4
    sw   ra, 0(sp)              # 保存 ra
    li   s3, 0                  # g = 0

    # P[0] = p, O[0] = o        (.half 陣列 → 用 sh)
    la   t0, P
    sh   s0, 0(t0)              # P[0] = s0
    la   t0, O
    sh   s1, 0(t0)              # O[0] = s1
    # F[0] = 255  (根節點沒有「上一步的面」，用一個不會等於 0..3 的值)
    la   t0, F
    li   t1, 255
    sb   t1, 0(t0)              # F[0] = 255   (.byte → sb)
    # level_init(0): CF[0] = 0, CT[0] = 0, CP[0] = p, CO[0] = o
    la   t0, CF
    sb   x0, 0(t0)              # CF[0] = 0 
    la   t0, CT
    sb   x0, 0(t0)              # CT[0] = 0
    la   t0, CP
    sh   s0, 0(t0)              # CP[0] = p
    la   t0, CO
    sh   s1, 0(t0)              # CO[0] = o

    # 根節點已經是 solved？ (p == 0 且 o == 0)
    or   t0, s0, s1             # t0 = p | o  (兩個都是 0，結果才是 0)
    beq  t0, x0, dls_found
dls_loop:
    la   t0, CF
    add  t0, t0, s3             # t0 = &CF[g]
    lbu  t2, 0(t0)              # t2 = CF[g]
    la   t1, CT
    add  t1, t1, s3             # t1 = &CT[g]
    lbu  t3, 0(t1)              # t3 = CT[g]
    la   t4, F
    add  t4, t4, s3
    lbu  t4, 0(t4)              # t4 = F[g]
    li   t5, 3
    beq  t3, t5, dls_nextface   # 這一面轉了 3 次 → 換面
    beq  t2, t4, dls_nextface   # CF[g] == F[g]（同面剪枝）→ 換面
    beq  t2, t5, dls_back       # CF[g] == 3 → 三面都試完
    j dls_turn

dls_nextface:                   # CF++、CT = 0、CP/CO 重設成 P/O
    addi t2, t2, 1
    sb   t2, 0(t0)              # CF[g] = t2
    sb   x0, 0(t1)              # CT[g] = 0
    slli t5, s3, 1              # t5 = g*2
    la   t6, P
    add  t6, t6, t5
    lhu  a0, 0(t6)              # a0 = P[g]
    la   t6, CP
    add  t6, t6, t5
    sh   a0, 0(t6)              # CP[g] = P[g]
    la   t6, O
    add  t6, t6, t5
    lhu  a0, 0(t6)              # a0 = O[g]
    la   t6, CO
    add  t6, t6, t5
    sh   a0, 0(t6)              # CO[g] = O[g]
    j dls_loop

dls_back:
    beq  s3, x0, dls_notfound   # g == 0 → 這個 bound 沒有解
    addi s3, s3, -1             # g--
    j    dls_loop

dls_turn:                       # 從 CP/CO 再轉一次（連轉）
    mv   a1, t2                 # a1 = f = CF[g]
    slli t5, s3, 1
    la   t6, CP
    add  t6, t6, t5
    lhu  a2, 0(t6)              # a2 = CP[g]
    la   t6, CO
    add  t6, t6, t5
    lhu  a3, 0(t6)              # a3 = CO[g]
    jal  ra, turn               # a0 = np, a1 = no   (t0~t4 被弄亂了!)
    slli t5, s3, 1
    la   t6, CP
    add  t6, t6, t5
    sh   a0, 0(t6)              # CP[g] = np
    la   t6, CO
    add  t6, t6, t5
    sh   a1, 0(t6)              # CO[g] = no
    la   t6, CT
    add  t6, t6, s3
    lbu  t5, 0(t6)
    addi t5, t5, 1
    sb   t5, 0(t6)              # CT[g]++
    or   t5, a0, a1
    beq  t5, x0, dls_hit      # 子節點是 solved → 找到

# ---- h pruning: g + 1 + h(np, no) > bound → don't descend ----
    mv   a2, a1                 # a2 = no   (move a1 first, or it gets overwritten)
    mv   a1, a0                 # a1 = np
    jal  ra, h_of               # a0 = h      (t0~t2 get clobbered)
    addi t5, s3, 1              # t5 = g + 1
    add  t5, t5, a0             # t5 = g + 1 + h
    blt  s2, t5, dls_loop       # bound < g+1+h → prune, back to loop top (hint: blt)

# ---- descend ----
    jal  ra, dls_record         # path[g] = move   (t2 = f afterwards)
    slli t5, s3, 1
    la   t6, CP
    add  t6, t6, t5
    lhu a0, 0(t6)              # a0 = np = CP[g]
    la   t6, CO
    add  t6, t6, t5
    lhu  a1, 0(t6)              # a1 = no = CO[g]
    addi s3, s3, 1              # g++
    slli t5, s3, 1              # t5 = new g * 2
    la   t6, P
    add  t6, t6, t5
    sh   a0, 0(t6)              # P[g] = np
    la   t6, O
    add  t6, t6, t5
    sh   a1, 0(t6)              # O[g] = no
    la   t6, CP
    add  t6, t6, t5
    sh   a0, 0(t6)              # CP[g] = np
    la   t6, CO
    add  t6, t6, t5
    sh   a1, 0(t6)              # CO[g] = no
    la   t6, F
    add  t6, t6, s3
    sb   t2, 0(t6)              # F[g] = f (the face we just turned)
    la   t6, CF
    add  t6, t6, s3
    sb   x0, 0(t6)              # CF[g] = 0
    la   t6, CT
    add  t6, t6, s3
    sb   x0, 0(t6)              # CT[g] = 0
    j    dls_loop

dls_hit:                        # child is solved: record the last move, then found
    jal  ra, dls_record
    j    dls_found

dls_notfound:
    li   a0, 0
    j    dls_ret
dls_found:
    li   a0, 1
dls_ret:
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

# path[g] = CF[g]*3 + CT[g] - 1；output t2 = CF[g] (the face)
dls_record:
    la   t0, CF
    add  t0, t0, s3
    lbu  t2, 0(t0)              # t2 = f
    la   t1, CT
    add  t1, t1, s3
    lbu  t3, 0(t1)              # t3 = number of turns
    slli t4, t2, 1              # t4 = f << 1
    add  t4, t4, t2             # t4 = f * 3
    add  t4, t4, t3             # + turns
    addi t4, t4, -1             # - 1
    la   t6, path
    add  t6, t6, s3
    sb   t4, 0(t6)              # path[g] = move
    ret