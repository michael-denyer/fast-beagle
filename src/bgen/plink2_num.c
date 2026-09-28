/*
 * Copyright (C) 2005-2026 Shaun Purcell, Christopher Chang
 * Ported to C from PLINK 2.0 v2.0.0-a.7.8 include/plink2_string.cc
 * (ScanadvDouble, dtoa_g); modified 2026.
 *
 * This file is part of beagle-c, a C port of Beagle. It is free software:
 * you can redistribute it and/or modify it under the terms of the GNU General
 * Public License as published by the Free Software Foundation, either version 3
 * of the License, or (at your option) any later version. See LICENSE.
 */
#include "bgen/plink2_num.h"

#include <stdbool.h>
#include <stdint.h>

#include "blbutil/utilities.h"

static const double POS_POW10[] = {1, 1.0e1, 1.0e2, 1.0e3, 1.0e4, 1.0e5, 1.0e6, 1.0e7, 1.0e8, 1.0e9, 1.0e10, 1.0e11,
        1.0e12, 1.0e13, 1.0e14, 1.0e15};
static const double POS_POW10_16[] = {1, 1.0e16, 1.0e32, 1.0e48, 1.0e64, 1.0e80, 1.0e96, 1.0e112, 1.0e128, 1.0e144,
        1.0e160, 1.0e176, 1.0e192, 1.0e208, 1.0e224, 1.0e240};
static const double NEG_POW10[] = {1, 1.0e-1, 1.0e-2, 1.0e-3, 1.0e-4, 1.0e-5, 1.0e-6, 1.0e-7, 1.0e-8, 1.0e-9, 1.0e-10,
        1.0e-11, 1.0e-12, 1.0e-13, 1.0e-14, 1.0e-15};
static const double NEG_POW10_16[] = {1, 1.0e-16, 1.0e-32, 1.0e-48, 1.0e-64, 1.0e-80, 1.0e-96, 1.0e-112};

/* The next character minus '0': below 10 for a digit, 0xfffffffe for '.'. */
static uint32_t next_digit(const char **s) {
    return (uint32_t)(unsigned char)*++*s - 48u;
}

/* The LP64 branch. */
const char *plink2_scanadv_double(const char *s, double *value) {
    uint32_t c = (unsigned char)*s;
    bool neg = c == '-';
    if (neg || c == '+') c = (unsigned char)*++s;
    uint32_t digit = c - 48u;
    int64_t e10 = 0;
    const char *dot = NULL;
    int64_t digits;
    if (digit < 10) {
        digits = digit;
        do {
            digit = next_digit(&s);
            if (digit >= 10) {
                if (digit == 0xfffffffeU) {
                    dot = s;
                    goto parse_decimal;
                }
                goto parse_exponent;
            }
            digits = digits * 10 + digit;
        } while (digits < 10000000000000000LL);
        /* 17 significant digits: count the rest without reading them */
        const char *last_sig = s;
        do digit = next_digit(&s);
        while (digit < 10);
        e10 = (s - last_sig) - 1;
        if (digit == 0xfffffffeU) {
            do digit = next_digit(&s);
            while (digit < 10);
        }
        goto parse_exponent;
    }
    if (digit != 0xfffffffeU) return NULL;
    dot = s;
    digit = next_digit(&s);
    if (digit >= 10) return NULL;
    digits = digit;
parse_decimal:
    for (;;) {
        digit = next_digit(&s);
        if (digit >= 10) {
            e10 = 1 - (s - dot);
            break;
        }
        digits = digits * 10 + digit;
        if (digits >= 10000000000000000LL) {
            e10 = -(s - dot);
            do digit = next_digit(&s);
            while (digit < 10);
            break;
        }
    }
parse_exponent:
    if ((digit & 0xdf) == 21) {  /* 'E' or 'e' */
        c = (unsigned char)*++s;
        bool exp_neg = c == '-';
        if (exp_neg || c == '+') c = (unsigned char)*++s;
        digit = c - 48u;
        int32_t exp = 0;
        while (digit < 10) {
            if (exp >= 214748364) {
                if (!exp_neg) return NULL;
                *value = 0;
                do digit = next_digit(&s);
                while (digit < 10);
                return s;
            }
            exp = exp * 10 + (int32_t)digit;
            digit = next_digit(&s);
        }
        e10 += exp_neg ? -exp : exp;
    }
    if (digits == 0) {
        *value = 0;
        return s;
    }
    if (neg) digits = -digits;
    double x = (double)digits;
    if (e10 < 0) {
        uint32_t p = (uint32_t)-e10;
        x *= NEG_POW10[p & 15];
        p /= 16;
        if (p) {
            x *= NEG_POW10_16[p & 7];
            if (p > 7) {
                if (p > 23) x = 0;
                else if (p > 15) x *= 1.0e-256;
                else x *= 1.0e-128;
            }
        }
    } else if (e10 > 0) {
        uint32_t p = (uint32_t)e10;
        x *= POS_POW10[p & 15];
        p /= 16;
        if (p) {
            x *= POS_POW10_16[p & 15];
            if (p > 15) {
                if (p > 31 || x > 1.7976931348623154e52) return NULL;
                x *= 1.0e256;
            }
        }
    }
    *value = x;
    return s;
}

/* kBankerRound8 */
static const double BANKER_ROUND8[2] = {0.499999995, 0.500000005};

static uint32_t banker_round(double x) {
    uint32_t result = (uint32_t)(int32_t)x;
    return result + (uint32_t)(int32_t)((x - (double)(int32_t)result) + BANKER_ROUND8[result & 1]);
}

/* BankerRoundD5 */
static void banker_round5(double x, uint32_t *quotient, uint32_t *remainder) {
    uint32_t r = banker_round(x * 100000);
    *quotient = r / 100000;
    *remainder = r - *quotient * 100000;
}

static char *put_pair(char *s, uint32_t v) {
    s[0] = (char)('0' + v / 10);
    s[1] = (char)('0' + v % 10);
    return s;
}

/* The end of the last pair written at s, dropping its trailing zero. */
static char *trim_pair(char *s) {
    return s[1] != '0' ? s + 2 : s + 1;
}

/* rtoa_p5 via qrtoa_1p5: one digit, then up to five decimals. */
static char *qrtoa_1p5(uint32_t quotient, uint32_t remainder, char *s) {
    *s++ = (char)('0' + quotient);
    if (!remainder) return s;
    *s++ = '.';
    uint32_t q = remainder / 1000;
    put_pair(s, q);
    remainder -= 1000 * q;
    if (remainder) {
        q = remainder / 10;
        s += 2;
        put_pair(s, q);
        remainder -= 10 * q;
        if (remainder) {
            s[2] = (char)('0' + remainder);
            return s + 3;
        }
    }
    return trim_pair(s);
}

/* uitoa_trunc6 */
static char *uitoa_trunc6(uint32_t v, char *s) {
    uint32_t q = v / 10000;
    put_pair(s, q);
    v -= 10000 * q;
    if (v) {
        q = v / 100;
        s += 2;
        put_pair(s, q);
        v -= 100 * q;
        if (v) {
            s += 2;
            put_pair(s, v);
        }
    }
    return trim_pair(s);
}

/* dtoa_g, keeping the branches that 0 <= x <= 1 reaches. */
void plink2_dtoa_g_unit(double x, char *buf) {
    if (!(x >= 0.0 && x <= 1.0)) util_exit("plink2_dtoa_g_unit: %g is outside [0, 1]", x);
    char *s = buf;
    uint32_t quotient, remainder;
    if (x == 0.0) {
        *s++ = '0';
    } else if (x < 9.9999949999999e-5) {
        uint32_t xp10 = 0;
        if (x < 9.9999949999999e-16) {
            if (x < 9.9999949999999e-128) {
                if (x < 9.9999949999999e-256) {
                    x *= 1.0e256;
                    xp10 |= 256;
                } else {
                    x *= 1.0e128;
                    xp10 |= 128;
                }
            }
            if (x < 9.9999949999999e-64) {
                x *= 1.0e64;
                xp10 |= 64;
            }
            if (x < 9.9999949999999e-32) {
                x *= 1.0e32;
                xp10 |= 32;
            }
            if (x < 9.9999949999999e-16) {
                x *= 1.0e16;
                xp10 |= 16;
            }
        }
        if (x < 9.9999949999999e-8) {
            x *= 100000000;
            xp10 |= 8;
        }
        if (x < 9.9999949999999e-4) {
            x *= 10000;
            xp10 |= 4;
        }
        if (x < 9.9999949999999e-2) {
            x *= 100;
            xp10 |= 2;
        }
        if (x < 9.9999949999999e-1) {
            x *= 10;
            ++xp10;
        }
        banker_round5(x, &quotient, &remainder);
        s = qrtoa_1p5(quotient, remainder, s);
        *s++ = 'e';
        *s++ = '-';
        if (xp10 >= 100) {
            quotient = xp10 / 100;
            *s++ = (char)('0' + quotient);
            xp10 -= 100 * quotient;
        }
        s = put_pair(s, xp10) + 2;
    } else if (x >= 0.99999949999999) {
        /* dtoa_so6 for x below 9.9999949999999 */
        banker_round5(x, &quotient, &remainder);
        s = qrtoa_1p5(quotient, remainder, s);
    } else {
        *s++ = '0';
        *s++ = '.';
        if (x < 9.9999949999999e-3) {
            x *= 100;
            *s++ = '0';
            *s++ = '0';
        }
        if (x < 9.9999949999999e-2) {
            x *= 10;
            *s++ = '0';
        }
        s = uitoa_trunc6(banker_round(x * 1000000), s);
    }
    *s = '\0';
}
