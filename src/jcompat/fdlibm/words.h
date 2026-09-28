/* Word access for the fdlibm sources, replacing fdlibm.h's pointer-cast macros,
 * which assume an endianness and break strict aliasing. */
#ifndef JCOMPAT_FDLIBM_WORDS_H
#define JCOMPAT_FDLIBM_WORDS_H

#include <math.h>
#include <stdint.h>
#include <string.h>

#include "jcompat/jmath.h"

static inline uint64_t fdlibm_bits(double x) {
    uint64_t b;
    memcpy(&b, &x, sizeof b);
    return b;
}

static inline double fdlibm_double(uint64_t b) {
    double x;
    memcpy(&x, &b, sizeof x);
    return x;
}

#define GET_HI(x) ((int32_t)(fdlibm_bits(x) >> 32))
#define GET_LO(x) ((int32_t)(uint32_t)fdlibm_bits(x))
#define SET_HI(x, v) ((x) = fdlibm_double((fdlibm_bits(x) & 0xffffffffULL) | ((uint64_t)(uint32_t)(v) << 32)))
#define SET_LO(x, v) ((x) = fdlibm_double((fdlibm_bits(x) & ~0xffffffffULL) | (uint32_t)(v)))

#endif
