/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef BLBUTIL_INT_LIST_H
#define BLBUTIL_INT_LIST_H

#include "blbutil/utilities.h"

/* A growable int array, as Beagle's ints.IntList. Zero-initialise to start empty. */
typedef struct {
    int *v;
    int n, cap;
} int_list;

static inline void int_list_add(int_list *l, int x) {
    if (l->n == l->cap) {
        l->cap = l->cap == 0 ? 8 : 2 * l->cap;
        l->v = util_realloc(l->v, (size_t)l->cap * sizeof *l->v);
    }
    l->v[l->n++] = x;
}

#endif
