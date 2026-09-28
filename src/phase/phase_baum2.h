/*
 * Copyright (C) 2014-2021 Brian L. Browning
 * Ported to C from Beagle 5.5 (27Feb25) phase/PhaseBaum2.java and
 * phase/SwapRate.java; modified 2026.
 *
 * This file is part of beagle-c, a C port of Beagle. It is free software:
 * you can redistribute it and/or modify it under the terms of the GNU General
 * Public License as published by the Free Software Foundation, either version 3
 * of the License, or (at your option) any later version. See LICENSE.
 */
#ifndef PHASE_PHASE_BAUM2_H
#define PHASE_PHASE_BAUM2_H

#include <stdbool.h>
#include <stdint.h>

#include "phase/basic_phase_states.h"

/* SwapRate: switches of phase between successive unphased heterozygotes, as
 * a proportion of unphased heterozygotes, over one iteration. */
typedef struct {
    int64_t n_swaps;
    int64_t n_unph_hets;
} swap_rate;

/* One sample at a time, runs forward-backward over the sample's clusters
 * with three HMMs (the genotype, and each haplotype after the last unphased
 * heterozygote), phases each unphased heterozygote from the posterior odds,
 * and imputes missing genotypes and masked heterozygotes. The model
 * parameters are fixed when it is created. */
typedef struct {
    phase_data *pd;
    bool burnin;
    float lr_threshold;
    bool mask_trailing_hets;
    int max_states;
    basic_phase_states states;
    int n_states;
    uint8_t ***mismatch;   /* [3][cluster][state]; rows 1 and 2 swap with the haplotypes */
    float p_mismatch;
    float em_probs[2];
    float *fwd[3];
    float *bwd[3];
    float fwd_sums[3];
    int n_miss_cap;
    int **ref_alleles;
    float **bwd_miss1;
    float **bwd_miss2;
    int n_het_cap;
    float **bwd_het1;
    float **bwd_het2;
    bool swap_haps;
    int n_swaps;
} phase_baum2;

/* new PhaseBaum2(phaseIbs) */
void phase_baum2_init(phase_baum2 *pb, const pbwt_phase_ibs *ibs);
/* PhaseBaum2.phase(sample): updates the sample's SamplePhase and adds its
 * swaps to rate. */
void phase_baum2_phase(phase_baum2 *pb, int sample, swap_rate *rate);
void phase_baum2_free(phase_baum2 *pb);

#endif
