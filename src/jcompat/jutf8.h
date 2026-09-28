/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef JCOMPAT_JUTF8_H
#define JCOMPAT_JUTF8_H

#include <stddef.h>
#include <stdint.h>

#include <htslib/kstring.h>

/* Java's UTF-8 decoding with REPLACE, re-encoded as UTF-8: each malformed
 * sequence becomes U+FFFD (EF BF BD), with the JDK's rules for how many bytes
 * one replacement consumes. Valid input is unchanged. s is rewritten in place. */
void jutf8_sanitize(kstring_t *s);

/* The BMP char that the 1-, 2- or 3-byte UTF-8 sequence at s[*i] encodes,
 * advancing *i past it, or -1 for anything else: Java decodes malformed input
 * to U+FFFD and a 4-byte sequence to a surrogate pair. Needs *i < len. */
int32_t jutf8_next_bmp(const char *s, size_t len, size_t *i);

#endif
