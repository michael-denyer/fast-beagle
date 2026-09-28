/*
 * Copyright (C) 2005-2026 Shaun Purcell, Christopher Chang
 * Ported to C from PLINK 2.0 v2.0.0-a.7.8 include/plink2_string.cc
 * (ScanadvDouble, dtoa_g); modified 2026.
 *
 * This file is part of beagle-c, a C port of Beagle. It is free software:
 * you can redistribute it and/or modify it under the terms of the GNU General
 * Public License as published by the Free Software Foundation, either version 3
 * of the License, or (at your option) any later version. See LICENSE.
 */
#ifndef BGEN_PLINK2_NUM_H
#define BGEN_PLINK2_NUM_H

/* ScanadvDouble: parses a number at s, as plink2 parses DS, INFO values and
 * numeric arguments. Returns the end of the number, or NULL if s does not
 * start with one. Not strtod: "0.3" gives 3 * 0.1, not the nearest double. */
const char *plink2_scanadv_double(const char *s, double *value);

/* dtoa_g for 0 <= x <= 1: plink2's 6-significant-digit %g. Writes a
 * terminated string of at most 16 bytes to buf. */
void plink2_dtoa_g_unit(double x, char *buf);

#endif
