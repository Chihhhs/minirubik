/* Ex3: the dense rank, Lehmer(p) * 729 + base-3(o[0..5]).
 * Checks a hand-computed rank and the rank/unrank bijection over all states.
 */
#define main solver_main
#include "../../solver.c"
#undef main
#include<stdio.h>
#include<stdlib.h>
#include <time.h>

void print_state(const char *label, state_t s)
{
    printf("%-4s p=", label);
    for (int i = 0; i < CUBIES; i++)
        printf("%d", s.p[i]);
    printf("  o=");
    for (int i = 0; i < CUBIES; i++)
        printf("%d", s.o[i]);
    printf("\n");
}

/*
Operation count (sed -n 87,145p solver.c | grep -nE '\*|/|%'):
rank_state:   3 multiplies (x(7-i), x3, x729)
unrank_state: 4 divides, 5 remainders
*/

/*
Lehmer code by hand, e.g. after R: p=1420356 o=1202100
digits (smaller entries to the right): 1,3,1,0,0,0,0

0 * 7 + 1    = 1
1 * 6 + 3    = 9
9 * 5 + 1    = 46
46 * 4 + 0   = 184
184 * 3 + 0  = 552
552 * 2 + 0  = 1104
1104 * 1 + 0 = 1104

o_rank (first six digits, base 3)
1*3^5 + 2*3^4 + 0 *3^3 + 2*3^2 + 1*3^1 + 0*3^0 = 426

rank = p * 3^6 + o = 1104 * 729 + 426 = 805242
*/

int main()
{
    state_t s;
    unrank_state(0, &s);          /* rank 0 = solved */
    print_state("Solved",s);

    state_t rs = apply_move(s,0);
    print_state("R", rs);
    printf("Rank: %d\n", rank_state(&rs));
    printf("rank / 729 = %d, rank %% 729 = %d\n",rank_state(&rs) / 729 , rank_state(&rs) % 729);


    clock_t t0 = clock();
    int fail = 0;
    for (uint32_t r = 0; r < STATES; r++) {
        state_t x;
        unrank_state(r, &x);
        if (!valid(&x)) fail++; // validity only, not a round trip
    }
    printf("fail=%d  time=%.3f s\n", fail, (double)(clock() - t0) / CLOCKS_PER_SEC);

    // check round-trip
    int bad_state = 0, bad_round = 0;
    for (uint32_t r = 0; r < STATES; r++) {
        state_t x;
        unrank_state(r, &x);
        if (!valid(&x)) bad_state++;              /* unranked state is valid */
        if (rank_state(&x) != r) bad_round++;     /* and ranks back to the same r */
    }
    if(bad_state|bad_round)
        printf("bad state: %d / %d , bad round: %d / %d\n", bad_state, STATES, bad_round, STATES);
    else printf("Pass\n");

    return 0;
}
