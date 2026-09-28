# How fast-beagle differs from Beagle 5.5

fast-beagle is a C port of Java Beagle 5.5 (`beagle.27Feb25.75f.jar`). Run with the same arguments and the same `nthreads=`, it writes a VCF whose text is byte-identical to Beagle's, header lines included. Everything else on this page is a difference you can see when you switch. fast-beagle writes no log file and prints nothing while it runs. Its error messages carry the same text without Java's exception class, stack trace or usage text. It refuses `ped=` and runs without a JVM or a heap limit. It also adds BGEN output, a tabix index and a trace parameter.

## Differences at a glance

| Area | Java Beagle 5.5 | fast-beagle |
|---|---|---|
| VCF text | The reference output | Byte-identical at the same `nthreads=` |
| `.vcf.gz` file bytes | BGZF from Beagle's own writer | BGZF from htslib, so the compressed bytes differ |
| `<out>.log` | Written on every run that passes parameter checks | Not written |
| Standard output | Banner, command line, sample and marker counts, estimated `ne` and `err`, timings | Nothing |
| No arguments | Prints the usage text and exits 0 | Prints `missing gt argument` and exits 1 |
| Error output | Message, often with the exception class and a stack trace | The message only |
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

### The log file

Beagle writes `<out>.log`, a copy of everything it prints to standard output. fast-beagle writes no log file. Beagle also creates `<out>.log` for a run that fails after the parameter checks, such as a run with a `ref=` file that it cannot read.

### BGEN files and the tabix index

fast-beagle can also write `<out>.bgen`, `<out>.sample`, `<out>.info` and `<out>.vcf.gz.tbi`. Beagle writes none of these. [Parameters and output files](usage.md) describes them.

## Console output

Beagle prints its progress to standard output as it runs. The output starts with the program name, the copyright line and the start time. It then lists the command line, with `nthreads=` added when you did not set it. It prints the sample counts, the markers in each window, and the estimated `ne` and `err`. It times each burn-in and phasing iteration and each imputation step, and ends with the total times and the end time.

fast-beagle prints nothing to standard output. A successful run is silent, and fast-beagle does not report the estimated `ne` and `err`.

With no arguments, Beagle prints its usage text and exits with status 0. fast-beagle treats an empty command line like any other command line without `gt=`. It prints `missing gt argument` to standard error and exits with status 1.

## Errors and exit status

Both tools exit with status 1 when they refuse a run. fast-beagle prints the same message text as Beagle, on standard error. It leaves out the lines Beagle adds around that message:

- For a parameter error, Beagle prints the message after `Exception in thread "main" java.lang.IllegalArgumentException:` and follows it with a stack trace.
- For an input file that does not exist, Beagle adds `java.lang.Throwable: File does not exist` and a stack trace.
- For an unrecognized parameter, a missing input file and several input errors, Beagle ends with a blank line and `Terminating program.`
- For an `out=` that is a directory or names an input file, Beagle prints the full usage text before the message.
- For a `window=` less than 1.1 times `overlap=`, Beagle prints its banner before the message and `Exiting program.` after it.

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
