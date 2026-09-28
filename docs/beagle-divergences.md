# How fast-beagle differs from Beagle 5.5

fast-beagle is a C port of Java Beagle 5.5 (`beagle.27Feb25.75f.jar`). Run with the same arguments and the same `nthreads=`, it writes a VCF whose text is byte-identical to Beagle's, header lines included. Everything else on this page is a difference you can see when you switch. It refuses `ped=` and runs without a JVM or a heap limit. It also adds BGEN output, a tabix index and a trace parameter.

## Differences at a glance

| Area | Java Beagle 5.5 | fast-beagle |
|---|---|---|
| VCF text | The reference output | Byte-identical at the same `nthreads=` |
| `.vcf.gz` file bytes | BGZF from Beagle's own writer | BGZF from htslib, so the compressed bytes differ |
| No arguments | Prints the usage text and exits 0 | Prints `missing gt argument` and exits 1 |
| Exit status on error | 1 | 1 |
| `ped=` | Accepted and ignored | Refused |
| Added parameters | None | `bgen=`, `bgen-bits=`, `bgen-min-dr2=`, `bgen-min-maf=`, `bgen-chr-set=`, `tbi=`, `trace=` |
| Default `nthreads=` | The processor count the JVM reports | The processor count `sysconf` reports |
| Memory limit | The JVM heap size (`-Xmx`) | None |
| Requirements | A Java runtime | A native build linked to htslib |
| bref3 files | Read by `ref=`. A separate bref3 jar writes them. | Read by `ref=`. fast-beagle has no bref3 writer. |

## Output files

### The VCF

The decompressed VCF is byte-identical to Beagle's when both run with the same arguments and `nthreads=`. The header is the same too. fast-beagle writes `##source="beagle.27Feb25.75f.jar"`, and `##filedate=` holds the run date in both tools. A downstream tool therefore cannot tell from the header which program wrote the file.

The compressed `.vcf.gz` files differ byte for byte. Beagle compresses with its own BGZF writer and fast-beagle compresses with htslib. Both files are valid BGZF, and `bgzip -t` accepts both. Compare the decompressed text, not the `.vcf.gz` bytes.

### BGEN files and the tabix index

fast-beagle can also write `<out>.bgen`, `<out>.sample`, `<out>.info` and `<out>.vcf.gz.tbi`. Beagle writes none of these. [Parameters and output files](usage.md) describes them.

## No arguments

With no arguments, Beagle prints its usage text and exits with status 0. fast-beagle treats an empty command line like any other command line without `gt=`. It prints `missing gt argument` to standard error and exits with status 1.

## Errors and exit status

Both tools exit with status 1 when they refuse a run.

When a command line has more than one unrecognized parameter, both tools list them in one message. Beagle lists them in hash-map order. fast-beagle lists them in the order you gave them.

A few errors exist only in fast-beagle, such as a refused `ped=` or a failure to start a thread. Their messages start with `beagle-c:`.

## Parameters

fast-beagle accepts every parameter that Beagle's parser accepts, with the same default, the same valid range and the same meaning. That includes the parameters Beagle's usage text leaves out (`initial-lr`, `step-scale`, `rare`, `imp-segment`, `imp-step`, `imp-nsteps`, `buffer` and `truth`). The one exception is `ped=`. Beagle checks that the file exists and then ignores it. fast-beagle stops with `beagle-c: the ped= parameter is not supported`. Remove `ped=` from a Beagle command line before you run it with fast-beagle.

fast-beagle adds these parameters. Beagle refuses each of them as an unrecognized parameter.

| Parameter | Effect |
|---|---|
| `bgen=`, `bgen-bits=`, `bgen-min-dr2=`, `bgen-min-maf=`, `bgen-chr-set=` | Write BGEN v1.2 files next to the VCF. See [BGEN output](usage.md#bgen-output). |
| `tbi=true` | Writes `<out>.vcf.gz.tbi`. See [Tabix index](usage.md#tabix-index). |
| `trace=<dir>` | Writes internal trace files to an existing directory, for comparison with a traced Java build. See [Compare trace seams](testing.md#compare-trace-seams). |

## Threads

Beagle's output depends on `nthreads=` when a window is longer than 4 cM. fast-beagle reproduces that dependence, so its VCF matches Beagle's run with the same `nthreads=`, and a run at another thread count can differ from both. See [Thread count](usage.md#thread-count).

Without `nthreads=`, both tools use the processor count. Beagle reads it from the JVM and fast-beagle reads it from `sysconf`. To reproduce a Beagle run exactly, set `nthreads=` to the value in the Beagle log's command line.

## Runtime and memory

fast-beagle is a native program. It needs no Java runtime and no `-Xmx` setting. The build needs a C11 compiler, `make` and htslib, and the binary links to htslib at run time. See [Install](../README.md#install). The [pre-merge gate](testing.md#run-the-pre-merge-gate) builds and tests it on macOS arm64 and on Linux x86_64.

The JVM's maximum heap caps Beagle's memory. Without `-Xmx`, the JVM sets the cap itself. On a 64 GB machine it chose 16 GB, and Beagle's log showed the command line as `java -Xmx16384m`. fast-beagle has no such cap. [Performance](perf-baseline.md) compares the two tools' wall time, CPU time and max memory, from a 321-sample benchmark to an imputation of about 100,000 samples.

## Input files

fast-beagle opens `gt=` and `ref=` files with Beagle's rules. The rules cover gzip and BGZF detection, bref3 references and the reference file-name extensions. A bref3 reference can give different imputed values than a VCF of the same panel in both tools. See [Reference panels in bref3 format](usage.md#reference-panels-in-bref3-format).

fast-beagle has no bref3 writer. To convert a VCF reference to bref3, use Beagle's `bref3.27Feb25.75f.jar`.
