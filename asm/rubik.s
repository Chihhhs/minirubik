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
# path:       .zero 12    # .byte [MAXD] solution moves 0..8
digits:     .zero 14    # .bytes 14 elements, input string to number

# Move names, 4 bytes each (index m -> offset m*4), order as solver.c:
# R R2 R' B B2 B' D D2 D'
move_names: .byte 82,0,0,0,  82,50,0,0,  82,39,0,0
            .byte 66,0,0,0,  66,50,0,0,  66,39,0,0
            .byte 68,0,0,0,  68,50,0,0,  68,39,0,0

.text
main:
#   TODO 1  parse:  input string -> p rank, o rank; invalid -> exit 2
#        (digits '1'..'7' / '1'..'3', bijection, sum o = 0 mod 3, length 14;
#        p = Lehmer code by Horner, o = base 3 of o[0..5]; no mul/div)

#   M1 step 1: digits[i] = input[i] - '1', i = 0..13
    la   t0, input          # t0 = &input[0]
    la   t1, digits         # t1 = &digits[0]
    li   t3, 14             # t3 = 還剩幾個字元

m1_copy:
    lbu  t2, 0(t0)          # t2 = 讀 t0 指到的 1 個 byte
    addi t2, t2, -49        # t2 = t2 - '1'      (提示: '1' 的 ASCII 是 49)
    sb   t2, 0(t1)          # 把 t2 存到 t1 指到的 1 個 byte
    addi t0, t0, 1          # t0 往下一格
    addi t1, t1, 1          # t1 往下一格
    addi t3, t3, -1         # 剩下的數量 - 1
    bne  t3, x0, m1_copy    # 如果 t3 != 0，回到 m1_copy

#   M1 step 2a: p[0..6] in 0..6 and all different 
    la   t1, digits         # t1 = &digits[0]
    li   t3, 7              # t3 = 還剩幾個
    li   t4, 0              # t4 = 看過的數字（bit 集合）
    li   t6, 7              # t6 = 上限 7（比較用）

m1_perm:
    lbu  t2, 0(t1)            # t2 = p[i]
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
    # la t1, input
    # lbu a0, 14(t1)
    lbu a0, 0(t0) # m1_copy 結束時 t0 = &input[14]（沒人改 t0）
    bne a0, x0, parse_fail
    

#   M1 Step 3 o Rank
    # la t1, digits     # t1 = &digits[0]
    addi t1, t1, -7   # t1 = &digits[14], -7 &digits[7]
    li s1, 0    # o rank
    li t3, 6    # loop o[0..5]

m1_orank:
    lbu  t2, 0(t1)       # t2 = o[i]
    slli t5, s1, 1       # s1 * 2 
    add  s1, t5, s1      # s1 = t5 + s1
    add  s1, s1, t2      # s1 = s1 + o[i]
    addi t1, t1, 1
    addi t3, t3, -1
    bne  t3, x0, m1_orank

#   M1 step 4: p rank (Lehmer)
#   p = 0;
#   for (i = 0; i < 7; i++) {
#      smaller = 0;
#     for (j = i + 1; j < 7; j++)       // 內層：數右邊比 p[i] 小的
#         if (p[j] < p[i]) smaller++;
#     p = p * (7 - i) + smaller;        // 乘數 7, 6, 5, ..., 1
#   }
    # la   t1, digits     # t1 = &p[0]
    li   s0, 0
    li   t3, 7       
    addi t1, t1, -13        # m1_orank 結束時 t1 = &digits[13]
m1_prank:
    lbu  t2, 0(t1)      # t2 = p[i]
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
# |   TODO 3  print path[0..len-1] with move_names, separated by spaces, '\n'  |
# |   TODO 4  T5: re-apply path to (p, o) with pmove/omove; (0, 0) -> exit 0   |
# ------------------------------------------------------------------------------
#     輸入 s0 = p、s1 = o，輸出 a0 = h, 四次查表
#     h = big[p * 9 + otab[o]];
#     if (odist[o] > h) h = odist[o];

#   v2: 表的起始位址只算一次，放進 s5～s9
    la   s5, pmove          # s5 = &pmove[0]
    la   s6, omove          # s6 = &omove[0]
    la   s7, big            # s7 = &big[0]
    la   s8, otab           # s8 = &otab[0]
    # la   s9, odist          # s9 = &odist[0]
    li   s2, 0              # bound 從 0 開始（v3：不再算 h）

#    M2b-2: IDA* outer loop ----
ida_loop:
    li   t0, 11
    blt  t0, s2, t5_fail       # bound > 11 → 不可能，失敗
    jal  ra, dls                # a0 = 1 找到 / 0 沒找到
    bne  a0, x0, ida_found      # 找到 → 跳出
    addi s2, s2, 1              # bound + 1
    j    ida_loop

#  M3: 印出 path[0..s2-1]，格式 "R B' D2 ...\n"
ida_found:
    mv   t1, s4                 # t1 = s4 + k（k = 0；search 剛結束，s4 還是 &P）
    mv   t3, s2
m3_loop:
    beq  t3, x0, m3_done
    lbu  t2, 108(t1)            # t2 = f = CF[k]
    lbu  t5, 120(t1)            # t5 = CT[k]
    slli t4, t2, 1              # t4 = f*2
    add  t2, t4, t2             # t2 = f*3
    add  t2, t2, t5             # t2 = f*3 + CT
    addi t2, t2, -1             # t2 = m
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

#   p = s0; o = s1;                          // 從起點開始
#   for (k = 0; k < len; k++) {
#       m = path[k];
#       f = m / 3;  n = m % 3 + 1;           // 面、轉幾次（不能除！）
#       repeat n 次: (p, o) = turn(f, p, o);
#   }
#   exit(p == 0 && o == 0 ? 0 : 1);

#   M4 / T5: 從起點照 path 轉回去，檢查是不是 solved
    addi s11, s4, 108           # s11 = &CF[0]  （s4 還是 &P，所以要在下一行之前！）
    mv   s4, s0                 # p = 起點 p   （從這行開始 s4 就不是 &P 了）
    mv   s10, s1                # o = 起點 o
    mv   s7, s2                 # s7 = 步數
t5_loop:
    beq  s7, x0, t5_check
    lbu  s9, 0(s11)           # s9 = f = CF[k], offset 前面加過了
    lbu  s8, 12(s11)          # s8 = n = CT[k]（CT = CF + 12 bytes）
t5_turn:
    mv   a1, s9                 # a1 = f
    mv   a2, s4                 # a2 = p
    mv   a3, s10                # a3 = o
    jal  ra, turn               # a0 = np, a1 = no
    mv   s4, a0                 # p = np
    mv   s10, a1                # o = no
    addi s8, s8, -1
    bne  s8, x0, t5_turn        # 還要轉 → 回去
    addi s11, s11, 1            # 下一步
    addi s7, s7, -1
    j    t5_loop
t5_check:
    or   t0, s4, s10            # t0 = p | o
    bne  t0, x0, t5_fail        # 不是 0 → 沒有回到 solved
    li   a0, 0                  # T5 通過 → exit 0
    li   a7, 93
    ecall
t5_fail:
    li   a0, 1                  # T5 失敗 → exit 1
    li   a7, 93
    ecall

parse_fail:
    li      a0, 2               # exit 2 (invalid input)
    li      a7, 93              # ecall 93 = exit
    ecall

#   h_of:  輸入 a1 = p, a2 = o
#       輸出 a0 = h
#       會用到 t0, t1, t2
#   change to inline h

#   M2b-1 轉一次 turn
turn:
    mv   t0, s5
    mv   t1, s6
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

#   v2, search 的陣列共用一個起點 s4
#   P O CP CO F CF CT path 在 .data 裡是緊緊排在一起的。
#   所以只要知道 P 的位址 (s4), 其他 = s4 + 固定的距離

##  Offset table of search state
#   P	    0	half	s4 + g*2 + 0
#   O	    24	half	s4 + g*2 + 24
#   CP	    48	half	s4 + g*2 + 48
#   CO	    72	half	s4 + g*2 + 72
#   F	    96	byte	s4 + g + 96
#   CF	    108	byte	s4 + g + 108
#   CT	    120	byte	s4 + g + 120
#   path	132	byte	s4 + g + 132

    la   s4, P                  # v2: s4 = search 陣列的起點（P 在最前面）
    # P[0] = p, O[0] = o
    sh   s0, 0(s4)              # P[0] = p
    sh   s1, 24(s4)             # O[0] = o
    # F[0] = 255
    li   t1, 255
    sb   t1, 96(s4)             # F[0] = 255
    # level_init(0)
    sb   x0, 108(s4)            # CF[0] = 0
    sb   x0, 120(s4)            # CT[0] = 0
    sh   s0, 48(s4)             # CP[0] = p
    sh   s1, 72(s4)             # CO[0] = o

#   根節點已經是 solved (p == 0 且 o == 0)
    or   t0, s0, s1             # t0 = p | o  (兩個都是 0，結果才是 0)
    beq  t0, x0, dls_found

dls_loop:
    add  t0, s4, s3             # t0 = s4 + g（byte 陣列共用這個位址）
    lbu  t2, 108(t0)            # t2 = CF[g]
    lbu  t3, 120(t0)            # t3 = CT[g]
    lbu  t4,  96(t0)            # t4 = F[g]
    li   t5, 3
    beq  t3, t5, dls_nextface
    beq  t2, t4, dls_nextface
    beq  t2, t5, dls_back
    j    dls_turn

dls_nextface:
    addi t2, t2, 1
    sb   t2, 108(t0)            # CF[g] = t2    （t0 還是 s4 + g）
    sb   x0, 120(t0)            # CT[g] = 0
    slli t5, s3, 1              # t5 = g*2
    add  t6, s4, t5             # t6 = s4 + g*2（half 陣列共用這個位址）
    lhu  a0, 0(t6)              # a0 = P[g]
    sh   a0, 48(t6)             # CP[g] = P[g]
    lhu  a0, 24(t6)             # a0 = O[g]
    sh   a0, 72(t6)             # CO[g] = O[g]
    j    dls_loop

dls_back:
    beq  s3, x0, dls_notfound   # g == 0 → 這個 bound 沒有解
    addi s3, s3, -1             # g--
    j    dls_loop

dls_turn:
    mv   a1, t2                 # a1 = f
    slli t5, s3, 1
    add  t6, s4, t5             # t6 = s4 + g*2
    lhu  a2, 48(t6)             # a2 = CP[g]
    lhu  a3, 72(t6)             # a3 = CO[g]
    jal  ra, turn               # turn 只用 t0～t4 → t6 還在
    sh   a0, 48(t6)             # CP[g] = np
    sh   a1, 72(t6)             # CO[g] = no
    add  t0, s4, s3             # t0 = s4 + g
    lbu  t5, 120(t0)            # t5 = CT[g]
    addi t5, t5, 1
    sb   t5, 120(t0)            # CT[g]++
    or   t5, a0, a1
    beq  t5, x0, dls_found      # 解答在 CF/CT 裡，找到就回傳 1

#   h 剪枝（v3: h_of inline）：h = max(big[np*9 + otab[no]], odist[no])
#   &odist[no] = &otab[no] + 729
    add  t0, s8, a1            # t0 = otab + no
    lbu  t1, 0(t0)             # t1 = otab[no]
    slli t3, a0, 3             # t3 = np * 8
    add  t3, t3, a0            # t3 = np * 9
    add  t3, t3, t1            # t3 = np*9 + otab[no]
    add  t3, s7, t3            # t3 = big + idx
    lbu  t3, 0(t3)             # t3 = big[idx]
#   add  t0, s9, a1             # t0 = odist + no
    lbu  t1, 729(t0)            # t1 = odist[no]
    bge  t3, t1, dls_hmax       # big 比較大 → t3 就是 h
    mv   t3, t1                 # 否則 h = odist[no]
dls_hmax:
    addi t5, s3, 1              # t5 = g + 1
    add  t5, t5, t3             # t5 = g + 1 + h
    blt  s2, t5, dls_loop       # bound < g+1+h → 剪

#   descend 
    add  t0, s4, s3             # t0 = s4 + g
    lbu  t2, 108(t0)            # t2 = f = CF[g]
    slli t5, s3, 1
    add  t6, s4, t5             # t6 = s4 + g*2（這一層）
    lhu  a0, 48(t6)            # a0 = CP[g]
    lhu  a1, 72(t6)            # a1 = CO[g]
    addi s3, s3, 1              # g++
    addi t6, t6, 2              # 下一層的 half 位址 = 往後 2 bytes
    sh   a0, 0(t6)             # P[g] = np
    sh   a1, 24(t6)            # O[g] = no
    sh   a0, 48(t6)            # CP[g] = np
    sh   a1, 72(t6)            # CO[g] = no
    # add  t0, s4, s3            # t0 = s4 + 新的 g
    addi t0, t0, 1             # t0 = s4 + g + 1
    sb   t2, 96(t0)            # F[g] = f
    sb   x0, 108(t0)            # CF[g] = 0
    sb   x0, 120(t0)            # CT[g] = 0
    j    dls_loop

dls_notfound:
    li   a0, 0
    j    dls_ret
dls_found:
    li   a0, 1
dls_ret:
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret
