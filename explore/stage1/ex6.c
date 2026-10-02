/* Ex6: where the cost lies.
 * ex5.c plus counters for expanded states, edges and table lookups.
 */
#define main solver_main
#include"../../solver.c"
#undef main

static uint16_t pmove[3][5040];
static uint16_t omove[3][729];
static uint8_t depth[STATES];

uint64_t expanded = 0;   /* states expanded */
uint64_t edges    = 0;   /* edges tried, one per move */
uint64_t lookups  = 0;   /* table lookups, pmove + omove = 2 per edge */

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
            expanded++;

            uint16_t p0 = r / 729, o0 = r % 729;

            // 3 faces x 1..3 quarter turns = 9 moves
            for(int f=0; f<3; f++){
                uint16_t p=p0, o=o0;
                for(int turn=0; turn<3; turn++){
                    p = pmove[f][p];
                    o = omove[f][o];
                    lookups +=2;

                    uint32_t rank2 = p * 729 + o;
                    edges +=1;
                    
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
    
    printf("expanded: %llu, (expect 3674160)\n",expanded);
    printf("edges: %llu, (expect 33067440)\n",edges);
    printf("lookups: %llu, (expect 66134880)\n",lookups);

    return 0;
}