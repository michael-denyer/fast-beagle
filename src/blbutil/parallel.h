/*
 * This file is part of fast-beagle, a C port of Beagle. It is free software:
 * you can redistribute it and/or modify it under the terms of the GNU General
 * Public License as published by the Free Software Foundation, either version 3
 * of the License, or (at your option) any later version. See LICENSE.
 */
#ifndef BLBUTIL_PARALLEL_H
#define BLBUTIL_PARALLEL_H

#include <stddef.h>

/* Threads for n_items independent items: nthreads capped at n_items, at
 * least 1. Only the thread count: a partition that the output depends on
 * keeps using par->nthreads. */
static inline int parallel_threads(int nthreads, int n_items) {
    int n = nthreads < n_items ? nthreads : n_items;
    return n > 0 ? n : 1;
}

/* Thread t's worker context is (char *)workers + t * worker_size, so workers
 * is an array of n_threads typed contexts; worker_size 0 gives every thread
 * the same context. */
typedef void (*parallel_fn)(void *worker, int item);

/* Runs fn(worker, item) for every item in [0, n_items) on up to n_threads
 * threads, which take items in any order. Each thread uses its own worker
 * context, so the results must not depend on which thread runs an item.
 * With one thread it runs in item order on the calling thread. */
void parallel_for(int n_threads, int n_items, void *workers, size_t worker_size, parallel_fn fn);

/* Runs build(worker, item) for every item in [0, n_items) on n_threads new
 * threads, which claim items in increasing order, while the calling thread
 * runs consume(ctx, item) in item order as soon as each item is built. No
 * thread starts item i until i < (items consumed) + window, so at most
 * window items are built or building but not consumed, and the caller can
 * keep item i's results in slot i % window. tla/ParallelOrdered.tla models
 * this protocol (tests/check-tla.sh); change both together. */
void parallel_ordered(int n_threads, int n_items, int window, void *workers, size_t worker_size, parallel_fn build,
        void *ctx, parallel_fn consume);

#endif
