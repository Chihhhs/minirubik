/* RV32I build of the shared search (ida.h) on fixed test states.
 * TODO S3-4 (yours): replace the (p, o) constants with parsing the
 * 14-char input string, and re-apply the path to check it is solved (T5).
 * Exit code: 0 = all tests pass.
 */
#include "rv.h"
#include "tables.h"
#include "ida.h"

/* (p, o) = (rank / 729, rank % 729), computed on the host. */
/* -DONLY=n runs just tests[n] (to measure one state's retired count). */
static const struct { uint16_t p, o; uint8_t d; } all_tests[] = {
    {0, 0, 0},          /* solved */
    {264, 0, 11},       /* rank 192,456: hardest distance-11 state */
    {720, 0, 11},       /* rank 524,880: 21345671111111 */
};
#ifdef ONLY
#define tests (all_tests + ONLY)
#define NTESTS 1
#else
#define tests all_tests
#define NTESTS (sizeof all_tests / sizeof all_tests[0])
#endif

int main(void)
{
    int fail = 0;
    for (unsigned i = 0; i < NTESTS; i++) {
        int len = 0;
        int d = ida_solve(tests[i].p, tests[i].o, &len);
        print_int(d);
        print_str(" moves:");
        for (int k = 0; k < len; k++) {
            print_char(' ');
            print_int(path[k]);
        }
        print_char('\n');
        fail |= d != tests[i].d;
    }
    return fail;
}
