// S2-6: non-recursive IDA*. Same search as s2_4.c (recursive dls kept as
// the reference), rewritten with explicit per-depth arrays for Stage 3/4.
#include "common.h"
#include <time.h>

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


#ifndef K 
#define K 9
#endif

static uint8_t otab[729];        // small table: o rank -> class 0..K-1
static uint8_t big[5040 * K];    // big table: min depth over each group

void build_otab()
{
    for(int o=0; o<729; o++){
        state_t x;
        unrank_state(o, &x);
        otab[o] = x.o[0] * 3 + x.o[1]; // encode o[0,1]

    }

}

void build_big()
{
    memset(big, 0xFF, sizeof big);
    for(int r=0;r<STATES;r++){
        int p= r/729, o = r % 729;
        int idx = p * K +otab[o];
        if(depth[r] < big[idx]) big[idx] = depth[r];

    }

}

static inline int h_of(int p, int o)
{
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
/* ---------- non-recursive version ---------- */
#define MAXD 12                 // 11 moves + the start state

static uint16_t P[MAXD], O[MAXD];   // state at depth g
static int8_t   F[MAXD];            // face of the move that led to depth g (-1 at the start)
static uint8_t  M[MAXD];            // next move to try at depth g, 0..9 (9 = all tried)
static uint8_t  path[MAXD];         // moves of the solution, filled when found

// Helper: apply move m (0..8) to (p, o). Face m / 3, (m % 3 + 1) quarter turns.
static void move_po(int p, int o, int m, int *np, int *no)
{
    int f = m / 3;
    for (int t = 0; t <= m % 3; t++) {
        p = pmove[f][p];
        o = omove[f][o];
    }
    *np = p;
    *no = o;
}

// Depth-limited search without recursion. Returns 1 if a solution of at
// most `bound` moves exists; then path[0..len-1] holds it and *len is set.
static int dls_iter(int p0, int o0, int bound, int *len)
{
    int g = 0;
    P[0] = p0; O[0] = o0; F[0] = -1; M[0] = 0;

    count++;                      // the start node (recursive dls counts it too)
    if (p0 == 0 && o0 == 0) { *len = 0; return 1; }
    if (h_of(p0, o0) > bound) return 0;

    for (;;) {
        // Step 1: all 9 moves at depth g tried?
        //   if g == 0: nothing found in this bound -> return 0
        //   else: go back up one level, and continue the loop
        if(M[g] == 9){
            if(g==0) return 0;
            g--;
            continue;
            
        }

        // Step 2: take the next move at this depth and advance the counter
        int m = M[g]++;

        // Step 3: same-face pruning (compare the face of m with F[g])
        if(prune && m / 3 == F[g]) continue;

        // Step 4: child state
        int np, no;
        move_po(P[g], O[g], m, &np, &no);
        count++;

        // Step 5: solved? record the move, the path is path[0..g], return 1
        if(np ==0 && no ==0){
            path[g] = m;
            *len = g+1;
            return 1;
        }

        // Step 6: heuristic cut for the child: it sits at depth g + 1
        if(g + 1 + h_of(np, no) > bound) continue;

        // Step 7: go down: record the move, g++, store the child in P/O,
        path[g] = m;
        g++;
        P[g] = np;
        O[g] = no;
        F[g] = m /3;
        M[g] = 0;
    }
}

static int ida_iter(int r, int *len)
{
    int p = r / 729, o = r % 729;
    for (int limit = h_of(p, o); limit <= 11; limit++)
        if (dls_iter(p, o, limit, len))
            return limit;
    return -1;
}

int main(void)
{
    build_moves();
    build_depth();
    build_pdist();
    build_odist();
    build_otab();
    build_big();

    // 1) answer AND node count as the recursive version
    //    on the worst state and on the reported vector.
    uint32_t tests[2] = {192456, 524880};
    for (int i = 0; i < 2; i++) {
        count = 0;
        int a = inter_deep_dfs(tests[i]);
        uint64_t ca = count;
        count = 0;
        int len;
        int b = ida_iter(tests[i], &len);
        printf("rank %u: recursive %d (%llu nodes), iterative %d (%llu nodes) %s\n",
               tests[i], a, (unsigned long long) ca, b,
               (unsigned long long) count,
               (a == b && ca == count) ? "OK" : "MISMATCH");
        printf("  path:");
        for (int k = 0; k < len; k++)
            printf(" %s", move_names[path[k]]);
        printf("\n");
    }

    // 2) H3 with the iterative version
    clock_t t0 = clock();
    uint32_t wrong = 0;
    for (uint32_t r = 0; r < STATES; r++) {
        int len;
        if (ida_iter(r, &len) != depth[r]) {
            if (wrong < 10)
                printf("H3 FAIL: rank %u depth %d\n", r, depth[r]);
            wrong++;
        }
    }
    printf("H3 (iterative): %u / %u wrong, %.1f s\n", wrong, STATES,
           (double) (clock() - t0) / CLOCKS_PER_SEC);
    return wrong != 0;
}
