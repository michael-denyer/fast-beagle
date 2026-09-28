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
#include "phase/phase_baum2.h"

#include <stdlib.h>
#include <string.h>

#include "blbutil/utilities.h"
#include "phase/hmm_updater.h"
#include "phase/marker_cluster.h"

void phase_baum2_init(phase_baum2 *pb, const pbwt_phase_ibs *ibs) {
    phase_data *pd = ibs->pd;
    const par *p = pd->par;
    int n_markers = pd->fpd->n_stage1;
    pb->pd = pd;
    pb->burnin = pd->it < p->burnin;
    pb->lr_threshold = pd->lr_threshold;
    pb->mask_trailing_hets = pb->lr_threshold < 50.0f;
    pb->max_states = p->phase_states;
    basic_phase_states_init(&pb->states, ibs, pb->max_states);
    pb->n_states = 0;
    pb->mismatch = util_malloc(3 * sizeof *pb->mismatch);
    for (int i = 0; i < 3; ++i) {
        pb->mismatch[i] = util_malloc((size_t)n_markers * sizeof **pb->mismatch);
        for (int m = 0; m < n_markers; ++m) pb->mismatch[i][m] = util_malloc((size_t)pb->max_states);
        pb->fwd[i] = util_malloc((size_t)pb->max_states * sizeof *pb->fwd[i]);
        pb->bwd[i] = util_malloc((size_t)pb->max_states * sizeof *pb->bwd[i]);
    }
    pb->p_mismatch = pd->p_mismatch;
    pb->em_probs[0] = 1.0f - pb->p_mismatch;
    pb->em_probs[1] = pb->p_mismatch;
    pb->n_miss_cap = pb->n_het_cap = 0;
    pb->ref_alleles = NULL;
    pb->bwd_miss1 = pb->bwd_miss2 = pb->bwd_het1 = pb->bwd_het2 = NULL;
    pb->swap_haps = false;
    pb->n_swaps = 0;
}

void phase_baum2_free(phase_baum2 *pb) {
    int n_markers = pb->pd->fpd->n_stage1;
    for (int i = 0; i < 3; ++i) {
        for (int m = 0; m < n_markers; ++m) free(pb->mismatch[i][m]);
        free(pb->mismatch[i]);
        free(pb->fwd[i]);
        free(pb->bwd[i]);
    }
    free(pb->mismatch);
    for (int j = 0; j < pb->n_miss_cap; ++j) {
        free(pb->ref_alleles[j]);
        free(pb->bwd_miss1[j]);
        free(pb->bwd_miss2[j]);
    }
    for (int j = 0; j < pb->n_het_cap; ++j) {
        free(pb->bwd_het1[j]);
        free(pb->bwd_het2[j]);
    }
    free(pb->ref_alleles);
    free(pb->bwd_miss1);
    free(pb->bwd_miss2);
    free(pb->bwd_het1);
    free(pb->bwd_het2);
    basic_phase_states_free(&pb->states);
}

static void ensure_capacity(phase_baum2 *pb, int n_unph, int n_miss) {
    size_t row = (size_t)pb->max_states;
    if (pb->n_miss_cap < n_miss) {
        pb->ref_alleles = util_realloc(pb->ref_alleles, (size_t)n_miss * sizeof *pb->ref_alleles);
        pb->bwd_miss1 = util_realloc(pb->bwd_miss1, (size_t)n_miss * sizeof *pb->bwd_miss1);
        pb->bwd_miss2 = util_realloc(pb->bwd_miss2, (size_t)n_miss * sizeof *pb->bwd_miss2);
        for (int j = pb->n_miss_cap; j < n_miss; ++j) {
            pb->ref_alleles[j] = util_malloc(row * sizeof **pb->ref_alleles);
            pb->bwd_miss1[j] = util_malloc(row * sizeof **pb->bwd_miss1);
            pb->bwd_miss2[j] = util_malloc(row * sizeof **pb->bwd_miss2);
        }
        pb->n_miss_cap = n_miss;
    }
    if (pb->n_het_cap < n_unph) {
        pb->bwd_het1 = util_realloc(pb->bwd_het1, (size_t)n_unph * sizeof *pb->bwd_het1);
        pb->bwd_het2 = util_realloc(pb->bwd_het2, (size_t)n_unph * sizeof *pb->bwd_het2);
        for (int j = pb->n_het_cap; j < n_unph; ++j) {
            pb->bwd_het1[j] = util_malloc(row * sizeof **pb->bwd_het1);
            pb->bwd_het2[j] = util_malloc(row * sizeof **pb->bwd_het2);
        }
        pb->n_het_cap = n_unph;
    }
}

/* The emission probabilities for a cluster of n markers: a mismatch anywhere
 * in it, capped at 0.5. */
static void set_cluster_em_probs(phase_baum2 *pb, int n_markers_in_cluster) {
    float clust_em = n_markers_in_cluster * pb->p_mismatch;
    if (clust_em >= 0.5f) clust_em = 0.5f;
    pb->em_probs[1] = clust_em;
    pb->em_probs[0] = 1.0f - clust_em;
}

static void copy_states(const phase_baum2 *pb, float *dst, const float *src) {
    memcpy(dst, src, (size_t)pb->n_states * sizeof *dst);
}

static void bwd_step(phase_baum2 *pb, const marker_cluster *mc, int cluster) {
    int c_p1 = cluster + 1;
    float p_rec = mc->p_recomb[c_p1];
    set_cluster_em_probs(pb, mc->ends[c_p1] - marker_cluster_start(mc, c_p1));
    hmm_bwd_update3(pb->bwd, p_rec, pb->em_probs, pb->mismatch[0][c_p1], pb->mismatch[1][c_p1], pb->mismatch[2][c_p1], pb->n_states);
}

static void bwd_alg(phase_baum2 *pb, const marker_cluster *mc) {
    const sample_phase *sp = mc->sp;
    int miss_index = sp->clust_type_cnt[CLUST_MISSING_GT] + sp->clust_type_cnt[CLUST_MASKED_HET] - 1;
    int unph_index = sp->clust_type_cnt[CLUST_UNPHASED_HET] - 1;
    for (int k = 0; k < pb->n_states; ++k) pb->bwd[0][k] = 1.0f / pb->n_states;
    copy_states(pb, pb->bwd[1], pb->bwd[0]);
    copy_states(pb, pb->bwd[2], pb->bwd[0]);
    int last_cluster = mc->n_clusters - 1;
    if (marker_cluster_is_missing_or_masked(mc, last_cluster)) {
        copy_states(pb, pb->bwd_miss1[miss_index], pb->bwd[0]);
        copy_states(pb, pb->bwd_miss2[miss_index], pb->bwd[0]);
        --miss_index;
    }
    for (int c = last_cluster - 1; c >= 0; --c) {
        bwd_step(pb, mc, c);
        if (marker_cluster_is_missing_or_masked(mc, c)) {
            copy_states(pb, pb->bwd_miss1[miss_index], pb->bwd[1]);
            copy_states(pb, pb->bwd_miss2[miss_index], pb->bwd[2]);
            --miss_index;
        }
        if (sp->clust_type[c + 1] == CLUST_UNPHASED_HET) {
            copy_states(pb, pb->bwd_het1[unph_index], pb->bwd[1]);
            copy_states(pb, pb->bwd_het2[unph_index], pb->bwd[2]);
            copy_states(pb, pb->bwd[1], pb->bwd[0]);
            copy_states(pb, pb->bwd[2], pb->bwd[0]);
            --unph_index;
        }
    }
}

static void fwd_step(phase_baum2 *pb, const marker_cluster *mc, int cluster) {
    float p_rec = mc->p_recomb[cluster];
    set_cluster_em_probs(pb, mc->ends[cluster] - marker_cluster_start(mc, cluster));
    hmm_fwd_update3(pb->fwd, pb->fwd_sums, p_rec, pb->em_probs, pb->mismatch[0][cluster], pb->mismatch[1][cluster], pb->mismatch[2][cluster], pb->n_states);
}

static void swap_haps(phase_baum2 *pb, const marker_cluster *mc, int start_clust, int end_clust) {
    for (int c = start_clust; c < end_clust; ++c) {
        uint8_t *tmp = pb->mismatch[1][c];
        pb->mismatch[1][c] = pb->mismatch[2][c];
        pb->mismatch[2][c] = tmp;
    }
    sample_phase_swap_haps(mc->sp, marker_cluster_start(mc, start_clust), mc->ends[end_clust - 1]);
}

static void phase_het(phase_baum2 *pb, sample_phase *sp, int unph_het_index, int cluster) {
    const float *b1 = pb->bwd_het1[unph_het_index];
    const float *b2 = pb->bwd_het2[unph_het_index];
    float p11 = 0.0f, p12 = 0.0f, p21 = 0.0f, p22 = 0.0f;
    for (int k = 0; k < pb->n_states; ++k) {
        p11 += pb->fwd[1][k] * b1[k];
        p12 += pb->fwd[1][k] * b2[k];
        p21 += pb->fwd[2][k] * b1[k];
        p22 += pb->fwd[2][k] * b2[k];
    }
    float num = p11 * p22;
    float den = p12 * p21;
    bool last_swap_haps = pb->swap_haps;
    pb->swap_haps = num < den;
    if (pb->swap_haps != last_swap_haps) ++pb->n_swaps;
    if (!pb->burnin && (num >= den * pb->lr_threshold || (pb->swap_haps && den >= num * pb->lr_threshold))) {
        sample_phase_mark_unphased_het_as_phased(sp, cluster);
    }
}

static void impute_missing_gt(sample_phase *sp, int marker, const float *al_freq1, const float *al_freq2, int n_alleles) {
    int a1 = 0;
    int a2 = 0;
    for (int j = 1; j < n_alleles; ++j) {
        if (al_freq1[j] > al_freq1[a1]) a1 = j;
        if (al_freq2[j] > al_freq2[a2]) a2 = j;
    }
    sample_phase_set_allele1(sp, marker, a1);
    sample_phase_set_allele2(sp, marker, a2);
}

static void impute_masked_het(const phase_baum2 *pb, sample_phase *sp, int cluster, int marker, const float *al_freq1, const float *al_freq2) {
    int a1 = sample_phase_allele1(sp, marker);
    int a2 = sample_phase_allele2(sp, marker);
    float p_no_switch = al_freq1[a1] * al_freq2[a2];
    float p_switch = al_freq1[a2] * al_freq2[a1];
    if (p_switch > p_no_switch) {
        sample_phase_set_allele1(sp, marker, a2);
        sample_phase_set_allele2(sp, marker, a1);
        if (p_switch >= pb->lr_threshold * p_no_switch) sample_phase_mark_masked_het_as_phased(sp, cluster);
    } else if (p_no_switch >= pb->lr_threshold * p_switch) {
        sample_phase_mark_masked_het_as_phased(sp, cluster);
    }
}

static void impute_alleles(phase_baum2 *pb, const marker_cluster *mc, int cluster, int miss_index) {
    float *state_probs1 = pb->bwd_miss1[miss_index];
    float *state_probs2 = pb->bwd_miss2[miss_index];
    if (pb->swap_haps) {
        float *tmp = state_probs1;
        state_probs1 = state_probs2;
        state_probs2 = tmp;
    }
    const int *ref_al = pb->ref_alleles[miss_index];
    for (int k = 0; k < pb->n_states; ++k) {
        state_probs1[k] *= pb->fwd[1][k];
        state_probs2[k] *= pb->fwd[2][k];
    }
    int marker = marker_cluster_start(mc, cluster);
    int n_alleles = fpd_n_alleles(pb->pd->fpd, marker);
    float *al_freq1 = util_malloc((size_t)n_alleles * sizeof *al_freq1);
    float *al_freq2 = util_malloc((size_t)n_alleles * sizeof *al_freq2);
    for (int a = 0; a < n_alleles; ++a) al_freq1[a] = al_freq2[a] = 0.0f;
    for (int k = 0; k < pb->n_states; ++k) {
        al_freq1[ref_al[k]] += state_probs1[k];
        al_freq2[ref_al[k]] += state_probs2[k];
    }
    sample_phase *sp = mc->sp;
    if (sp->clust_type[cluster] == CLUST_MISSING_GT) {
        impute_missing_gt(sp, marker, al_freq1, al_freq2, n_alleles);
    } else if (sp->clust_type[cluster] == CLUST_MASKED_HET) {
        impute_masked_het(pb, sp, cluster, marker, al_freq1, al_freq2);
    }
    free(al_freq1);
    free(al_freq2);
}

static void fwd_alg(phase_baum2 *pb, const marker_cluster *mc) {
    int miss_index = 0;
    int unph_het_index = 0;
    for (int k = 0; k < pb->n_states; ++k) pb->fwd[0][k] = 1.0f / pb->n_states;
    copy_states(pb, pb->fwd[1], pb->fwd[0]);
    copy_states(pb, pb->fwd[2], pb->fwd[0]);
    pb->fwd_sums[2] = pb->fwd_sums[1] = pb->fwd_sums[0] = 1.0f;
    for (int c = 0; c < mc->n_clusters; ++c) {
        if (mc->sp->clust_type[c] == CLUST_UNPHASED_HET) {
            phase_het(pb, mc->sp, unph_het_index, c);
            ++unph_het_index;
            if (pb->swap_haps) {
                int swap_end = unph_het_index < mc->n_unph_het ? mc->unph_het_clusters[unph_het_index] : mc->n_clusters;
                swap_haps(pb, mc, c, swap_end);
            }
            copy_states(pb, pb->fwd[1], pb->fwd[0]);
            copy_states(pb, pb->fwd[2], pb->fwd[0]);
            pb->fwd_sums[1] = pb->fwd_sums[2] = pb->fwd_sums[0];
        }
        fwd_step(pb, mc, c);
        if (marker_cluster_is_missing_or_masked(mc, c)) impute_alleles(pb, mc, c, miss_index++);
    }
}

void phase_baum2_phase(phase_baum2 *pb, int sample, swap_rate *rate) {
    sample_phase *sp = &pb->pd->phase[sample];
    if (pb->mask_trailing_hets) sample_phase_mask_trailing_unphased_hets(sp);
    int n_unph_hets = sp->clust_type_cnt[CLUST_UNPHASED_HET];
    int n_missing_or_masked = sp->clust_type_cnt[CLUST_MISSING_GT] + sp->clust_type_cnt[CLUST_MASKED_HET];
    if (n_missing_or_masked > 0 || n_unph_hets > 0) {
        pb->n_swaps = 0;
        pb->swap_haps = false;
        marker_cluster mc;
        marker_cluster_init(&mc, pb->pd, sample);
        ensure_capacity(pb, n_unph_hets, n_missing_or_masked);
        pb->n_states = basic_phase_states_cluster_states(&pb->states, &mc, pb->ref_alleles, pb->mismatch);
        bwd_alg(pb, &mc);
        fwd_alg(pb, &mc);
        rate->n_swaps += pb->n_swaps;
        rate->n_unph_hets += n_unph_hets;
        marker_cluster_free(&mc);
    }
}
