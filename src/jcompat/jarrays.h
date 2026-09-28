/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef JCOMPAT_JARRAYS_H
#define JCOMPAT_JARRAYS_H

#include <stdint.h>

/* Arrays.binarySearch(a, from, to, key) over a sorted int[]: the index of a
 * matching element, else -(insertion point) - 1. The probe order is Java's, so
 * among equal elements the same one is found. */
static inline int jarrays_search_int(const int32_t *a, int from, int to, int32_t key) {
    int low = from, high = to - 1;
    while (low <= high) {
        int mid = (int)((unsigned)(low + high) >> 1);
        if (a[mid] < key) low = mid + 1;
        else if (a[mid] > key) high = mid - 1;
        else return mid;
    }
    return -(low + 1);
}

#endif
