/* Reads the output of JcompatFixtures.search() and prints it again,
 * recomputing each result with jarrays_search_int. */
#include <inttypes.h>
#include <stdio.h>

#include "jcompat/jarrays.h"

int main(void) {
    int n;
    while (scanf("%d", &n) == 1) {
        int32_t a[64], from, to, key, expected;
        if (n < 0 || n > 64) return 1;
        for (int i = 0; i < n; ++i) {
            if (scanf("%" SCNd32, &a[i]) != 1) return 1;
        }
        if (scanf("%" SCNd32 " %" SCNd32 " %" SCNd32 " %" SCNd32, &from, &to, &key, &expected) != 4) return 1;
        printf("%d", n);
        for (int i = 0; i < n; ++i) printf(" %" PRId32, a[i]);
        printf(" %" PRId32 " %" PRId32 " %" PRId32 " %d\n", from, to, key, jarrays_search_int(a, from, to, key));
    }
    return 0;
}
