// S2-3: IDA* = iterative deepening (s2_1.c) + heuristic tables (s2_2.c)
// Functions below are copied from s2_1.c and s2_2.c; TODO marks what changes.
#include "common.h"

/* ---------- heuristic tables (from s2_2.c) ---------- */
static uint8_t pdist[5040];
static uint8_t odist[729];

void build_pdist()
{
    memset(pdist, 0xFF, sizeof pdist);
    pdist[0]=0;
    for (int d = 0;; d++) {
        int found=0;
        for (int p =0; p<5040; p++) {
            if(pdist[p] != d) continue;

            for(int face=0; face< 3; face++){
                int np = p;
                for (int turn = 0; turn < 3; turn++) {
                    np = pmove[face][np];
                    if (pdist[np] == 0xFF) {
                        pdist[np]= d+1;
                        found++;
                    }
                }
            }
        }
        if (found == 0) break;
    }
}

void build_odist()
{
   memset(odist, 0xFF, sizeof odist);
   odist[0]=0;

    for(int d=0;;d++){
        int found=0;
        for(int o=0;o<729;o++){
            if(odist[o] != d) continue;

            for(int face=0; face<3; face++){
                int no = o;
                for(int turn=0;turn<3;turn++){
                    no = omove[face][no];
                    if(odist[no] == 0xFF){
                        odist[no] = d+1;
                        found++;
                    }
                }
            }
        }
        if(found ==0) break;
    }
}


uint64_t count =0; //count the bls
uint8_t  prune =1; //prune on/off

uint8_t dls(uint8_t g, uint8_t bound, int p, int o, int8_t last_face)
{
    count++;
    if(!p&&!o) return 1;     // check solved
    // replace the bound check above with the heuristic cut
    int mdist = pdist[p] > odist[o] ? pdist[p] : odist[o];
    if(g + mdist > bound) return 0;
    // if(g >= bound) return 0;    // check bound limit
    
    for(int face=0;face <3;face++){
        if(prune && face == last_face) continue;
        int np=p,no=o;
        for(int turn=0;turn < 3;turn++){
            np = pmove[face][np];
            no = omove[face][no];
            if(dls(g +1, bound, np, no, face)) return 1;
        }
    }
    return 0;
}

uint8_t inter_deep_dfs(int init)
{
    int result=0;
    uint16_t p = init / 729, o= init % 729;

    // start the bound at h(root) instead of 0
    int h0 = pdist[p] > odist[o] ? pdist[p] : odist[o];

    for(int limit=h0;;limit++){
        result = dls(0, limit, p, o, -1);
        if(result) return limit;
        if(limit > 11) return -1;
    }
    return -1;
}

/* ---------- measurement ---------- */
int main(void)
{
    build_moves();
    build_depth();
    build_pdist();
    build_odist();

    // TODO(S2-3 measure): for every r with depth[r] == 11
    //   - reset count, run inter_deep_dfs(r)
    //   - check the returned length is 11 (print an error otherwise)
    //   - track the maximum count and its rank, and the sum for the average
    // then print: number of states, max count + rank, average count

    uint64_t num =0,sum =0,maxc =0, maxr =0;
    for(int r =0;r<STATES;r++){
        if(depth[r] != 11) continue;
        count =0;
        int len = inter_deep_dfs(r);
        if(len != 11) printf("error state: %d,%d \n", r, len);
        num++, sum += count;
        if(count > maxc){
            maxc = count;
            maxr = r;
        }
    }
    printf("num=%llu, maxc=%llu, maxr=%llu, sum/num= %.2f\n", num, maxc, maxr, (double) sum/num);

    // Reported vector from the assignment
    state_t s;
    if (!parse_state("21345671111111", &s)) {
        printf("parse failed\n");
        return 1;
    }

    int r = rank_state(&s);
    count = 0;
    uint8_t len = inter_deep_dfs(r);
    printf("21345671111111: rank %u, depth %d, found %d, nodes %llu\n",
           r, depth[r], len, (unsigned long long) count);

    return 0;
}
