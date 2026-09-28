/*
 * Copyright (C) 2014-2021 Brian L. Browning
 * Ported to C from Beagle 5.5 (27Feb25) blbutil/Utilities.java; modified 2026.
 *
 * This file is part of fast-beagle, a C port of Beagle. It is free software:
 * you can redistribute it and/or modify it under the terms of the GNU General
 * Public License as published by the Free Software Foundation, either version 3
 * of the License, or (at your option) any later version. See LICENSE.
 */
#include "blbutil/utilities.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void util_exit(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(1);
}

void *util_malloc(size_t size) {
    void *p = malloc(size == 0 ? 1 : size);
    if (p == NULL) util_exit("ERROR: out of memory");
    return p;
}

void *util_realloc(void *p, size_t size) {
    p = realloc(p, size == 0 ? 1 : size);
    if (p == NULL) util_exit("ERROR: out of memory");
    return p;
}

char *util_strndup(const char *s, size_t n) {
    char *d = util_malloc(n + 1);
    memcpy(d, s, n);
    d[n] = '\0';
    return d;
}

int util_compare_ints(const void *a, const void *b) {
    int x = *(const int *)a, y = *(const int *)b;
    return (x > y) - (x < y);
}

void util_shuffle(int *a, int n, int n_elements, jrandom *r) {
    for (int j = 0; j < n_elements; ++j) {
        int x = jrandom_next_int_bound(r, n - j);
        int tmp = a[j];
        a[j] = a[j + x];
        a[j + x] = tmp;
    }
}
