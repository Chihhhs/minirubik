/* Shared IDA* search: the SAME file is compiled by the host harness
 * (s3_ida.c, H3 + node counts) and the RV32I build (rv_ida.c).
 * Needs the tables pmove, omove, big, otab, odist (tables.h) in scope.
 * v0 = s2_6.c dls_iter/ida_iter; v1 = face/turn counters (see dls_iter).
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

static uint16_t P[MAXD], O[MAXD];   /* parent state at depth g */
static int8_t   F[MAXD];            /* face of the move into depth g (-1 at root) */
static uint8_t  CF[MAXD];           /* face being tried at depth g (3 = done) */
static uint8_t  CT[MAXD];           /* quarter turns done on that face (0..3) */
static uint16_t CP[MAXD], CO[MAXD]; /* state after CT turns: chained turns */
static uint8_t  path[MAXD];         /* solution moves 0..8 */

static inline int h_of(int p, int o)
{
    int tmp = big[p * K + otab[o]];                 /* *9: gcc -> shift+add */
    return tmp > odist[o] ? tmp : odist[o];
}

/* Start trying moves at depth g from its parent state. */
static inline void level_init(int g)
{
    CF[g] = 0;
    CT[g] = 0;
    CP[g] = P[g];
    CO[g] = O[g];
}

/* v1 (AI-written, 10-06): m = 0..8 split into face CF[g] and turn CT[g],
 * so no / or %; turns on one face are chained from CP/CO instead of
 * re-applied from P/O. Same move order as v0 -> same node counts. */
static int dls_iter(int p0, int o0, int bound, int *len)
{
    int g = 0;
    P[0] = p0; O[0] = o0; F[0] = -1;
    level_init(0);

    COUNT();
    if (p0 == 0 && o0 == 0) { *len = 0; return 1; }
    if (h_of(p0, o0) > bound) return 0;

    for (;;) {
        /* Face finished (3 turns) or same face as the last move: next face. */
        if (CT[g] == 3 || CF[g] == F[g]) {
            CF[g]++;
            CT[g] = 0;
            CP[g] = P[g];
            CO[g] = O[g];
            continue;
        }
        /* All 3 faces tried: back up one level. */
        if (CF[g] == 3) {
            if (g == 0) return 0;
            g--;
            continue;
        }

        /* One more quarter turn of face CF[g] on the chained state. */
        int f = CF[g];
        int np = pmove[f * 5040 + CP[g]];            /* const *: shift+add */
        int no = omove[f * 729 + CO[g]];
        CP[g] = np;
        CO[g] = no;
        CT[g]++;
        COUNT();

        if (np == 0 && no == 0) {
            path[g] = f * 3 + CT[g] - 1;
            *len = g + 1;
            return 1;
        }
        if (g + 1 + h_of(np, no) > bound) continue;  /* next turn chains */

        path[g] = f * 3 + CT[g] - 1;
        g++;
        P[g] = np;
        O[g] = no;
        F[g] = f;
        level_init(g);
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
