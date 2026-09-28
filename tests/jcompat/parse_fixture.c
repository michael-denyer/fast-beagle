/* Reads the output of JcompatFixtures.parse() and prints it again, recomputing
 * both parses with jnum. */
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
        printf("%s ", in);
        double d;
        if (jnum_parse_double(text, n, &d)) {
            uint64_t b;
            memcpy(&b, &d, sizeof b);
            printf("%" PRIx64, b);
        } else {
            printf("ERR");
        }
        float f;
        if (jnum_parse_float(text, n, &f)) {
            uint32_t b;
            memcpy(&b, &f, sizeof b);
            printf(" %" PRIx32 "\n", b);
        } else {
            printf(" ERR\n");
        }
    }
    return 0;
}
