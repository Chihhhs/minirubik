/* Ex2: the orientation invariant, sum(o) == 0 (mod 3).
 * Random walk keeps every state valid, a single twisted corner is
 * rejected, and each face's twist row sums to 0 mod 3.
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


int main()
{
    state_t s;
    unrank_state(0, &s);          /* rank 0 = solved */
    print_state("Solved",s);

    state_t t = s;

    srand((unsigned) 1);          /* fixed seed: reproducible run */
    int fail =0;
    for(int i=0;i<100;i++){
        t = apply_move(t,rand() % 9);
        if(!valid(&t))
            fail++;
    }
    printf("failures:%d/100",fail);
    printf("\n");

    // twist a single corner: sum(o) = 1, must be invalid
    t = s;
    t.o[0]=1;
    printf("%d\n",valid(&t)); // 0

    // each twist row must sum to 0 mod 3
    for(int i=0;i<3;i++){
        int sum=0;
        for(int j=0;j<CUBIES;j++)
            sum+=twist[i][j];
        printf("twist[%d]'s sum=%d, mod 3 = %d \n", i, sum, sum%3);
    }


    return 0;
}
