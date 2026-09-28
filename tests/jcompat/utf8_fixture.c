/* Reads the output of JcompatFixtures.utf8() and prints it again, recomputing
 * both decodings with jutf8_sanitize. */
#include <stdio.h>
#include <stdlib.h>

#include "jcompat/jutf8.h"

static void print_hex(const kstring_t *s) {
    putchar('x');
    for (size_t j = 0; j < s->l; ++j) printf("%02x", (unsigned char)s->s[j]);
}

int main(void) {
    char in[64], line[256];
    while (fgets(line, sizeof line, stdin)) {
        if (sscanf(line, "%63s", in) != 1 || in[0] != 'x') {
            fprintf(stderr, "bad line: %s", line);
            return 1;
        }
        kstring_t s = {0, 0, NULL};
        kputsn("", 0, &s);
        for (const char *p = in + 1; p[0] && p[1]; p += 2) {
            char byte[3] = {p[0], p[1], 0};
            kputc((int)strtol(byte, NULL, 16), &s);
        }
        jutf8_sanitize(&s);
        printf("%s ", in);
        print_hex(&s);
        putchar(' ');
        print_hex(&s);
        putchar('\n');
        free(s.s);
    }
    return 0;
}
