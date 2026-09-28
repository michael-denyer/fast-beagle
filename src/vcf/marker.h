/*
 * Copyright (C) 2014-2021 Brian L. Browning
 * Ported to C from Beagle 5.5 (27Feb25) vcf/Marker.java, vcf/MarkerParser.java
 * and vcf/MarkerUtils.java; modified 2026.
 *
 * This file is part of beagle-c, a C port of Beagle. It is free software:
 * you can redistribute it and/or modify it under the terms of the GNU General
 * Public License as published by the Free Software Foundation, either version 3
 * of the License, or (at your option) any later version. See LICENSE.
 */
#ifndef VCF_MARKER_H
#define VCF_MARKER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* A substring: s[0..n) with no terminator. */
typedef struct {
    const char *s;
    int n;
} span;

/* Java's Marker with its storage kept as is: a fieldInfo word of flags and a
 * tab-separated `fields` string built by MarkerParser(storeId=true, false,
 * false, false). QUAL and FILTER are dropped and INFO keeps only its first END=
 * subfield. SNV REF/ALT fields that prefix an entry of SNV_PERMS are stored as
 * an index into it. The accessors reproduce Java's, including the layouts an
 * empty ID field produces. */
typedef struct {
    int chrom_index;
    int32_t pos;
    uint16_t field_info;
    char *fields;       /* NULL where Java's is null */
    size_t fields_len;
} marker;

/* Marker.instance(rec, parser). Exits with Java's message on malformed input. */
void marker_parse(marker *m, const char *rec, size_t len);
void marker_free(marker *m);

const char *marker_chrom(const marker *m);
int marker_n_alleles(const marker *m);
/* Marker.bitsPerAllele: the bits a non-missing allele needs, 0 for one allele. */
int marker_bits_per_allele(const marker *m);
bool marker_has_id(const marker *m);
span marker_id(const marker *m);         /* "." when absent */
span marker_alleles(const marker *m);    /* REF '\t' ALT */
span marker_end_value(const marker *m);  /* "" when absent */
span marker_info(const marker *m);       /* the stored INFO field (only its END= subfield is kept), "." when absent */

#endif
