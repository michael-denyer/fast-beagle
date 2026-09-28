/* The chrom= interval over a record source, through an in-memory source. */
#include <assert.h>
#include <stdio.h>

#include "vcf/interval_it.h"

typedef struct {
    marker marker;
    bool released;
} rec;

typedef struct {
    rec *recs;
    int n, n_read;
    samples smp;
    bool closed;
} array_it;

static const samples *array_samples(const void *self) {
    return &((const array_it *)self)->smp;
}

static void *array_next(void *self) {
    array_it *it = self;
    return it->n_read < it->n ? &it->recs[it->n_read++] : NULL;
}

static void array_close(void *self) {
    ((array_it *)self)->closed = true;
}

static const marker *rec_marker(const void *r) {
    return &((const rec *)r)->marker;
}

static void rec_release(void *r) {
    ((rec *)r)->released = true;
}

static const sample_file_it_ops array_ops = {.samples = array_samples, .next = array_next, .close = array_close,
        .marker = rec_marker, .release = rec_release};

static rec at(int chrom, int32_t pos) {
    return (rec){.marker = {.chrom_index = chrom, .pos = pos}};
}

int main(void) {
    rec recs[] = {at(0, 5), at(0, 10), at(0, 20), at(0, 30), at(0, 40), at(1, 1)};
    array_it src = {.recs = recs, .n = 6};
    chrom_interval ci = {.chrom_index = 0, .start = 10, .end = 30};
    sample_file_it it = interval_it_open((sample_file_it){&array_ops, &src}, &ci);
    assert(src.n_read == 2);
    assert(recs[0].released);
    assert(sample_file_it_samples(it) == &src.smp);
    assert(sample_file_it_next(it) == &recs[1]);
    assert(sample_file_it_next(it) == &recs[2]);
    assert(sample_file_it_next(it) == &recs[3]);
    assert(src.n_read == 5);
    assert(recs[4].released);
    assert(sample_file_it_next(it) == NULL);
    assert(sample_file_it_next(it) == NULL);
    assert(src.n_read == 5);
    assert(!recs[1].released && !recs[2].released && !recs[3].released);
    sample_file_it_close(it);
    assert(src.closed);
    puts("PASS records before the interval are skipped and the first one after it ends the stream");

    rec back[] = {at(0, 10), at(0, 20), at(1, 15), at(0, 25)};
    array_it back_src = {.recs = back, .n = 4};
    it = interval_it_open((sample_file_it){&array_ops, &back_src}, &ci);
    assert(sample_file_it_next(it) == &back[0]);
    assert(sample_file_it_next(it) == &back[1]);
    assert(sample_file_it_next(it) == NULL);
    assert(back_src.n_read == 3);
    assert(back[2].released && !back[3].released);
    sample_file_it_close(it);
    puts("PASS a record back in the interval after one outside it is never read");

    rec all[] = {at(0, 5), at(1, 1), at(0, 3)};
    array_it all_src = {.recs = all, .n = 3};
    it = interval_it_open((sample_file_it){&array_ops, &all_src}, NULL);
    assert(it.it == &all_src && all_src.n_read == 0);
    for (int j = 0; j < 3; ++j) assert(sample_file_it_next(it) == &all[j]);
    assert(sample_file_it_next(it) == NULL);
    sample_file_it_close(it);
    assert(all_src.closed);
    puts("PASS no interval passes every record through");

    rec end[] = {at(0, 5), at(0, 30)};
    array_it end_src = {.recs = end, .n = 2};
    ci = (chrom_interval){.chrom_index = 0, .start = INT32_MIN, .end = INT32_MAX};
    it = interval_it_open((sample_file_it){&array_ops, &end_src}, &ci);
    assert(sample_file_it_next(it) == &end[0]);
    assert(end_src.n_read == 2);
    sample_file_it_close(it);
    assert(end[1].released && end_src.closed);
    puts("PASS close releases the lookahead and closes the source");
    return 0;
}
