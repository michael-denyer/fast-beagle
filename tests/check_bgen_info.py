#!/usr/bin/env python3
"""Check a bgen= run's .info sidecar against its .bgen and VCF.

Usage: check_bgen_info.py <out>.bgen <out>.info <out>.vcf.gz

The .info must have a header and one row per BGEN variant, in BGEN order,
with the variant's position and ID. Each row must copy its VCF record:
CHROM, POS, ID, REF and ALT, the printed DR2 and AF values ("." if absent),
and IMP as 1 or 0. The VCF may have records the BGEN leaves out (bgen=plink2
filters and multiallelic records). Exits 1 and prints the first difference.
"""

import gzip
import struct
import sys

HEADER = "CHROM\tPOS\tID\tREF\tALT\tDR2\tAF\tIMP"


def fail(msg):
    print(msg)
    sys.exit(1)


def bgen_variants(path):
    with open(path, "rb") as f:
        data = f.read()
    offset, _, n_variants, _ = struct.unpack_from("<IIII", data, 0)
    pos = 4 + offset
    for _ in range(n_variants):
        fields = []
        for _ in range(3):
            (length,) = struct.unpack_from("<H", data, pos)
            fields.append(data[pos + 2 : pos + 2 + length].decode())
            pos += 2 + length
        vpos, k = struct.unpack_from("<IH", data, pos)
        pos += 6
        for _ in range(k):
            (length,) = struct.unpack_from("<I", data, pos)
            pos += 4 + length
        (c,) = struct.unpack_from("<I", data, pos)
        pos += 4 + c
        yield fields[1], vpos


def info_value(info, key):
    return next((t[len(key) + 1 :] for t in info if t.startswith(key + "=")), ".")


def expected_row(f):
    info = f[7].split(";")
    return [
        f[0],
        f[1],
        f[2],
        f[3],
        f[4],
        info_value(info, "DR2"),
        info_value(info, "AF"),
        "1" if "IMP" in info else "0",
    ]


def main():
    bgen = list(bgen_variants(sys.argv[1]))
    with open(sys.argv[2]) as fh:
        lines = fh.read().split("\n")
    if lines[0] != HEADER or lines[-1] != "":
        fail(f".info header {lines[0]!r} or missing final newline")
    rows = [line.split("\t") for line in lines[1:-1]]
    if len(rows) != len(bgen):
        fail(f".info has {len(rows)} rows, the BGEN {len(bgen)} variants")
    with gzip.open(sys.argv[3], "rt") as vcf:
        records = (line.rstrip("\n").split("\t") for line in vcf if not line.startswith("#"))
        for row, (rsid, vpos) in zip(rows, bgen):
            if (row[2], row[1]) != (rsid, str(vpos)):
                fail(f".info row {row[:3]} for BGEN variant {rsid} at {vpos}")
            for f in records:
                if f[1] == row[1] and f[2] == row[2] and f[3] == row[3] and f[4] == row[4]:
                    break
            else:
                fail(f".info row {row[:5]} has no VCF record after the previous row's")
            if row != expected_row(f):
                fail(f".info row {row}, VCF gives {expected_row(f)}")
    print(f"{len(rows)} rows")


if __name__ == "__main__":
    main()
