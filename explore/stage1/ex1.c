/* Ex1: state representation and moves.
 * Apply single moves from solved and check basic group identities.
 */
#define main solver_main
#include "../../solver.c"
#undef main

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

int main()
{
    state_t s;
    unrank_state(0, &s);          /* rank 0 = solved */
    print_state("Solved",s);
    state_t t = s;

    /* A: apply R, B and D once each, starting from solved */
    print_state("R", t=apply_move(s, 0));
    print_state("2R", t=apply_move(t, 0));
    print_state("3R", t=apply_move(t, 0));

    /* move numbers: B = 3, D = 6 */
    print_state("B", apply_move(s,3));
    print_state("D", apply_move(s,6));

    /* B: R applied 4 times must return to solved */
    //R,R2,R' -> 0,1,2
    t=s;
    for(int i=0; i< 4; i++) t = apply_move(t,0);
    print_state("4R",t);

    /* C: R followed by R' (move 0 then 2) must return to solved */
    t = s;
    print_state("R",t=apply_move(t,0));
    print_state("R'",t=apply_move(t,2));

    return 0;
}
