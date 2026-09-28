/* Reads the output of JcompatFixtures.parseInt() and prints it again,
 * recomputing the results with jnum_parse_int and jnum_parse_long. */
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

#include "jcompat/jnum.h"

int main(void) {
    char in[256], line[512], text[128];
    while (fgets(line, sizeof line, stdin)) {
        if (sscanf(line, "%255s", in) != 1 || in[0] != 'x') {
            fprintf(stderr, "bad line: %s", line);
            return 1;
        }
        size_t n = 0;
        for (const char *p = in + 1; p[0] && p[1]; p += 2) {
            char byte[3] = {p[0], p[1], 0};
            text[n++] = (char)strtol(byte, NULL, 16);
        }
        printf("%s", in);
        int32_t v;
        if (jnum_parse_int(text, n, &v)) {
            printf(" %" PRId32, v);
        } else {
            printf(" ERR");
        }
        int64_t w;
        if (jnum_parse_long(text, n, &w)) {
            printf(" %" PRId64 "\n", w);
        } else {
            printf(" ERR\n");
        }
    }
    return 0;
}
