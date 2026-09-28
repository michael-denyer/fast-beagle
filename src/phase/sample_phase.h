/*
 * Copyright (C) 2014-2021 Brian L. Browning
 * Ported to C from Beagle 5.5 (27Feb25) phase/SamplePhase.java; modified 2026.
 *
 * This file is part of fast-beagle, a C port of Beagle. It is free software:
 * you can redistribute it and/or modify it under the terms of the GNU General
 * Public License as published by the Free Software Foundation, either version 3
 * of the License, or (at your option) any later version. See LICENSE.
 */
#ifndef PHASE_SAMPLE_PHASE_H
#define PHASE_SAMPLE_PHASE_H

#include <stdint.h>

#include "phase/fixed_phase_data.h"

/* SamplePhase.ClustType, in Java's ordinal order. */
typedef enum {
    CLUST_MISSING_GT,
    CLUST_MASKED_HET,
    CLUST_HOMOZYGOUS_GT,
    CLUST_PHASED_HET,
    CLUST_UNPHASED_HET,
    N_CLUST_TYPES
} clust_type;

/* One target sample's current haplotypes at the stage-1 markers, and the
 * partition of those markers into clusters. A missing genotype or a
 * heterozygote is a cluster of its own; runs of homozygotes are grouped into
 * clusters of at most 255 markers spanning at most 0.005 cM. */
typedef struct {
    int sample;
    const fixed_phase_data *fpd;
    uint64_t *hap1;
    uint64_t *hap2;
    int n_clusters;
    uint8_t *clust_size;
    uint8_t *clust_type;
    int clust_type_cnt[N_CLUST_TYPES];
} sample_phase;

/* new SamplePhase(sample, markers, genPos, hap1, hap2, unphasedHets,
 * missingGTs): the lists of markers are increasing. */
void sample_phase_init(sample_phase *sp, int sample, const fixed_phase_data *fpd, const int *hap1, const int *hap2,
        const int *unph_hets, int n_unph_hets, const int *missing, int n_missing);
int sample_phase_allele1(const sample_phase *sp, int m);
int sample_phase_allele2(const sample_phase *sp, int m);
void sample_phase_set_allele1(sample_phase *sp, int m, int allele);
void sample_phase_set_allele2(sample_phase *sp, int m, int allele);
/* Swaps the two haplotypes' alleles at stage-1 markers [start, end). */
void sample_phase_swap_haps(sample_phase *sp, int start, int end);
/* Each cluster's exclusive end marker, n_clusters entries. */
void sample_phase_clust_ends(const sample_phase *sp, int *ends);
/* SamplePhase.maskTrailingUnphasedHets: in each run of 2 or 3 unphased
 * heterozygote clusters that ends at a phased heterozygote or the last
 * cluster, masks all but the last cluster: always for a run of 2, and for a
 * run of 3 when the first two start at most 3,000 bp apart. */
void sample_phase_mask_trailing_unphased_hets(sample_phase *sp);
void sample_phase_mark_unphased_het_as_phased(sample_phase *sp, int cluster);
void sample_phase_mark_masked_het_as_phased(sample_phase *sp, int cluster);
void sample_phase_free(sample_phase *sp);

#endif
