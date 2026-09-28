/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "jcompat/jutf8.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static bool not_cont(unsigned b) {
    return (b & 0xc0) != 0x80;
}

/* Bytes one replacement consumes for a bad 3- or 4-byte sequence. */
static size_t bad3_len(unsigned b1, unsigned b2) {
    return ((b1 == 0xe0 && (b2 & 0xe0) == 0x80) || not_cont(b2)) ? 1 : 2;
}

static bool bad4_2(unsigned b1, unsigned b2) {
    return (b1 == 0xf0 && (b2 < 0x90 || b2 > 0xbf)) || (b1 == 0xf4 && (b2 & 0xf0) != 0x80) || not_cont(b2);
}

static size_t bad4_len(unsigned b1, unsigned b2, unsigned b3) {
    if (b1 > 0xf4 || bad4_2(b1, b2)) return 1;
    return not_cont(b3) ? 2 : 3;
}

void jutf8_sanitize(kstring_t *s) {
    const unsigned char *b = (const unsigned char *)s->s;
    size_t n = s->l, i = 0;
    for (uint64_t w; i + 8 <= n; i += 8) {
        memcpy(&w, b + i, 8);
        if ((w & 0x8080808080808080u) != 0) break;
    }
    while (i < n && b[i] < 0x80) ++i;
    if (i == n) return;

    kstring_t out = {0, 0, NULL};
    kputsn(s->s, i, &out);
    static const char REPL[] = "\xef\xbf\xbd";
    while (i < n) {
        unsigned b1 = b[i];
        if (b1 < 0x80) {
            kputc((int)b1, &out);
            ++i;
        } else if (b1 >= 0xc2 && b1 <= 0xdf) {
            if (i + 1 >= n) {
                kputs(REPL, &out);
                break;
            }
            if (not_cont(b[i + 1])) {
                kputs(REPL, &out);
                i += 1;
            } else {
                kputsn(s->s + i, 2, &out);
                i += 2;
            }
        } else if (b1 >= 0xe0 && b1 <= 0xef) {
            if (i + 2 < n) {
                unsigned b2 = b[i + 1], b3 = b[i + 2];
                if ((b1 == 0xe0 && (b2 & 0xe0) == 0x80) || not_cont(b2) || not_cont(b3)) {
                    kputs(REPL, &out);
                    i += bad3_len(b1, b2);
                } else {
                    if (b1 == 0xed && b2 >= 0xa0) kputs(REPL, &out);  /* a surrogate */
                    else kputsn(s->s + i, 3, &out);
                    i += 3;
                }
            } else {
                kputs(REPL, &out);
                if (i + 1 < n && bad3_len(b1, b[i + 1]) == 1) {
                    i += 1;
                } else {
                    break;
                }
            }
        } else if (b1 >= 0xf0 && b1 <= 0xf7) {
            if (i + 3 < n) {
                unsigned b2 = b[i + 1], b3 = b[i + 2], b4 = b[i + 3];
                unsigned uc = ((b1 & 0x07) << 18) | ((b2 & 0x3f) << 12) | ((b3 & 0x3f) << 6) | (b4 & 0x3f);
                if (not_cont(b2) || not_cont(b3) || not_cont(b4) || uc < 0x10000 || uc > 0x10ffff) {
                    kputs(REPL, &out);
                    i += bad4_len(b1, b2, b3);
                } else {
                    kputsn(s->s + i, 4, &out);
                    i += 4;
                }
            } else {
                kputs(REPL, &out);
                if (b1 > 0xf4 || (i + 1 < n && bad4_2(b1, b[i + 1]))) {
                    i += 1;
                } else if (i + 2 < n && not_cont(b[i + 2])) {
                    i += 2;
                } else {
                    break;
                }
            }
        } else {
            kputs(REPL, &out);
            i += 1;
        }
    }
    free(s->s);
    *s = out;
}

int32_t jutf8_next_bmp(const char *s, size_t len, size_t *i) {
    const unsigned char *b = (const unsigned char *)s + *i;
    size_t rem = len - *i;
    if (b[0] < 0x80) {
        *i += 1;
        return b[0];
    }
    if (b[0] >= 0xc2 && b[0] <= 0xdf && rem >= 2 && !not_cont(b[1])) {
        *i += 2;
        return ((b[0] & 0x1f) << 6) | (b[1] & 0x3f);
    }
    if (b[0] >= 0xe0 && b[0] <= 0xef && rem >= 3 && !not_cont(b[1]) && !not_cont(b[2])
            && !(b[0] == 0xe0 && b[1] < 0xa0) && !(b[0] == 0xed && b[1] >= 0xa0)) {
        *i += 3;
        return ((b[0] & 0x0f) << 12) | ((b[1] & 0x3f) << 6) | (b[2] & 0x3f);
    }
    return -1;
}
