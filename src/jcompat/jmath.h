/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef JCOMPAT_JMATH_H
#define JCOMPAT_JMATH_H

/* java.lang.StrictMath, which is fdlibm 5.3. At every Beagle call site the
 * result is cast to float or floored, and there Math and StrictMath agree on
 * both HotSpot x86_64 (libm intrinsics) and aarch64: see tests/jcompat. */
double jmath_log(double x);
double jmath_log10(double x);
double jmath_pow(double x, double y);
double jmath_expm1(double x);

#endif
