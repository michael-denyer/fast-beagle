#!/usr/bin/env python3
"""Check a bgen=phased BGEN against the VCF written in the same run.

Usage: check_bgen_phased.py <out>.bgen <out>.vcf.gz

The BGEN must hold every VCF record in order, with the same chromosome,
position, ID and alleles (REF first), and per-haplotype probabilities that
agree with the VCF: exactly the GT alleles where the record has no DS field;
otherwise the GT allele is each haplotype's most probable, and dosages are
within rounding of DS, AP1 and AP2. Probabilities may have any bit depth
from 1 to 32; the tolerance is one stored unit per haplotype. Exits 1 and prints the first difference
otherwise. The exact quantisation rule is tested in tests/bgen/quantise_test.c.
"""

import gzip
import math
import struct
import sys
import zlib


def fail(msg):
    print(msg)
    sys.exit(1)


def read_bgen(path):
    with open(path, "rb") as f:
        data = f.read()
    offset, header_len, n_variants, _n_samples = struct.unpack_from("<IIII", data, 0)
    if data[16:20] != b"bgen":
        fail("bad magic")
    flags = struct.unpack_from("<I", data, 4 + header_len - 4)[0]
    if flags & 3 != 1 or (flags >> 2) & 15 != 2 or not flags >> 31:
        fail(f"flags {flags:#x}: want zlib, layout 2, sample ids")
    pos = 4 + header_len
    _, n = struct.unpack_from("<II", data, pos)
    pos += 8
    ids = []
    for _ in range(n):
        (length,) = struct.unpack_from("<H", data, pos)
        ids.append(data[pos + 2 : pos + 2 + length].decode())
        pos += 2 + length
    pos = 4 + offset
    variants = []
    for _ in range(n_variants):
        fields = []
        for _ in range(3):
            (length,) = struct.unpack_from("<H", data, pos)
            fields.append(data[pos + 2 : pos + 2 + length].decode())
            pos += 2 + length
        varid, rsid, chrom = fields
        vpos, k = struct.unpack_from("<IH", data, pos)
        pos += 6
        alleles = []
        for _ in range(k):
            (length,) = struct.unpack_from("<I", data, pos)
            alleles.append(data[pos + 4 : pos + 4 + length].decode())
            pos += 4 + length
        c, d = struct.unpack_from("<II", data, pos)
        block = zlib.decompress(data[pos + 8 : pos + 4 + c])
        pos += 4 + c
        if len(block) != d:
            fail(f"{chrom}:{vpos} block length {len(block)}, header says {d}")
        variants.append((varid, rsid, chrom, vpos, alleles, block))
    if pos != len(data):
        fail(f"{len(data) - pos} bytes after the last variant")
    return ids, variants


def unpack(block, n_samples, k):
    """The phased flag, the largest stored value, and per sample its ploidy,
    missing flag and probability groups as integer units of 1/max, each group
    with its omitted last value restored: one group per haplotype if phased,
    else one group over the genotypes."""
    n, kk, pmin, pmax = struct.unpack_from("<IHBB", block, 0)
    if n != n_samples or kk != k:
        fail(f"block has {n} samples and {kk} alleles, want {n_samples} and {k}")
    ploidy_bytes = block[8 : 8 + n]
    ploidy = [p & 0x3F for p in ploidy_bytes]
    missing = [bool(p & 0x80) for p in ploidy_bytes]
    phased, bits = block[8 + n], block[9 + n]
    if phased > 1 or not 1 <= bits <= 32:
        fail(f"phased={phased} bits={bits}, want 0 or 1 and 1 to 32")
    top = (1 << bits) - 1
    if min(ploidy) != pmin or max(ploidy) != pmax:
        fail("ploidy range does not match the ploidy bytes")
    if phased:
        groups = [[k] * p for p in ploidy]
    else:
        groups = [[math.comb(p + k - 1, k - 1)] for p in ploidy]
    n_values = sum(size - 1 for g in groups for size in g)
    n_bytes = (n_values * bits + 7) // 8
    if 10 + n + n_bytes != len(block):
        fail(f"probability data is {len(block) - 10 - n} bytes, want {n_bytes}")
    packed = int.from_bytes(block[10 + n :], "little")
    if packed >> (n_values * bits):
        fail("padding bits after the last value are not zero")
    values = [(packed >> (i * bits)) & top for i in range(n_values)]
    pos = 0
    samples = []
    for p, m, g in zip(ploidy, missing, groups):
        probs = []
        for size in g:
            stored = values[pos : pos + size - 1]
            pos += size - 1
            if sum(stored) > top:
                fail(f"stored probabilities {stored} sum above {top}")
            probs.append(stored + [top - sum(stored)])
        samples.append((p, m, probs))
    return phased, top, samples


def decode(block, n_samples, k):
    """The largest stored value, and per sample, per haplotype, the K
    probabilities as integer units of 1/max."""
    phased, top, samples = unpack(block, n_samples, k)
    if not phased:
        fail("the block is unphased")
    if any(m for _, m, _ in samples):
        fail("a sample is marked missing")
    return top, [haps for _, _, haps in samples]


def close(units, top, value, n_units):
    return abs(units / top - value) <= 0.005 + n_units / top + 1e-9


def main():
    ids, variants = read_bgen(sys.argv[1])
    vi = 0
    with gzip.open(sys.argv[2], "rt") as vcf:
        for line in vcf:
            if line.startswith("##"):
                continue
            f = line.rstrip("\n").split("\t")
            if line.startswith("#"):
                if f[9:] != ids:
                    fail("sample IDs differ from the VCF header")
                continue
            if vi == len(variants):
                fail("the VCF has more records than the BGEN")
            varid, rsid, chrom, vpos, alleles, block = variants[vi]
            vi += 1
            where = f"{f[0]}:{f[1]}"
            want = (f[0], int(f[1]), f[2], [f[3]] + f[4].split(","))
            if (chrom, vpos, rsid, alleles) != want or varid != "":
                fail(f"{where}: BGEN variant {(varid, rsid, chrom, vpos, alleles)}, VCF {want}")
            k = len(alleles)
            keys = f[8].split(":")
            top, samples = decode(block, len(ids), k)
            for s, (haps, field) in enumerate(zip(samples, f[9:])):
                vals = dict(zip(keys, field.split(":")))
                gt = [int(a) for a in vals["GT"].replace("|", "/").split("/")]
                if len(gt) != len(haps):
                    fail(f"{where} sample {s}: ploidy {len(haps)}, GT {vals['GT']}")
                if "DS" not in vals:
                    for h, a in zip(haps, gt):
                        if h[a] != top:
                            fail(f"{where} sample {s}: {h} for certain allele {a}")
                    continue
                # GT is each haplotype's most probable allele; rounding moves
                # a value by less than one unit.
                for h, a in zip(haps, gt):
                    if h[a] + 1 < max(h):
                        fail(f"{where} sample {s}: GT {vals['GT']} but haplotype probabilities {h}")
                for a in range(1, k):
                    dose = sum(h[a] for h in haps)
                    if not close(dose, top, float(vals["DS"].split(",")[a - 1]), len(haps)):
                        fail(f"{where} sample {s}: allele {a} dosage {dose}/{top}, DS {vals['DS']}")
                    for h, key in zip(haps, ("AP1", "AP2")):
                        if key in vals and not close(h[a], top, float(vals[key].split(",")[a - 1]), 1):
                            fail(f"{where} sample {s}: {key} {vals[key]}, BGEN {h}")
    if vi != len(variants):
        fail(f"the BGEN has {len(variants) - vi} records beyond the VCF")
    print(f"{len(variants)} variants")


if __name__ == "__main__":
    main()
