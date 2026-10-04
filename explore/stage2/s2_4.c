// S2-4: IDA* with a finer heuristic table, index = p * K + otab[o].
// Copied from s2_3.c; the heuristic is now computed in one place, h_of().
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

/* ---------- S2-4: finer abstraction ---------- */
// splits the 729 orientation ranks into; record which positions you use
// and why in stage2-note.md.
// #define K ?
#ifndef K 
#define K 9
//#error "S2-4: define K (and decide what otab[] stores) before building"
#endif

static uint8_t otab[729];        // small table: o rank -> class 0..K-1
static uint8_t big[5040 * K];    // big table: min depth over each group

void build_otab()
{
    // for every o rank 0..728
    //   - unrank_state(o, &x) gives a state whose orientation part is o
    //   - read the orientation digits you chose from x.o[...]
    //   - combine them into one number 0..K-1 and store it in otab[o]
    
    for(int o=0; o<729; o++){
        state_t x;
        unrank_state(o, &x);
        otab[o] = x.o[0] * 3 + x.o[1]; // encode o[0,1]

    }

}

void build_big()
{
    //  needs depth[] and otab[]
    //   - for every rank r: p = r / 729, o = r % 729, idx = p * K + otab[o]
    //   - keep the minimum: if depth[r] < big[idx], big[idx] = depth[r]
    memset(big, 0xFF, sizeof big);
    for(int r=0;r<STATES;r++){
        int p= r/729, o = r % 729;
        int idx = p * K +otab[o];
        if(depth[r] < big[idx]) big[idx] = depth[r];

    }

}

// The heuristic used by the search. Starts as the S2-3 heuristic so the
// file runs unchanged; replace it with the big-table lookup.
static inline int h_of(int p, int o)
{
    // use big[p * K + otab[o]] (and decide whether to also
    // take the max with pdist[p] / odist[o])
    int tmp = big[p * K + otab[o]];
    return tmp > odist[o] ? tmp : odist[o];
}


uint64_t count =0; //count the bls
uint8_t  prune =1; //prune on/off

uint8_t dls(uint8_t g, uint8_t bound, int p, int o, int8_t last_face)
{
    count++;
    if(!p&&!o) return 1;     // check solved
    int mdist = h_of(p, o);
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
    int h0 = h_of(p, o);

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
    build_otab();
    build_big();

    // H2 and H1 for the new table (same checks as in s2_2.c)
    int unfilled = 0, bmax = 0;
    for (int i = 0; i < 5040 * K; i++) {
        if (big[i] == 0xFF) unfilled++;
        else if (big[i] > bmax) bmax = big[i];
    }
    printf("big: %zu bytes, unfilled=%d max=%d solved group=%d\n",
           sizeof big, unfilled, bmax, big[0 * K + otab[0]]);

    int bad = 0;
    for (int r = 0; r < STATES; r++) {
        int p = r / 729, o = r % 729;
        if (h_of(p, o) > depth[r]) bad++;
    }
    printf("H1: h > depth in %d states (expect 0)\n", bad);

    // S2-3 measurement, unchanged: worst distance-11 state with the new h

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
