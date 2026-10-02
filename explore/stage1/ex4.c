/* Ex4: factored transition tables.
 * The permutation and orientation ranks advance independently, so a quarter
 * turn is two lookups: pmove[face][p] and omove[face][o].
 */
#define main solver_main
#include"../../solver.c"
#undef main

static uint16_t pmove[3][5040];
static uint16_t omove[3][729];

int main(void)
{
    for (int f = 0; f < 3; f++) {
        for (int p = 0; p < 5040; p++) {
            state_t x;
            unrank_state(p * 729, &x);        /* pair p with o = 0 */
            x = quarter_turn(x, f);
            pmove[f][p] = rank_state(&x) / 729;   /* keep the p part */
        }
        for (int o = 0; o < 729; o++) {
            state_t x;
            unrank_state(o,&x);               /* pair o with p = 0 */
            x = quarter_turn(x,f);
            omove[f][o] = rank_state(&x) % 729;   /* keep the o part */
        }
    }

    printf("pmove[0][0] = %u (expect 1104)\n", pmove[0][0]);
    printf("omove[0][0] = %u (expect 426)\n",  omove[0][0]);
    printf("table bytes = %zu (expect 34614)\n", sizeof pmove + sizeof omove);

    /* compare table lookups against apply_move for every state and move */
    long bad = 0;
    for (uint32_t r = 0; r < STATES; r++)
        for (int m = 0; m < 9; m++) {
            int face = m / 3, turns = m % 3 + 1;

            state_t x;                         /* method A: apply_move */
            unrank_state(r, &x);
            x = apply_move(x, m);
            uint32_t expect = rank_state(&x);

            uint16_t p = r / 729, o = r % 729; /* method B: table lookup */
            for (int t = 0; t < turns; t++) {
                p = pmove[face][p];
                o = omove[face][o];
            }
            if ((uint32_t) p * 729 + o != expect) bad++;
        }
    printf("table vs apply_move: bad = %ld / %u\n", bad, STATES * 9);

    return 0;
}
