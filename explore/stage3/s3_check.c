// S3-1 check: the generated tables.h must equal the tables computed here
// (same code as s3_gen.c), plus H2 on the emitted copy.
#define S3_GEN_NO_MAIN
#include "s3_gen.c"

/* Emitted copies under other names, so both sets coexist. */
#define pmove T_pmove
#define omove T_omove
#define big T_big
#define otab T_otab
#define odist T_odist
#undef K
#include "tables.h"
#undef pmove
#undef omove
#undef big
#undef otab
#undef odist

/* Count differences and report H2 (unfilled, max, entry 0) for one table. */
static int cmp(const char *name, int size, const void *a, const void *b, int n)
{
    int diff = 0, unfilled = 0, max = 0;
    for (int i = 0; i < n; i++) {
        int x = size == 2 ? ((const uint16_t *) a)[i] : ((const uint8_t *) a)[i];
        int y = size == 2 ? ((const uint16_t *) b)[i] : ((const uint8_t *) b)[i];
        diff += x != y;
        unfilled += size == 1 && y == 0xFF;
        if (y > max) max = y;
    }
    int e0 = size == 2 ? ((const uint16_t *) b)[0] : ((const uint8_t *) b)[0];
    printf("%-6s %6d entries  diff %d  unfilled %d  max %d  [0] = %d\n",
           name, n, diff, unfilled, max, e0);
    return diff + unfilled;
}

int main(void)
{
    build_moves();
    build_depth();
    build_odist();
    build_otab();
    build_big();

    int bad = 0;
    bad += cmp("pmove", 2, pmove, T_pmove, 3 * 5040);
    bad += cmp("omove", 2, omove, T_omove, 3 * 729);
    bad += cmp("big", 1, big, T_big, 5040 * K);
    bad += cmp("otab", 1, otab, T_otab, 729);
    bad += cmp("odist", 1, odist, T_odist, 729);

    /* H1 on the emitted tables: h(s) <= d(s) for every state. */
    uint32_t over = 0;
    for (uint32_t r = 0; r < STATES; r++) {
        int p = r / 729, o = r % 729;
        int h = T_big[p * K + T_otab[o]];
        if (T_odist[o] > h) h = T_odist[o];
        over += h > depth[r];
    }
    printf("H1: %u / %u states with h > d\n", over, STATES);
    bad += over != 0;
    printf("%s\n", bad ? "MISMATCH" : "tables.h OK");
    return bad != 0;
}
