/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "jrandom.h"

#include <stdio.h>
#include <stdlib.h>

#define MULTIPLIER 0x5DEECE66DULL
#define ADDEND 0xBULL
#define MASK ((1ULL << 48) - 1)

void jrandom_init(jrandom *r, int64_t seed) {
    r->seed = ((uint64_t)seed ^ MULTIPLIER) & MASK;
}

static int32_t next(jrandom *r, int bits) {
    r->seed = (r->seed * MULTIPLIER + ADDEND) & MASK;
    return (int32_t)(uint32_t)(r->seed >> (48 - bits));
}

int32_t jrandom_next_int(jrandom *r) {
    return next(r, 32);
}

int32_t jrandom_next_int_bound(jrandom *r, int32_t bound) {
    if (bound <= 0) {
        fprintf(stderr, "jrandom_next_int_bound: bound must be positive: %d\n", bound);
        abort();
    }
    int32_t m = bound - 1;
    if ((bound & m) == 0) {
        return (int32_t)(((int64_t)bound * next(r, 31)) >> 31);
    }
    /* Java rejects u while u - u % bound + m overflows int. */
    int32_t u = next(r, 31);
    int32_t x = u % bound;
    while ((int32_t)((uint32_t)u - (uint32_t)x + (uint32_t)m) < 0) {
        u = next(r, 31);
        x = u % bound;
    }
    return x;
}

int64_t jrandom_next_long(jrandom *r) {
    uint64_t hi = (uint64_t)(int64_t)next(r, 32) << 32;
    return (int64_t)(hi + (uint64_t)(int64_t)next(r, 32));
}

bool jrandom_next_boolean(jrandom *r) {
    return next(r, 1) != 0;
}
