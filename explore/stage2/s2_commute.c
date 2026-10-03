/* S2-1 Q4: do any two of R, B, D commute?
 * For every pair of moves a, b on different faces, count the states s
 * where applying a then b equals applying b then a. If a pair commutes,
 * the count equals STATES; one state that differs is a counterexample.
 */
#include "common.h"

/* Apply move m (face m/3, m%3+1 quarter turns) to the rank r. */
static uint32_t move_rank(uint32_t r, int m)
{
    uint16_t p = r / 729, o = r % 729;
    for (int t = 0; t <= m % 3; t++) {
        p = pmove[m / 3][p];
        o = omove[m / 3][o];
    }
    return (uint32_t) p * 729 + o;
}

int main(void)
{
    static const char *name[9] = {"R", "R2", "R'", "B", "B2", "B'",
                                  "D", "D2", "D'"};
    build_moves();

    for (int a = 0; a < 9; a++)
        for (int b = a + 1; b < 9; b++) {
            if (a / 3 == b / 3)
                continue; /* same face: handled by same-face pruning */
            uint32_t same = 0;
            for (uint32_t r = 0; r < STATES; r++)
                if (move_rank(move_rank(r, a), b) ==
                    move_rank(move_rank(r, b), a))
                    same++;
            printf("%-2s %-2s  equal on %7u / %u states%s\n", name[a],
                   name[b], same, STATES,
                   same == STATES ? "  -> commute" : "");
        }
    return 0;
}
