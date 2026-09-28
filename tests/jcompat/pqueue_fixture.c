/* Prints the same output as JcompatFixtures.pqueue(). */
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

#include "beagleutil/comp_hap_queue.h"
#include "jcompat/jrandom.h"

static const int64_t SEEDS[] = {0, 1, -1, -99999, 42, 0x5DEECE66DLL,
        INT64_MIN, INT64_MAX, 1234567890123LL, -1234567890123LL};

int main(void) {
    for (size_t s = 0; s < sizeof SEEDS / sizeof *SEEDS; ++s) {
        jrandom r;
        jrandom_init(&r, SEEDS[s]);
        comp_hap_queue q;
        comp_hap_queue_init(&q, 280);
        comp_hap_segment *segs = malloc(3000 * sizeof *segs);
        int next_id = 0;
        printf("seed %" PRId64 "\n", SEEDS[s]);
        for (int i = 0; i < 3000; ++i) {
            int op = jrandom_next_int_bound(&r, 10);
            if (op < 5) {
                comp_hap_segment *seg = &segs[next_id];
                seg->last_ibs_step = jrandom_next_int_bound(&r, 8);
                seg->comp_hap_index = next_id++;
                comp_hap_queue_offer(&q, seg);
            } else if (op < 7) {
                comp_hap_segment *seg = comp_hap_queue_poll(&q);
                printf("%d ", seg == NULL ? -1 : seg->comp_hap_index);
            } else if (op == 7) {
                comp_hap_segment *seg = comp_hap_queue_peek(&q);
                printf("p%d ", seg == NULL ? -1 : seg->comp_hap_index);
            } else if (op == 8) {
                comp_hap_segment *seg = comp_hap_queue_poll(&q);
                if (seg != NULL) {
                    seg->last_ibs_step = jrandom_next_int_bound(&r, 8);
                    comp_hap_queue_offer(&q, seg);
                }
            } else if (jrandom_next_int_bound(&r, 50) == 0) {
                comp_hap_queue_clear(&q);
                printf("c ");
            }
        }
        printf("\n");
        free(segs);
        comp_hap_queue_free(&q);
    }
    return 0;
}
