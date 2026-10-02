/* Ex5: level-by-level BFS over the Cayley graph of <R, B, D>.
 * Uses the factored tables from ex4.c and no queue; prints the
 * distance distribution and proves the HTM diameter is 11.
 */
#define main solver_main
#include"../../solver.c"
#undef main

static uint16_t pmove[3][5040];
static uint16_t omove[3][729];
static uint8_t depth[STATES];

/*
$ /usr/bin/time -l ./ex5
depth  0:       1
depth  1:       9
depth  2:      54
depth  3:     321
depth  4:    1847
depth  5:    9992
depth  6:   50136
depth  7:  227536
depth  8:  870072
depth  9: 1887748
depth 10:  623800
depth 11:    2644
total = 3674160 (expect 3674160)
        0.10 real         0.09 user         0.00 sys
             4784128  maximum resident set size
             4522496  peak memory footprint
*/

int main(void)
{
    // factored transition tables (see ex4.c)
    for (int f = 0; f < 3; f++) {
        for (int p = 0; p < 5040; p++) {
            state_t x;
            unrank_state(p * 729, &x);
            x = quarter_turn(x, f);
            pmove[f][p] = rank_state(&x) / 729; 
        }
        for (int o = 0; o < 729; o++) {
            state_t x;
            unrank_state(o,&x);
            x = quarter_turn(x,f);
            omove[f][o] = rank_state(&x) % 729;
        }
    }

    memset(depth, 0xFF, sizeof depth);
    depth[0] =0; // solved
    uint32_t total = 0;

    /* expand every state at depth d with all 9 moves;
       unvisited neighbours belong to depth d + 1 */
    for(int d=0;;d++){
        uint32_t count=0,found=0;
        for(int r=0; r<STATES;r++){
            if(depth[r] != d) continue;
            count++;

            uint16_t p0 = r / 729, o0 = r % 729;

            // 3 faces x 1..3 quarter turns = 9 moves
            for(int f=0; f<3; f++){
                uint16_t p=p0, o=o0;
                for(int turn=0; turn<3; turn++){
                    p = pmove[f][p];
                    o = omove[f][o];

                    uint32_t rank2 = p * 729 + o;
                    
                    if(depth[rank2] == 0xFF){
                        depth[rank2] = d+1; // rank is in d + 1 layer
                        found++;
                    }

                }
            }
        }
        total += count;
        printf("depth %2d: %7d\n", d, count);
        if (found == 0) break;
    }
    printf("total = %u (expect %u)\n", total, STATES);
    return 0;
}