/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef JCOMPAT_JRANDOM_H
#define JCOMPAT_JRANDOM_H

#include <stdbool.h>
#include <stdint.h>

/* java.util.Random: the same 48-bit linear congruential generator and the
 * same derived methods, so a given seed yields Java's exact sequence. */
typedef struct {
    uint64_t seed;
} jrandom;

void jrandom_init(jrandom *r, int64_t seed);  /* new Random(seed) and setSeed(seed) */
int32_t jrandom_next_int(jrandom *r);
int32_t jrandom_next_int_bound(jrandom *r, int32_t bound);
int64_t jrandom_next_long(jrandom *r);
bool jrandom_next_boolean(jrandom *r);

/* The Java long seed + offset, which wraps; signed overflow is undefined in C. */
static inline int64_t jrandom_seed_plus(int64_t seed, int64_t offset) {
    return (int64_t)((uint64_t)seed + (uint64_t)offset);
}

#endif
