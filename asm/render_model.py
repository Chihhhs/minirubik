#!/usr/bin/env python3
"""M6 (AI-written): sticker model of the 2x2x2 cube used to derive the LED renderer tables.

1. Builds a physical model: 8 positions with (x, y, z) in {-1, 1}^3, 3 stickers each, and
   R / B / D as clockwise quarter turns of the x=+1 / z=-1 / y=-1 layers.
2. Checks that this model reproduces solver.c's source[][] and twist[][] tables, and finds
   the orientation convention: list each position's stickers as (U/D sticker, then clockwise
   seen from outside); a cubie with twist o shows its sticker (k + o) mod 3 in slot k.
3. Verifies that rule on random states, then prints the rxy / rcol tables used in rubik.s
   and a text picture of the solved net and of the net after R.
Run: python3 render_model.py
"""
import random

# Position i -> corner coordinates (x right, y up, z toward the viewer). solver index = i - 1.
POS = [(-1, 1, 1), (1, 1, 1), (1, -1, 1), (-1, -1, 1),
       (1, 1, -1), (1, -1, -1), (-1, -1, -1), (-1, 1, -1)]
# Clockwise quarter turns, seen from outside that face; each with its layer test.
MOVES = [(lambda v: (v[0], v[2], -v[1]), lambda p: p[0] == 1),    # R
         (lambda v: (-v[1], v[0], v[2]), lambda p: p[2] == -1),   # B
         (lambda v: (v[2], v[1], -v[0]), lambda p: p[1] == -1)]   # D
SRC = [[1, 4, 2, 0, 3, 5, 6], [0, 1, 2, 4, 5, 6, 3], [0, 2, 5, 3, 1, 4, 6]]   # solver.c
TW = [[1, 2, 0, 2, 1, 0, 0], [0, 0, 0, 1, 2, 1, 2], [0, 0, 0, 0, 0, 0, 0]]    # solver.c


def det(u, v, w):
    return (u[0] * (v[1] * w[2] - v[2] * w[1]) - u[1] * (v[0] * w[2] - v[2] * w[0])
            + u[2] * (v[0] * w[1] - v[1] * w[0]))


def slots(p):
    """Sticker normals of position p: U/D sticker first, then clockwise seen from outside."""
    ud, a, b = (0, p[1], 0), (p[0], 0, 0), (0, 0, p[2])
    return [ud, a, b] if det(ud, a, b) < 0 else [ud, b, a]


def solved():
    return {(p, n): (c, k) for c, p in enumerate(POS) for k, n in enumerate(slots(p))}


def turn(st, f):
    rot, inside = MOVES[f]
    return {((rot(p), rot(n)) if inside(p) else (p, n)): v for (p, n), v in st.items()}


def solver_turn(p, o, f):
    return ([p[SRC[f][i]] for i in range(7)],
            [(o[SRC[f][i]] + TW[f][i]) % 3 for i in range(7)])


# 2. One quarter turn from solved reproduces solver.c, with o = -(slot of the U/D sticker).
for f in range(3):
    st = turn(solved(), f)
    perm, ori = [], []
    for p in POS:
        c = st[(p, slots(p)[0])][0]
        k = next(i for i, n in enumerate(slots(p)) if st[(p, n)] == (c, 0))
        perm.append(c)
        ori.append(-k % 3)
    assert perm[0] == 0 and ori[0] == 0
    assert [c - 1 for c in perm[1:]] == SRC[f] and ori[1:] == TW[f], f
print('model matches solver.c source/twist tables')

# 3. Render rule on random states.
random.seed(1)
for _ in range(2000):
    st, p, o = solved(), list(range(7)), [0] * 7
    for _ in range(random.randint(0, 15)):
        f = random.randrange(3)
        st, (p, o) = turn(st, f), solver_turn(p, o, f)
    for e in range(7):
        pos = POS[e + 1]
        for k, n in enumerate(slots(pos)):
            assert st[(pos, n)] == (p[e] + 1, (k + o[e]) % 3)
print('render rule (slot k shows sticker (k + o) mod 3) holds on 2000 random states')

# Net: face slots (col, row) * (9, 7);  . U . . / L F R B / . D . .  Facelet (a, b) at +4a, +3b.
FACE = {(0, 1, 0): ('U', 9, 0, lambda p: (p[0] + 1) // 2, lambda p: (p[2] + 1) // 2, 0xFFFFFF),
        (-1, 0, 0): ('L', 0, 7, lambda p: (p[2] + 1) // 2, lambda p: (1 - p[1]) // 2, 0xFF8000),
        (0, 0, 1): ('F', 9, 7, lambda p: (p[0] + 1) // 2, lambda p: (1 - p[1]) // 2, 0x00C000),
        (1, 0, 0): ('R', 18, 7, lambda p: (1 - p[2]) // 2, lambda p: (1 - p[1]) // 2, 0xFF0000),
        (0, 0, -1): ('B', 27, 7, lambda p: (1 - p[0]) // 2, lambda p: (1 - p[1]) // 2, 0x0000FF),
        (0, -1, 0): ('D', 9, 14, lambda p: (p[0] + 1) // 2, lambda p: (1 - p[2]) // 2, 0xFFFF00)}
ENTRY = [1, 2, 3, 4, 5, 6, 7, 0]   # entry e -> position (entry 7 = fixed corner)
XY = [[(FACE[n][1] + 4 * FACE[n][3](POS[q]), FACE[n][2] + 3 * FACE[n][4](POS[q]), FACE[n][0])
       for n in slots(POS[q])] for q in ENTRY]
COL = [[(FACE[n][5], FACE[n][0]) for n in slots(POS[q])] for q in ENTRY]
assert len({(x, y) for row in XY for x, y, _ in row}) == 24

print('\nrxy:')
for e, row in enumerate(XY):
    print('    .byte ' + ',  '.join(f'{x},{y}' for x, y, _ in row) + f'   # e={e}: '
          + ' '.join(n for *_, n in row))
print('rcol:')
for e, row in enumerate(COL):
    print('    .word ' + ', '.join(f'0x{c:06X}' for c, _ in row) + f'   # cubie {e}: '
          + ' '.join(n for _, n in row))


def picture(p, o):
    grid = [['.'] * 35 for _ in range(20)]
    for e, (c, t) in enumerate(zip(p + [7], o + [0])):
        for k in range(3):
            x, y, _ = XY[e][k]
            for dy in range(3):
                for dx in range(4):
                    grid[y + dy][x + dx] = COL[c][(k + t) % 3][1]
    return '\n'.join(''.join(r) for r in grid)


print('\nsolved:\n' + picture(list(range(7)), [0] * 7))
print('\nafter R:\n' + picture(*solver_turn(list(range(7)), [0] * 7, 0)))
