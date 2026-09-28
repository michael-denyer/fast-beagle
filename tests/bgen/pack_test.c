/*
 * bgen_pack_bits: values packed little-endian at 1 to 16 bits each, crossing
 * byte boundaries, with zero padding after the last value and nothing
 * written past the last byte.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "bgen/bgen_writer.h"

static int failures;

static void check(const char *name, const uint32_t *v, size_t n, int bits, const uint8_t *want, size_t want_len) {
    uint8_t got[16];
    memset(got, 0xaa, sizeof got);
    bgen_pack_bits(v, n, bits, got);
    for (size_t k = 0; k < sizeof got; ++k) {
        uint8_t w = k < want_len ? want[k] : 0xaa;
        if (got[k] != w) {
            printf("FAIL %s: byte %zu is 0x%02x, want 0x%02x\n", name, k, got[k], w);
            ++failures;
            return;
        }
    }
    printf("pass %s\n", name);
}

int main(void) {
    check("1 bit", (const uint32_t[]){1, 0, 1, 1, 0, 0, 0, 1, 1, 0, 1}, 11, 1, (const uint8_t[]){0x8d, 0x05}, 2);
    /* 5 | 7 << 3 | 2 << 6 | 1 << 9 = 0x2bd: the third value spans both bytes */
    check("3 bits", (const uint32_t[]){5, 7, 2, 1}, 4, 3, (const uint8_t[]){0xbd, 0x02}, 2);
    check("8 bits", (const uint32_t[]){0x12, 0xff, 0}, 3, 8, (const uint8_t[]){0x12, 0xff, 0x00}, 3);
    /* 0xabc | 0x123 << 12 | 0xfff << 24 = 0xfff123abc in 36 bits */
    check("12 bits", (const uint32_t[]){0xabc, 0x123, 0xfff}, 3, 12, (const uint8_t[]){0xbc, 0x3a, 0x12, 0xff, 0x0f}, 5);
    check("16 bits", (const uint32_t[]){0x1234, 0xffff, 1}, 3, 16, (const uint8_t[]){0x34, 0x12, 0xff, 0xff, 0x01, 0x00}, 6);
    check("no values", (const uint32_t[]){0}, 0, 12, NULL, 0);
    return failures != 0;
}
