/* Shared IDA* search: the SAME file is compiled by the host harness
 * (s3_ida.c, H3 + node counts) and the RV32I build (rv_ida.c).
 * Needs the tables pmove, omove, big, otab, odist (tables.h) in scope.
 * v0: s2_6.c dls_iter/ida_iter copied unchanged (m / 3, m % 3 left in).
 * The RV32I link fails if any variable *, /, % is left (__divsi3...).
 * After each change: node counts must stay 125,651 / 40,526 and H3 = 0.
 */

#ifndef IDA_H
#define IDA_H
#include <stdint.h>

#define MAXD 12                 /* 11 moves + the start state */

#ifdef COUNT_NODES
static uint64_t ida_nodes;
#define COUNT() (ida_nodes++)
#else
#define COUNT() ((void) 0)
#endif

static uint16_t P[MAXD], O[MAXD];
static int8_t   F[MAXD];
static uint8_t  M[MAXD];
static uint8_t  path[MAXD];     /* solution moves 0..8 */

static inline int h_of(int p, int o)
{
    int tmp = big[p * K + otab[o]];
    return tmp > odist[o] ? tmp : odist[o];
}

static void move_po(int p, int o, int m, int *np, int *no)
{
    int f = m / 3;
    for (int t = 0; t <= m % 3; t++) {
        p = pmove[f * 5040 + p];                     /* tables.h is flat */
        o = omove[f * 729 + o];
    }
    *np = p;
    *no = o;
}

static int dls_iter(int p0, int o0, int bound, int *len)
{
    int g = 0;
    P[0] = p0; O[0] = o0; F[0] = -1; M[0] = 0;

    COUNT();
    if (p0 == 0 && o0 == 0) { *len = 0; return 1; }
    if (h_of(p0, o0) > bound) return 0;

    for (;;) {
        if (M[g] == 9) {
            if (g == 0) return 0;
            g--;
            continue;
        }
        int m = M[g]++;
        if (m / 3 == F[g]) continue;

        int np, no;
        move_po(P[g], O[g], m, &np, &no);
        COUNT();

        if (np == 0 && no == 0) {
            path[g] = m;
            *len = g + 1;
            return 1;
        }
        if (g + 1 + h_of(np, no) > bound) continue;

        path[g] = m;
        g++;
        P[g] = np;
        O[g] = no;
        F[g] = m / 3;
        M[g] = 0;
    }
}

/* Takes (p, o) directly: the target gets them from the input string,
 * so r / 729 never appears on the target. Returns the length or -1. */
static int ida_solve(int p, int o, int *len)
{
    for (int limit = h_of(p, o); limit <= 11; limit++)
        if (dls_iter(p, o, limit, len))
            return limit;
    return -1;
}

#endif
