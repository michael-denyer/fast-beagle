# Performance

This page compares `build/beagle` with Java Beagle 5.5 (`beagle.27Feb25.75f.jar`). Both tools write the same VCF, so the comparison is of time and memory only. The gain grows with the size of the imputation.

| Run | Target samples | Threads | Faster | Less CPU time | Less max memory |
|---|---|---|---|---|---|
| [1000 Genomes chr20](#1000-genomes-chr20-benchmark) | 321 | 18 | 1.5× to 1.9× | 2.0× to 2.1× | 2.2× to 3.0× |
| [Production scale](#production-scale-run) | about 100,000 | 60 | 3.1× | 2.3× | 3.5× |

The chr20 ranges span two runs on different days. The chr20 benchmark uses public data, so anyone can rerun it.

## Production-scale run

This run imputed one chromosome for about 100,000 target samples and wrote about 13 GB of compressed VCF. It ran on a Databricks node of type `Standard_E64ds_v6`, which has 64 vCPUs (Intel Xeon Platinum 8573C) and 512 GiB of memory, with Databricks Runtime 16.4 LTS on Ubuntu 24.04. Both tools ran with `nthreads=60`, and both wrote the same VCF. The figures cover the Beagle step alone, one run per tool on 2026-09-28. The input data is not public, so this run cannot be reproduced from this repository.

| | Java | C | Java / C |
|---|---|---|---|
| Wall time | 884 s | 288 s | 3.1× faster |
| CPU time | 30,420 s | 13,499 s | 2.3× less |
| Max memory | 296.4 GB | 84.3 GB | 3.5× less |

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
