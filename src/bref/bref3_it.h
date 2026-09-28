/*
 * Copyright (C) 2014-2021 Brian L. Browning
 * Ported to C from Beagle 5.5 (27Feb25) bref/Bref3It.java,
 * bref/Bref3Reader.java and bref/Bref3Header.java; modified 2026.
 *
 * This file is part of fast-beagle, a C port of Beagle. It is free software:
 * you can redistribute it and/or modify it under the terms of the GNU General
 * Public License as published by the Free Software Foundation, either version 3
 * of the License, or (at your option) any later version. See LICENSE.
 */
#ifndef BREF_BREF3_IT_H
#define BREF_BREF3_IT_H

#include "blbutil/sample_file_it.h"
#include "blbutil/str_set.h"

/* The records (ref_gt_rec) of a bref3 file that pass the marker filter, one
 * block at a time. The file's blocks are kept as written: the sequence-coded
 * records of a block share one group, whose sequences were numbered over every
 * sample in the file. Excluded samples and markers are dropped after that
 * coding, where a VCF reference drops them before it, so the groups, and the
 * imputation clusters that break at group boundaries, can differ from a VCF
 * reference of the same panel. Every sample is diploid. With tracing on, writes
 * seams T1a-ref, T1b-ref and T1d-ref.
 *
 * new Bref3It(file, sampleFilter, markerFilter): reads the header and the
 * first block. Exits with Java's message on a bad magic number or when every
 * sample is excluded, and on a malformed file. */
sample_file_it bref3_it_open(const char *path, const str_set *exclude_samples, const str_set *exclude_markers);

#endif
