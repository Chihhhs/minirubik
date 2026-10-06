// S3-2/S3-3 host harness: node counts on the two reference states and H3
// over all states, for the shared search in ida.h using the emitted tables.
#include "../stage2/common.h"   /* depth[] (exact BFS), move_names */
#include <time.h>

/* Emitted tables under other names, so they don't clash with common.h;
 * ida.h is written with the plain names and sees the emitted ones. */
#define pmove T_pmove
#define omove T_omove
#include "tables.h"
#define COUNT_NODES
#ifdef LOW
#include "ida_low.h"        /* make s3_ida LOW=1 */
#define VERSION "ida_low.h"
#else
#include "ida.h"
#define VERSION "ida.h"
#endif
#undef pmove
#undef omove

int main(void)
{
    printf("search: %s\n", VERSION);
    build_moves();
    build_depth();

    /* 1) node counts must match v0 (s2_6.c): any change = different search */
    struct { uint32_t r; uint64_t nodes; } ref[] = {
        {192456, 125651},       /* hardest distance-11 state */
        {524880, 40526},        /* 21345671111111 */
    };
    int bad = 0;
    for (int i = 0; i < 2; i++) {
        int len;
        ida_nodes = 0;
        int d = ida_solve(ref[i].r / 729, ref[i].r % 729, &len);
        int ok = d == depth[ref[i].r] && ida_nodes == ref[i].nodes;
        bad += !ok;
        printf("rank %u: length %d, %llu nodes (v0 %llu) %s\n  path:", ref[i].r,
               d, (unsigned long long) ida_nodes,
               (unsigned long long) ref[i].nodes, ok ? "OK" : "MISMATCH");
        for (int k = 0; k < len; k++)
            printf(" %s", move_names[path[k]]);
        printf("\n");
    }

    /* 2) H3 over all states */
    clock_t t0 = clock();
    uint32_t wrong = 0;
    for (uint32_t r = 0; r < STATES; r++) {
        int len;
        if (ida_solve(r / 729, r % 729, &len) != depth[r]) {
            if (wrong < 10)
                printf("H3 FAIL: rank %u depth %d\n", r, depth[r]);
            wrong++;
        }
    }
    printf("H3: %u / %u wrong, %.1f s\n", wrong, STATES,
           (double) (clock() - t0) / CLOCKS_PER_SEC);
    return bad || wrong;
}
