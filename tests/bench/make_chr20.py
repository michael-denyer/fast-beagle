"""Split the 1000 Genomes chr20 panel into a reference and an array-like target.

Usage: make_chr20.py <panel.vcf.gz> <out-dir>

Target: every 10th sample, unphased, at every 10th biallelic SNV with
0.05 <= AF <= 0.95. Reference: the other samples at every record except
symbolic structural variants and repeats of an earlier (POS, REF, ALT),
which Beagle rejects.
"""

import gzip
import sys


def is_target(i):
    return i % 10 == 0


def main():
    src, out = sys.argv[1], sys.argv[2]
    seen = set()
    common = 0
    with (
        gzip.open(src, "rt") as f,
        gzip.open(out + "/ref.vcf.gz", "wt", compresslevel=1) as ref,
        gzip.open(out + "/target.vcf.gz", "wt", compresslevel=1) as targ,
    ):
        for line in f:
            if line.startswith("##"):
                if line.startswith(("##fileformat", "##contig=<ID=chr20", "##FORMAT=<ID=GT")):
                    ref.write(line)
                    targ.write(line)
                continue
            cols = line.rstrip("\n").split("\t")
            if line.startswith("#"):
                ref.write("\t".join(cols[:9] + [s for i, s in enumerate(cols[9:]) if not is_target(i)]) + "\n")
                targ.write("\t".join(cols[:9] + [s for i, s in enumerate(cols[9:]) if is_target(i)]) + "\n")
                continue
            gts = cols[9:]
            fixed = cols[:7] + [".", "GT"]
            key = (cols[1], cols[3], cols[4])
            if not cols[4].startswith("<") and key not in seen:
                seen.add(key)
                ref.write("\t".join(fixed + [g for i, g in enumerate(gts) if not is_target(i)]) + "\n")
            if len(cols[3]) == 1 and len(cols[4]) == 1:
                af = float(cols[7].split("AF=", 1)[1].split(";", 1)[0])
                if 0.05 <= af <= 0.95:
                    common += 1
                    if common % 10 == 0:
                        targ.write(
                            "\t".join(fixed + [g.replace("|", "/") for i, g in enumerate(gts) if is_target(i)]) + "\n"
                        )


if __name__ == "__main__":
    main()
