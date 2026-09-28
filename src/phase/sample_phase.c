/*
 * Copyright (C) 2014-2021 Brian L. Browning
 * Ported to C from Beagle 5.5 (27Feb25) phase/SamplePhase.java; modified 2026.
 *
 * This file is part of fast-beagle, a C port of Beagle. It is free software:
 * you can redistribute it and/or modify it under the terms of the GNU General
 * Public License as published by the Free Software Foundation, either version 3
 * of the License, or (at your option) any later version. See LICENSE.
 */
#include "phase/sample_phase.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "blbutil/bit_array.h"
#include "blbutil/int_list.h"
#include "blbutil/utilities.h"

static const float MAX_CLUSTER_CM = 0.005f;

/* Markers.allelesToBits */
static uint64_t *alleles_to_bits(const fixed_phase_data *fpd, const int *alleles) {
    const int *hap_bits = fpd->stage1_hap_bits;
    uint64_t *bits = bit_array_new((size_t)hap_bits[fpd->n_stage1]);
    for (int m = 0; m < fpd->n_stage1; ++m) bit_array_set_allele(bits, hap_bits, m, alleles[m]);
    return bits;
}

static clust_type type_of(bool is_missing, bool is_unphased, int a1, int a2) {
    if (is_missing) return CLUST_MISSING_GT;
    if (a1 == a2) return CLUST_HOMOZYGOUS_GT;
    return is_unphased ? CLUST_UNPHASED_HET : CLUST_PHASED_HET;
}

static void set_clusters(sample_phase *sp, const fixed_phase_data *fpd, const int *hap1, const int *hap2,
        const int *unph_hets, int n_unph_hets, const int *missing, int n_missing) {
    const double *gen_pos = fpd->stage1_map.gen_pos;
    int n_markers = fpd->n_stage1;
    int_list types = {0};
    int_list sizes = {0};
    double max_clust_end = gen_pos[0] + (double)MAX_CLUSTER_CM;
    bool prev_is_missing_or_het = false;
    int last_end = 0;
    int miss_index = 0;
    int unph_index = 0;
    int next_miss = miss_index < n_missing ? missing[miss_index++] : -1;
    int next_unph = unph_index < n_unph_hets ? unph_hets[unph_index++] : -1;
    clust_type prev_type = CLUST_HOMOZYGOUS_GT;
    for (int m = 0; m < n_markers; ++m) {
        int size = m - last_end;
        clust_type type = type_of(m == next_miss, m == next_unph, hap1[m], hap2[m]);
        if (type == CLUST_MISSING_GT) {
            next_miss = miss_index < n_missing ? missing[miss_index++] : -1;
        } else if (type == CLUST_UNPHASED_HET) {
            next_unph = unph_index < n_unph_hets ? unph_hets[unph_index++] : -1;
        }
        bool is_missing_or_het = type == CLUST_MISSING_GT || type == CLUST_UNPHASED_HET || type == CLUST_PHASED_HET;
        if (is_missing_or_het || prev_is_missing_or_het || gen_pos[m] > max_clust_end || size == 255) {
            if (m > 0) {
                int_list_add(&types, (int)prev_type);
                ++sp->clust_type_cnt[prev_type];
                int_list_add(&sizes, size);
                max_clust_end = gen_pos[m] + (double)MAX_CLUSTER_CM;
                last_end = m;
            }
            prev_type = type;
        }
        prev_is_missing_or_het = is_missing_or_het;
    }
    int_list_add(&types, (int)prev_type);
    ++sp->clust_type_cnt[prev_type];
    int_list_add(&sizes, n_markers - last_end);

    sp->n_clusters = types.n;
    sp->clust_type = util_malloc((size_t)types.n * sizeof *sp->clust_type);
    sp->clust_size = util_malloc((size_t)sizes.n * sizeof *sp->clust_size);
    for (int c = 0; c < types.n; ++c) {
        sp->clust_type[c] = (uint8_t)types.v[c];
        sp->clust_size[c] = (uint8_t)sizes.v[c];
    }
    free(types.v);
    free(sizes.v);
}

void sample_phase_init(sample_phase *sp, int sample, const fixed_phase_data *fpd, const int *hap1, const int *hap2,
        const int *unph_hets, int n_unph_hets, const int *missing, int n_missing) {
    sp->sample = sample;
    sp->fpd = fpd;
    sp->hap1 = alleles_to_bits(fpd, hap1);
    sp->hap2 = alleles_to_bits(fpd, hap2);
    memset(sp->clust_type_cnt, 0, sizeof sp->clust_type_cnt);
    set_clusters(sp, fpd, hap1, hap2, unph_hets, n_unph_hets, missing, n_missing);
}

int sample_phase_allele1(const sample_phase *sp, int m) {
    return bit_array_allele(sp->hap1, sp->fpd->stage1_hap_bits, m);
}

int sample_phase_allele2(const sample_phase *sp, int m) {
    return bit_array_allele(sp->hap2, sp->fpd->stage1_hap_bits, m);
}

void sample_phase_free(sample_phase *sp) {
    free(sp->hap1);
    free(sp->hap2);
    free(sp->clust_size);
    free(sp->clust_type);
}

void sample_phase_set_allele1(sample_phase *sp, int m, int allele) {
    bit_array_set_allele(sp->hap1, sp->fpd->stage1_hap_bits, m, allele);
}

void sample_phase_set_allele2(sample_phase *sp, int m, int allele) {
    bit_array_set_allele(sp->hap2, sp->fpd->stage1_hap_bits, m, allele);
}

void sample_phase_swap_haps(sample_phase *sp, int start, int end) {
    const int *hap_bits = sp->fpd->stage1_hap_bits;
    for (int b = hap_bits[start]; b < hap_bits[end]; ++b) {
        uint64_t mask = (uint64_t)1 << (b & 63);
        uint64_t diff = (sp->hap1[b >> 6] ^ sp->hap2[b >> 6]) & mask;
        sp->hap1[b >> 6] ^= diff;
        sp->hap2[b >> 6] ^= diff;
    }
}

void sample_phase_clust_ends(const sample_phase *sp, int *ends) {
    int cum_sum = 0;
    for (int c = 0; c < sp->n_clusters; ++c) {
        cum_sum += sp->clust_size[c];
        ends[c] = cum_sum;
    }
}

static void set_clust_type(sample_phase *sp, int cluster, clust_type from, clust_type to) {
    if (sp->clust_type[cluster] != from) util_exit("java.lang.IllegalArgumentException: %d", sp->clust_type[cluster]);
    sp->clust_type[cluster] = (uint8_t)to;
    --sp->clust_type_cnt[from];
    ++sp->clust_type_cnt[to];
}

void sample_phase_mark_unphased_het_as_phased(sample_phase *sp, int cluster) {
    set_clust_type(sp, cluster, CLUST_UNPHASED_HET, CLUST_PHASED_HET);
}

void sample_phase_mark_masked_het_as_phased(sample_phase *sp, int cluster) {
    set_clust_type(sp, cluster, CLUST_MASKED_HET, CLUST_PHASED_HET);
}

static void mask_run(sample_phase *sp, const int_list *clusters, const int_list *markers, int max_masked_bp) {
    int last_masked = clusters->n - 2;
    if (last_masked == 0) {
        set_clust_type(sp, clusters->v[0], CLUST_UNPHASED_HET, CLUST_MASKED_HET);
    } else if (last_masked > 0) {
        int32_t start_pos = fpd_marker(sp->fpd, markers->v[0])->pos;
        int32_t end_pos = fpd_marker(sp->fpd, markers->v[last_masked])->pos;
        if (end_pos - start_pos <= max_masked_bp) {
            for (int j = 0; j <= last_masked; ++j) set_clust_type(sp, clusters->v[j], CLUST_UNPHASED_HET, CLUST_MASKED_HET);
        }
    }
}

void sample_phase_mask_trailing_unphased_hets(sample_phase *sp) {
    int max_unph_het_clusters = 3;
    int max_masked_bp = 3000;
    int_list markers = {0};
    int_list clusters = {0};
    int start_marker = 0;
    for (int c = 0; c < sp->n_clusters; ++c) {
        if (sp->clust_type[c] == CLUST_PHASED_HET) {
            if (2 <= clusters.n && clusters.n <= max_unph_het_clusters) mask_run(sp, &clusters, &markers, max_masked_bp);
            markers.n = 0;
            clusters.n = 0;
        } else if (sp->clust_type[c] == CLUST_UNPHASED_HET) {
            int_list_add(&markers, start_marker);
            int_list_add(&clusters, c);
        }
        start_marker += sp->clust_size[c];
    }
    if (2 <= clusters.n && clusters.n <= max_unph_het_clusters) mask_run(sp, &clusters, &markers, max_masked_bp);
    free(markers.v);
    free(clusters.v);
}
