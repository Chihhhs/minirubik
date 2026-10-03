/* Shared Stage 2 helpers: the factored move tables (ex4.c) and the exact
 * BFS distance of every state (ex5.c), used as ground truth for the search.
 */
#define main solver_main
#include "../../solver.c"
#undef main

static uint16_t pmove[3][5040];
static uint16_t omove[3][729];
static uint8_t depth[STATES];   /* exact distance to solved, 0..11 */

/* Quarter-turn tables: pmove[face][p], omove[face][o]. */
static void build_moves(void)
{
    for (int f = 0; f < 3; f++) {
        for (int p = 0; p < 5040; p++) {
            state_t x;
            unrank_state(p * 729, &x);        /* pair p with o = 0 */
            x = quarter_turn(x, f);
            pmove[f][p] = rank_state(&x) / 729;
        }
        for (int o = 0; o < 729; o++) {
            state_t x;
            unrank_state(o, &x);              /* pair o with p = 0 */
            x = quarter_turn(x, f);
            omove[f][o] = rank_state(&x) % 729;
        }
    }
}

/* Level-by-level BFS from solved; needs build_moves() first. */
static void build_depth(void)
{
    memset(depth, 0xFF, sizeof depth);
    depth[0] = 0;
    for (int d = 0;; d++) {
        uint32_t found = 0;
        for (uint32_t r = 0; r < STATES; r++) {
            if (depth[r] != d)
                continue;
            uint16_t p0 = r / 729, o0 = r % 729;
            for (int f = 0; f < 3; f++) {
                uint16_t p = p0, o = o0;
                for (int t = 0; t < 3; t++) {
                    p = pmove[f][p];
                    o = omove[f][o];
                    uint32_t r2 = (uint32_t) p * 729 + o;
                    if (depth[r2] == 0xFF) {
                        depth[r2] = d + 1;
                        found++;
                    }
                }
            }
        }
        if (found == 0)
            break;
    }
}
