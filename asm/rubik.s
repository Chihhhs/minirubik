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
# digits:     .zero 14    # .bytes 14 elements, input string to number

# Move names, 4 bytes each (index m -> offset m*4), order as solver.c:
# R R2 R' B B2 B' D D2 D'
move_names: .byte 82,0,0,0,  82,50,0,0,  82,39,0,0
            .byte 66,0,0,0,  66,50,0,0,  66,39,0,0
            .byte 68,0,0,0,  68,50,0,0,  68,39,0,0

# RENDER-BEGIN
# ---- M6 renderer 的資料（只在 GUI build 出現）----
# search 只有 rank，畫圖要知道「每個位置是哪個角塊、轉了幾次」→ renderer 自己存一份陣列。
# 第 e 格（e = 0..6）= solver 的第 e 個位置（也就是位置 e+1）；e = 7 = 固定不動的位置 0（前-上-左）。
# 每個位置的 3 張貼紙叫 slot 0、1、2：slot 0 = U/D 那張，接著從角的外面看「順時針」。
# 規則（render_model.py 推導並用 2000 個隨機狀態驗證）：
#   位置 e 上是角塊 c、方位 o 時，slot k 顯示「角塊 c 的第 (k + o) mod 3 張貼紙」。
.align 2
rp:         .byte 0,1,2,3,4,5,6,7   # rp[e] = 位置 e 上的角塊（第 7 格固定 = 7）
ro:         .byte 0,0,0,0,0,0,0,0   # ro[e] = 它的方位 0..2        （位址 = rp + 8）
rtp:        .zero 8                 # 轉之前 rp 的備份               （rp + 16）
rto:        .zero 8                 # 轉之前 ro 的備份               （rp + 24）
rsrc:       .byte 1,4,2,0,3,5,6,7   # = solver.c 的 source[f][i]；一面一列、每列 8 個（R、B、D）
            .byte 0,1,2,4,5,6,3,7
            .byte 0,2,5,3,1,4,6,7
rtw:        .byte 1,2,0,2,1,0,0,0   # = solver.c 的 twist[f][i]
            .byte 0,0,0,1,2,1,2,0
            .byte 0,0,0,0,0,0,0,0
# 展開圖 35 x 20：每面 8 x 6 px，面之間 1 px 黑線；排法  . U . .  /  L F R B  /  . D . .
# rxy[e][k] = 位置 e 的 slot k 在 LED 上的左上角 (x, y)，每格 2 bytes；每個 facelet 4 x 3 px。
rxy:        .byte 13,3,  18,7,  13,7    # e=0 (前上右): U R F
            .byte 13,14, 13,10, 18,10   # e=1 (前下右): D F R
            .byte 9,14,  4,10,  9,10    # e=2 (前下左): D L F
            .byte 13,0,  27,7,  22,7    # e=3 (後上右): U B R
            .byte 13,17, 22,10, 27,10   # e=4 (後下右): D R B
            .byte 9,17,  31,10, 0,10    # e=5 (後下左): D B L
            .byte 9,0,   0,7,   31,7    # e=6 (後上左): U L B
            .byte 9,3,   9,7,   4,7     # e=7 (前上左，固定): U F L
# rcol[c][j] = 角塊 c 第 j 張貼紙的顏色（= solved 時它在自己位置上的 3 格顏色），每個 1 word。
# U 白、F 綠、R 紅、B 藍、L 橘、D 黃。
.align 2
rcol:       .word 0xFFFFFF, 0xFF0000, 0x00C000   # 角塊 0: U R F
            .word 0xFFFF00, 0x00C000, 0xFF0000   # 角塊 1: D F R
            .word 0xFFFF00, 0xFF8000, 0x00C000   # 角塊 2: D L F
            .word 0xFFFFFF, 0x0000FF, 0xFF0000   # 角塊 3: U B R
            .word 0xFFFF00, 0xFF0000, 0x0000FF   # 角塊 4: D R B
            .word 0xFFFF00, 0x0000FF, 0xFF8000   # 角塊 5: D B L
            .word 0xFFFFFF, 0xFF8000, 0x0000FF   # 角塊 6: U L B
            .word 0xFFFFFF, 0x00C000, 0xFF8000   # 角塊 7（固定）: U F L
# RENDER-END

.text
main:
#   TODO 1  parse:  input string -> p rank, o rank; invalid -> exit 2
#        (digits '1'..'7' / '1'..'3', bijection, sum o = 0 mod 3, length 14;
#        p = Lehmer code by Horner, o = base 3 of o[0..5]; no mul/div)

#   M1 step 1: input[i] = input[i] - '1', i = 0..13
    # la   t0, input          # t0 = &input[0]
    # la   t1, digits         # t1 = &digits[0]
    la   t1, input            # t1 = &input[0]
    # li   t3, 14             # t3 = 還剩幾個字元
    li   t3, 7              # t3 = 還剩幾個
    li   t4, 0              # t4 = 看過的數字（bit 集合）
    li   t6, 7              # t6 = 上限 7

m1_perm:
    lbu  t2, 0(t1)            # t2 = p[i]
    addi t2, t2, -49          # char 2 num
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
    addi t2, t2, -49       # char 2 num
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
    lbu a0, 0(t1)           # t1 &input[14]
    bne a0, x0, parse_fail
    

#   M1 Step 3 o Rank
    addi t1, t1, -7   # t1 = &digits[14], -7 &digits[7]
    li s1, 0    # o rank
    li t3, 6    # loop o[0..5]

m1_orank:
    lbu  t2, 0(t1)       # t2 = o[i]
    addi t2, t2, -49     # char 2 num
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
# RENDER-BEGIN
    jal  ra, r_init             # M6：輸入合法 → 先畫出起始狀態（search 還沒開始）
# RENDER-END

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
    blt  t0, s2, t5_fail      # bound > 11 → 不可能，失敗
    j    dls                  # v6: founded → ida_found, notfound → dls_notfound

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
# RENDER-BEGIN
#   M6 hook：剛印完第 k 步 → 把這一步套到 rp/ro 上、重畫。
#   M3 迴圈還要用 t1（指到第 k 步）和 t3（剩幾步），renderer 會弄亂它們 → 先存到 stack。
    addi sp, sp, -8            # 挪出 2 個 word 的空間（往低位址長，所以是負的）
    sw   t1, 0(sp)
    sw   t3, 4(sp)
    lbu  a0, 108(t1)            # a0 = 面 f = CF[k]   （t1 = s4 + k，CF 的 offset？）
    lbu  a1, 120(t1)            # a1 = 次數 n = CT[k]  （CT 的 offset）
    jal  ra, r_step             # 轉 n 次、重畫
    lw   t1, 0(sp)              # 讀回來
    lw   t3, 4(sp)
    addi sp, sp, 8              # 還原 sp
# RENDER-END
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
# t5_check:
#     or   t0, s4, s10            # t0 = p | o
#     bne  t0, x0, t5_fail        # 不是 0 → 沒有回到 solved
#     li   a0, 0                  # T5 通過 → exit 0
#     li   a7, 93
#     ecall
# t5_fail:
#     li   a0, 1                  # T5 失敗 → exit 1
#     li   a7, 93
#     ecall

# parse_fail:
#     li      a0, 2               # exit 2 (invalid input)
#     li      a7, 93              # ecall 93 = exit
#     ecall

t5_check:
    or   t0, s4, s10            # t0 = p | o
    sltu a0, x0, t0             # a0 = (t0 != 0) ? 1 : 0, fail:pass
    j    exit
parse_fail:
    li   a0, 2                  # exit 2（輸入不合法）
    j    exit
t5_fail:
    li   a0, 1                  # exit 1（bound > 11，不該發生）
exit:
    li   a7, 93                 # 共用的 exit：a0 = exit code
    ecall

# RENDER-BEGIN
# ==== M6 renderer（只在 GUI build；只用 stack 存東西，不動任何 s 暫存器：T5 還要用 s0/s1/s2/s4）====
#   r_init：把（已經檢查過的）input 字串轉成 rp/ro，然後畫一次。
#   input[0..6] = p 的 7 個字元，input[7..13] = o 的 7 個字元。

r_init:
    la   t4, input              # t4 = &input[e]
    la   t5, rp                 # t5 = &rp[e]
    li   t6, 7                  # 7 個位置（第 7 格固定，不用讀）
r_init_loop:
    lbu  t0, 0(t4)              # p
    addi t0, t0, -49            # char2num
    sb   t0, 0(t5)              # rp[e]
    lbu  t0, 7(t4)            # o , p + 7
    addi t0, t0, -49
    sb   t0, 8(t5)            # ro[e] = o digits
    addi t4, t4, 1
    addi t5, t5, 1
    addi t6, t6, -1
    bne  t6, x0, r_init_loop
    j    r_draw                 # 直接跳過去，r_draw 的 ret 會回到呼叫 r_init 的地方

# r_step：a0 = 面 f、a1 = 轉幾次 n（1..3）；轉 n 次，再重畫。
#   r_turn 會弄亂 a0/a1，所以把 ra、f、n 都存在 stack。
r_step:
    addi sp, sp, -12            # 3 個 word
    sw   ra, 0(sp)
    sw   a0, 4(sp)              # f
    sw   a1, 8(sp)              # n
r_step_turn:
    lw   a0, 4(sp)            # 每次都重新讀 f
    jal  ra, r_turn             # 轉一次
    lw   a1, 8(sp)
    addi a1, a1, -1            # 剩下的次數 - 1
    sw   a1, 8(sp)
    bne  a1, x0, r_step_turn    # 還沒轉完 → 再轉
    lw   ra, 0(sp)
    addi sp, sp, 12
    j    r_draw                 # 尾呼叫：畫完直接回到 M3

# r_turn：a0 = 面 f；把 rp/ro 轉一次 90°，跟 solver.c 的 quarter_turn 一樣：
#   p[i] = 舊p[src[f][i]]，o[i] = (舊o[src[f][i]] + twist[f][i]) mod 3
#   要先備份：不然 p[0] 改掉之後，後面要讀「舊的 p[0]」就讀錯了。
r_turn:
    la   t4, rp                 # t4 = &rp；rp/ro 共 16 bytes = 4 個 word
    lw   t5, 0(t4)              # 一次搬 4 bytes：rp[0..3] → rtp[0..3]
    sw   t5, 16(t4)            # rtp 在 rp 後面 16
    lw   t5, 4(t4)              # rp[4..7]
    sw   t5, 20(t4)
    lw   t5, 8(t4)              # ro[0..3]
    sw   t5, 24(t4)            # rto 在 rp 後面 16 + 8 
    lw   t5, 12(t4)             # ro[4..7]
    sw   t5, 28(t4)
    slli t5, a0, 3            # 第 f 列的起點 = f * 8
    la   t6, rsrc
    add  t6, t6, t5             # t6 = &rsrc[f][0]
    la   a1, rtw
    add  a1, a1, t5             # a1 = &rtw[f][0]
    li   a2, 0                  # i = 0
r_turn_i:
    add  a3, t6, a2
    lbu  a3, 0(a3)              # s = src[f][i]
    add  a3, t4, a3             # a3 = &rp[s]
    lbu  a4, 16(a3)            # a4 = 舊 p[s] = rtp[s]
    lbu  a5, 24(a3)            # a5 = 舊 o[s] = rto[s]
    add  a3, a1, a2
    lbu  a3, 0(a3)              # a3 = twist[f][i]
    add  a5, a5, a3             # o + twist（最大 2 + 2 = 4）
    li   a3, 3
    blt  a5, a3, r_turn_ok      # < 3
    addi a5, a5, -3            # mod 3
r_turn_ok:
    add  a3, t4, a2             # a3 = &rp[i]
    sb   a4, 0(a3)              # rp[i] = 舊 p[s]
    sb   a5, 8(a3)              # ro[i] = 新的方位
    addi a2, a2, 1
    li   a3, 7                # 只做第 0..6 格（第 7 格是固定的角，不轉）
    bne  a2, a3, r_turn_i
    ret

# r_draw：照 rp/ro 畫出 24 個 facelet（8 個位置 × 3 個 slot）。
#   迴圈變數放在 a3（e）、a6（k），因為 draw_block 只用 a0..a2、t0..t2，不會弄亂它們。
r_draw:
    addi sp, sp, -4
    sw   ra, 0(sp)              # 要呼叫 draw_block → 先存 ra
    li   a3, 0                  # e = 0
r_draw_e:
    la   t4, rp
    add  t4, t4, a3
    lbu  a4, 0(t4)              # c = rp[e]（哪個角塊）
    lbu  a5, 8(t4)            # o = ro[e]（轉了幾次）
    li   a6, 0                  # k = 0
r_draw_k:
    add  t4, a6, a5             # j = k + o：slot k 顯示角塊的第 j 張貼紙
    li   t5, 3
    blt  t4, t5, r_draw_j
    addi t4, t4, -3             # j mod 3
r_draw_j:
    # 顏色 = rcol[c][j]，在 rcol + (c*3 + j) * 4
    slli t5, a4, 1
    add  t5, t5, a4            # t5 = c * 3
    add  t5, t5, t4             # + j
    slli t5, t5, 2            # × 4（rcol 每個是 1 word）
    la   t6, rcol
    add  t5, t5, t6
    lw   a2, 0(t5)              # a2 = 顏色
    # 位置 = rxy[e][k]，在 rxy + (e*3 + k) * 2
    slli t5, a3, 1
    add  t5, t5, a3             # e * 3
    add  t5, t5, a6            # + k
    slli t5, t5, 1            # × 2（每格是 x、y 兩個 byte）
    la   t6, rxy
    add  t5, t5, t6
    lbu  a0, 0(t5)              # a0 = x
    lbu  a1, 1(t5)            # a1 = y（x 的下一個 byte）
    jal  ra, draw_block         # 畫這一格
    addi a6, a6, 1              # 下一個 slot
    li   t5, 3
    bne  a6, t5, r_draw_k
    addi a3, a3, 1              # 下一個位置
    li   t5, 8               
    bne  a3, t5, r_draw_e
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

# draw_block：a0 = x、a1 = y（左上角）、a2 = 顏色；畫 4 寬 × 3 高。
#   LED (x, y) 的位址 = LED_MATRIX_0_BASE + (y*35 + x) * 4（row-major，M6-1 確認過）。只用 t0..t2。
draw_block:
    slli t0, a1, 5            # y * 32
    slli t1, a1, 1            # y * 2
    add  t0, t0, t1
    add  t0, t0, a1            # + y → y * 35
    add  t0, t0, a0            # + x → 第幾顆 LED
    slli t0, t0, 2              # × 4 bytes
    li   t1, LED_MATRIX_0_BASE
    add  t0, t0, t1             # t0 = &LED(x, y)
    li   t2, 3                  # 畫 3 列
db_row:
    sw   a2, 0(t0)              # 這一列的 4 顆
    sw   a2, 4(t0)
    sw   a2, 8(t0)
    sw   a2, 12(t0)
    addi t0, t0, 140            # 下一列 = 往後 35 顆 × 4 bytes
    addi t2, t2, -1
    bne  t2, x0, db_row
    ret
# RENDER-END

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
    beq  t0, x0, ida_found

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
    beq  t5, x0, dls_found_child      # 解答在 CF/CT 裡，找到就回傳 1

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
    addi t0, t0, 1              # t0 = s4 + g + 1
    sb   t2, 96(t0)             # F[g] = f
    sb   x0, 108(t0)            # CF[g] = 0
    sb   x0, 120(t0)            # CT[g] = 0
    j    dls_loop

dls_notfound:           # bound + 1, looping
    addi s2, s2, 1      # s2 = bound + 1
    j    ida_loop       # retry check bound <= 11
dls_found_child:
    addi s2, s3, 1                 # 長度 = g + 1
    j    ida_found
