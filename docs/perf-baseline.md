# Performance

This page compares `build/beagle` with Java Beagle 5.5 (`beagle.27Feb25.75f.jar`). Both tools write the same VCF, so the comparison is of time and memory only. The gain grows with the size of the imputation.

| Run | Target samples | Threads | Faster | Less CPU time | Less max memory |
|---|---|---|---|---|---|
| [1000 Genomes chr20](#1000-genomes-chr20-benchmark) | 321 | 18 | 1.5× to 1.9× | 2.0× to 2.1× | 2.2× to 3.0× |
| [Production scale](#production-scale-run) | about 100,000 | 60 | 3.1× | 2.3× | 3.5× |
| [Phasing, 1000 Genomes chr20](#reference-free-phasing) | 3,202 | 16 | 2.0× | 2.1× | 1.2× more |
| [Phasing, 1000 Genomes chrX](#reference-free-phasing) | 3,202 | 60 | 1.8× | 2.1× | 2.7× |
| [Phasing, 1000 Genomes chr1](#reference-free-phasing) | 3,202 | 60 | 1.8× | 2.1× | 3.3× |

The chr20 imputation ranges span two runs on different days. The 1000 Genomes runs use public data, so anyone can rerun them.

## Production-scale run

This run imputed one chromosome for about 100,000 target samples and wrote about 13 GB of compressed VCF. It ran on a Databricks node of type `Standard_E64ds_v6`, which has 64 vCPUs (Intel Xeon Platinum 8573C) and 512 GiB of memory, with Databricks Runtime 16.4 LTS on Ubuntu 24.04. Both tools ran with `nthreads=60`, and both wrote the same VCF. The figures cover the Beagle step alone, one run per tool on 2026-09-28. The input data is not public, so this run cannot be reproduced from this repository.

| | Java | C | Java / C |
|---|---|---|---|
| Wall time | 884 s | 288 s | 3.1× faster |
| CPU time | 30,420 s | 13,499 s | 2.3× less |
| Max memory | 296.4 GB | 84.3 GB | 3.5× less |

The C binary was built with GCC 13.3 and linked against Ubuntu 24.04's shared htslib, which uses libdeflate. On 2026-09-30, commit `9e4be51` built the same way took 291 s. A static build of that commit with htslib linked against zlib alone took 338 s and 16,685 s of CPU time. `release/build-static.sh` links libdeflate for this reason.

The C run did not write a tabix index. With `tbi=true`, the same step took 346 s and 16,194 s of CPU time at the same max memory, and it replaced a separate `tabix -p vcf` pass.

## 1000 Genomes chr20 benchmark

### Input

`tests/bench/fetch-chr20.sh <dir>` downloads the 1000 Genomes high-coverage chr20 phased panel and Beagle's GRCh38 genetic map. It checks their SHA-256 and derives three files with `tests/bench/make_chr20.py`:

- `target.vcf.gz`: 321 samples (every 10th panel sample), unphased, at 15,879 markers (every 10th biallelic SNV with 0.05 <= AF <= 0.95).
- `ref.vcf.gz`: the other 2,881 samples at 1,642,181 markers (every panel record except symbolic structural variants and repeats of an earlier position, REF and ALT).
- `chr20.map`: the chr20 PLINK map with chromosome `chr20`.

```bash
tests/bench/fetch-chr20.sh ~/beagle-bench
```

### Method

`tests/bench/bench.sh <dir> <rounds> [nthreads]` runs Java and C in the order Java, C, C, Java in each round, so both tools see the same thermal and load state. It records wall time, CPU time (user plus system) and max memory (maximum resident set size) with `/usr/bin/time`. It also records the output hash as `tests/check-oracle.sh` computes it.

```bash
JAVA="/opt/homebrew/opt/openjdk@21/bin/java -Xmx32g" tests/bench/bench.sh ~/beagle-bench 3
```

### Result

These runs used commit `12edce9` on 2026-09-26, with 18 threads and 3 rounds (6 runs per tool). Every run wrote the VCF with hash `38d4ed96cec67a44`.

| | Java | C | C / Java |
|---|---|---|---|
| Wall time, median (range) | 31.5 s (30.9 to 32.5) | 21.1 s (20.9 to 22.2) | 0.67 |
| CPU time, median (range) | 478 s (471 to 493) | 235 s (232 to 248) | 0.49 |
| Max memory, median (range) | 7.9 GB (7.7 to 8.5) | 2.66 GB (2.63 to 2.66) | 0.34 |

Java's max memory depends on `-Xmx` and the garbage collector. These runs used `-Xmx32g` and the default collector.

The machine was an Apple M5 Pro (6 super and 12 performance cores) with 64 GB and macOS 27.0. Java was OpenJDK 21.0.12.1 (Homebrew). The C build used Apple clang 21.0.0 with the Makefile's flags, and htslib 1.24.

A second run on 2026-09-28, at commit `c7ee83f` on a busier machine, wrote the same hash. Its medians were 40.3 s against 21.3 s of wall time, 538 s against 253 s of CPU time, and 5.9 GB against 2.63 GB of max memory. The summary table at the top gives the range over both runs.

## Reference-free phasing

These runs phase every sample of a 1000 Genomes high-coverage panel without a reference panel, so almost all of their time is spent phasing.

### Phasing input

`tests/bench/make_phase.py <panel.vcf.gz> <out.vcf.gz>` keeps every sample and every record except symbolic structural variants and repeats of an earlier POS, REF and ALT, and it removes the phase from each genotype. For chr20 it reads the panel that `tests/bench/fetch-chr20.sh` downloads, and the runs use that script's `chr20.map`:

```bash
python3 tests/bench/make_phase.py ~/beagle-bench/1kGP_high_coverage_Illumina.chr20.filtered.SNV_INDEL_SV_phased_panel.vcf.gz ~/beagle-bench/chr20.phase.vcf.gz
```

The chr1 and chrX inputs come from the same release's chr1 panel and chrX `v2` panel, with the maps in the `chr_in_chrom_field` folder of Beagle's GRCh38 map zip. chrX keeps only the region outside the pseudoautosomal regions (positions 2,781,480 to 155,701,382), because Beagle needs one ploidy per sample and male samples are diploid inside those regions.

| Input | Samples | Records |
|---|---|---|
| chr20 | 3,202 | 1,642,181 |
| chrX | 3,202 | 2,731,121 |
| chr1 | 3,202 | 5,751,396 |

Each tool ran `gt=<input> map=<map> out=<out> nthreads=<n>` once per input.

### Result on an Apple M5 Pro

This run phased chr20 with `nthreads=16` on the machine described under [1000 Genomes chr20](#result). Java ran on 2026-09-29 with `-Xmx57344m`. Its Java version was not recorded. C ran at commit `9e4be51` on 2026-09-30. Both wrote the VCF with hash `51c2dcefaa661614`.

| | Java | C | Java / C |
|---|---|---|---|
| Wall time | 2,545 s | 1,278 s | 2.0× faster |
| CPU time | 38,688 s | 18,456 s | 2.1× less |
| Max memory | 32.5 GB | 40.1 GB | 1.2× more |

C's max memory on this input varies between runs. A build with the same phasing code reached 32.4 GB in one run and 39.6 GB in another, while its instruction count stayed within 0.02%.

### Result on Intel Xeon

These ran on Databricks nodes of type `Standard_D64ds_v6`, which have 64 vCPUs (Intel Xeon Platinum 8573C) and 256 GiB of memory, with Databricks Runtime 16.4 LTS. Both tools ran with `nthreads=60`. Java was OpenJDK 17.0.20 with `-Xmx190g` and ran on 2026-09-29. C was the static Linux build of commit `9e4be51` from `release/build-static.sh` (GCC 14.2.1) and ran on 2026-09-30 on a fresh node of the same type.

| chrX | Java | C | Java / C |
|---|---|---|---|
| Wall time | 2,032 s | 1,101 s | 1.8× faster |
| CPU time | 105,873 s | 49,827 s | 2.1× less |
| Max memory | 166.0 GB | 60.8 GB | 2.7× less |

| chr1 | Java | C | Java / C |
|---|---|---|---|
| Wall time | 5,895 s | 3,275 s | 1.8× faster |
| CPU time | 322,874 s | 157,013 s | 2.1× less |
| Max memory | 202.1 GB | 60.3 GB | 3.3× less |

Both tools wrote the same VCF, with hash `87ee28d95925da18` for chrX and `e0baf0b3ae88a2d4` for chr1.
