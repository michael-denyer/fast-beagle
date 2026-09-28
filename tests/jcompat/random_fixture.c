/* Prints the same output as JcompatFixtures.random(). */
#include <inttypes.h>
#include <stdio.h>

#include "jcompat/jrandom.h"

static const int64_t SEEDS[] = {0, 1, -1, -99999, 42, 0x5DEECE66DLL,
        INT64_MIN, INT64_MAX, 1234567890123LL, -1234567890123LL};
static const int32_t BOUNDS[] = {1, 2, 3, 7, 10, 16, 181, 362, 1000, 1 << 20,
        (1 << 30) + 1, 1 << 30, INT32_MAX, 1717986919};

int main(void) {
    for (size_t s = 0; s < sizeof SEEDS / sizeof *SEEDS; ++s) {
        jrandom r;
        jrandom_init(&r, SEEDS[s]);
        printf("seed %" PRId64 "\n", SEEDS[s]);
        for (int i = 0; i < 20; ++i) printf("%" PRId32 " ", jrandom_next_int(&r));
        printf("\n");
        for (size_t b = 0; b < sizeof BOUNDS / sizeof *BOUNDS; ++b) {
            for (int i = 0; i < 20; ++i) printf("%" PRId32 " ", jrandom_next_int_bound(&r, BOUNDS[b]));
            printf("\n");
        }
        for (int i = 0; i < 20; ++i) printf("%" PRId64 " ", jrandom_next_long(&r));
        printf("\n");
        for (int i = 0; i < 64; ++i) putchar(jrandom_next_boolean(&r) ? '1' : '0');
        printf("\n");
        jrandom_init(&r, (int64_t)((uint64_t)SEEDS[s] + 7));
        for (int i = 0; i < 5; ++i) printf("%" PRId32 " ", jrandom_next_int_bound(&r, 1000));
        printf("\n");
    }
    return 0;
}
