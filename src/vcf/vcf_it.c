/*
 * Copyright (C) 2014-2021 Brian L. Browning
 * Ported to C from Beagle 5.5 (27Feb25) vcf/VcfIt.java; modified 2026.
 *
 * This file is part of fast-beagle, a C port of Beagle. It is free software:
 * you can redistribute it and/or modify it under the terms of the GNU General
 * Public License as published by the Free Software Foundation, either version 3
 * of the License, or (at your option) any later version. See LICENSE.
 */
#include "vcf/vcf_it.h"

#include <stdlib.h>

#include "blbutil/line_reader.h"
#include "blbutil/trace.h"
#include "blbutil/utilities.h"
#include "vcf/filter_util.h"
#include "vcf/gt_rec.h"
#include "vcf/vcf_header.h"

typedef struct {
    line_reader *reader;
    vcf_header header;
    const str_set *exclude;
    kstring_t line;
    bool have_line;     /* line holds the next unparsed data line */
} vcf_it;

void vcf_it_trace_marker(const char *seam, const marker *m) {
    span id = marker_id(m), al = marker_alleles(m), end = marker_end_value(m);
    trace_line(seam, "%s\t%d\t%.*s\t%.*s\t%d\t%.*s", marker_chrom(m), m->pos, id.n, id.s, al.n, al.s,
            marker_n_alleles(m), end.n, end.s);
}

/* VcfIt.readLine skips blank lines, except a final one. */
static bool is_blank(const kstring_t *s) {
    for (size_t j = 0; j < s->l; ++j) {
        if ((unsigned char)s->s[j] > ' ') return false;
    }
    return true;
}

static void read_line(vcf_it *it) {
    it->have_line = line_reader_next(it->reader, &it->line);
    kstring_t probe = {0, 0, NULL};
    while (it->have_line && is_blank(&it->line)) {
        if (!line_reader_next(it->reader, &probe)) break;
        kstring_t tmp = it->line;
        it->line = probe;
        probe = tmp;
    }
    free(probe.s);
}

static void trace_rec(const gt_rec *rec) {
    vcf_it_trace_marker("T1a-target", &rec->marker);
    kstring_t s = {0, 0, NULL};
    ksprintf(&s, "%s\t%s\t", gt_rec_class_name(rec), rec->is_phased ? "true" : "false");
    for (int h = 0; h < rec->n_haps; ++h) {
        int a = gt_rec_get(rec, h);
        if (h > 0) kputc(',', &s);
        if (a < 0) kputc('.', &s);
        else kputw(a, &s);
    }
    trace_line("T1c-target", "%s", s.s);
    free(s.s);
}

/* VcfIt.next: the next record that passes the marker filter. */
static void *vcf_it_next(void *self) {
    vcf_it *it = self;
    while (it->have_line) {
        gt_rec *rec = util_malloc(sizeof *rec);
        gt_rec_parse(rec, it->line.s, it->line.l, &it->header);
        rec->refs = 1;
        read_line(it);
        if (filter_accept_marker(it->exclude, &rec->marker)) {
            if (trace_on()) trace_rec(rec);
            return rec;
        }
        gt_rec_release(rec);
    }
    return NULL;
}

static const samples *vcf_it_samples(const void *self) {
    const vcf_it *it = self;
    return &it->header.samples;
}

static void vcf_it_close(void *self) {
    vcf_it *it = self;
    vcf_header_free(&it->header);
    free(it->line.s);
    line_reader_close(it->reader);
    free(it);
}

static const marker *rec_marker(const void *rec) {
    return &((const gt_rec *)rec)->marker;
}

static void rec_release(void *rec) {
    gt_rec_release(rec);
}

static const sample_file_it_ops vcf_it_ops = {.samples = vcf_it_samples, .next = vcf_it_next, .close = vcf_it_close,
        .marker = rec_marker, .release = rec_release};

sample_file_it vcf_it_open(const char *path, const str_set *exclude_samples, const str_set *exclude_markers,
        int n_threads) {
    vcf_it *it = util_malloc(sizeof *it);
    *it = (vcf_it){0};
    it->reader = line_reader_open(path, n_threads);
    it->exclude = exclude_markers;
    vcf_header_read(&it->header, it->reader, &it->line, exclude_samples);
    it->have_line = true;
    if (trace_on()) vcf_header_trace(&it->header, "T1b-target");
    return (sample_file_it){&vcf_it_ops, it};
}
