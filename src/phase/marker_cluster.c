/*
 * Copyright (C) 2014-2021 Brian L. Browning
 * Ported to C from Beagle 5.5 (27Feb25) phase/MarkerCluster.java;
 * modified 2026.
 *
 * This file is part of fast-beagle, a C port of Beagle. It is free software:
 * you can redistribute it and/or modify it under the terms of the GNU General
 * Public License as published by the Free Software Foundation, either version 3
 * of the License, or (at your option) any later version. See LICENSE.
 */
#include "phase/marker_cluster.h"

#include <stdlib.h>

#include "blbutil/utilities.h"

void marker_cluster_init(marker_cluster *mc, const phase_data *pd, int sample) {
    sample_phase *sp = &pd->phase[sample];
    int n = sp->n_clusters;
    mc->sp = sp;
    mc->n_clusters = n;
    mc->ends = util_malloc((size_t)n * sizeof *mc->ends);
    sample_phase_clust_ends(sp, mc->ends);
    mc->n_unph_het = sp->clust_type_cnt[CLUST_UNPHASED_HET];
    mc->unph_het_clusters = util_malloc((size_t)(mc->n_unph_het > 0 ? mc->n_unph_het : 1) * sizeof *mc->unph_het_clusters);
    for (int c = 0, j = 0; c < n; ++c) {
        if (sp->clust_type[c] == CLUST_UNPHASED_HET) mc->unph_het_clusters[j++] = c;
    }
    mc->p_recomb = util_malloc((size_t)n * sizeof *mc->p_recomb);
    mc->p_recomb[0] = 0.0f;
    int start = mc->ends[0];
    for (int c = 1; c < n; ++c) {
        int end = mc->ends[c];
        float p_no_recomb = 1.0f;
        for (int k = start; k < end; ++k) p_no_recomb *= (1.0f - pd->p_recomb[k]);
        mc->p_recomb[c] = 1.0f - p_no_recomb;
        start = end;
    }
}

void marker_cluster_free(marker_cluster *mc) {
    free(mc->ends);
    free(mc->unph_het_clusters);
    free(mc->p_recomb);
}
