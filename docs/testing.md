# Checks and the pre-merge gate

Most checks compare fast-beagle with Beagle 5.5 or with a tool whose output it must match. The unmodified Java source in `java/src/` and the release jar are the oracle. [Byte identity with Beagle 5.5](byte-identity.md) summarises what these checks prove and where the proof stops.

## Check an implementation

`tests/check-oracle.sh` takes the command of any implementation. To check the release jar:

```bash
tests/check-oracle.sh java -ea -jar data/beagle.27Feb25.75f.jar
```

To check fast-beagle, run `tests/check-oracle.sh build/beagle`.

## Fixtures

`tests/fetch-fixtures.sh` downloads Beagle's public test data and release jars, verifies checksums, and derives the fixtures that the case tables run. The fixtures include:

- the reference/target split
- chrX with haploid samples
- multiallelic markers
- missing genotypes
- a genetic map on which the region spans 5 cM (5 windows with `window=1.5 overlap=0.5`)
- a target with a 50 kb gap in its markers
- exclusion lists
- bref3 references, one of them with END= on SNV and indel records
- a bref3 edge case (IDs with a 4-byte character, an invalid byte and two entries, a marker with no ALT allele, a symbolic allele)
- for `tests/check-bgen.sh`, the chrX split moved to chromosome 22 and the reference/target split moved to chromosome 38

## Oracle hashes

`tests/check-oracle.sh` runs an implementation on the fixtures at 1, 2 and 18 threads and compares its output with the hashes in `tests/oracle-cases.txt`. `NTHREADS` overrides the thread counts.

- `CASES="gt imp"` restricts the run. A name that is not in the case tables fails the run. The same holds for the sanitizer, trace and BGEN runners.
- Beagle's output depends on the thread count when a window is longer than 4 cM. Such cases record one hash per thread count, as `thread:hash` pairs.

## Case tables

Every case table row holds a name, the expected outcome, tags and Beagle's arguments. The expected outcome is a hash, or `exit=N` where the row records no hash. The tags (`nonautosome`, `multiallelic`) tell `tests/check-bgen.sh` how plink2 reads the output.

- `tests/cases.sh` reads the tables. It holds the one verdict that `tests/check-oracle.sh`, `tests/check-sanitizers.sh` and `tests/check-bgen.sh` apply to a run. The verdict requires the expected exit and, for a case with a hash, the hash for the run's thread count.
- `tests/cases.sh` also holds the one refusal rule that `tests/check-failures.sh` and `tests/check-bgen.sh` apply. The rule requires exit 1, the expected message, and no file at the paths the caller lists.
- `tests/check_cases.py` tests the verdict and the refusal rule with a fake Beagle.

## Log and console output

`tests/check-log.sh <command...>` runs an implementation on each oracle case at `nthreads=2` and compares its `<out>.log` with Beagle's recorded log in `tests/logs/<case>.log`. It masks the timings, the start and end times, the data directory, `out=` and the lines that name the program, and drops fast-beagle's `CPU time:` and `Max memory:` lines. Every other line must match. For fast-beagle, standard output must also equal the log. A run that fails on a malformed reference must print one error message and end its log with it, including at `nthreads=18` on a reference where every record is malformed, so every parse worker fails at once. `CASES` restricts the cases. The gate runs it twice. `log-jar` proves the recorded logs against the jar in the full tier, and `log-c` checks `build/beagle` in both tiers. After a change to the report, rewrite the recorded logs from the jar:

```bash
RECORD=1 tests/check-log.sh java -ea -jar data/beagle.27Feb25.75f.jar
```

Every log run must also pass its recorded exit and VCF hash checks. Recording stages the new logs and replaces `tests/logs/` only after all checks pass, so logs of removed cases go too. `tests/check_log_recording.py` verifies that failed runs and wrong VCF hashes preserve the previous recordings.

## Refused inputs

`tests/check-failures.sh` runs an implementation on arguments and inputs that Beagle refuses. Each run must exit 1 with Java's message. The cases are:

- an `out=` that names the `gt=` or `ref=` file or a directory. A refused `out=` must leave the input unchanged and write no VCF.
- `window` less than 1.1 times `overlap`
- `imp-segment` below half of `imp-step`
- genetic map files that Beagle rejects:
  - genetic positions that are all equal
  - an infinite position
  - a repeated base position
  - descending positions
  - lines with too few or too many fields
  - no map for the target's chromosome
- a one-character non-ASCII GT allele
- a bref3 SNV allele code whose permutation index is negative
- a bref3 header whose sample count overflows when doubled. This case runs for the C build only, because the jar's result depends on its heap size.

`tests/check_output_failures.py build/beagle` checks that log, VCF, BGEN and tabix destinations refuse collisions with input files before writing. It covers both BGEN modes, the tabix index, relative paths, symbolic links and hard links. It also checks that disabled outputs do not cause refusals, that nonfinite phased BGEN probabilities fail with a message and leave no BGEN files, and that a large `ne=` saturates the reported population size as Java does. The gate runs these checks normally and under the sanitizers, with leak detection off for the expected failures.

## Compare trace seams

`java/trace.patch` holds trace hooks for the Java source. `make java-trace` applies the patch to a copy in `build/java-trace/`. When that build runs with `-Dbeagle.trace=<dir>`, it writes each trace seam to `<dir>/<seam>.txt`. To change the hooks, edit a patched copy and regenerate the patch with `diff -ruN` against `java/src`.

- `tests/run-trace.sh` runs an implementation on every case with tracing on, so two runs can be compared with `diff -r`.
- `tests/check-trace.sh <seam...>` runs the Java trace build and `build/beagle` on every case, including the input edge cases in `tests/trace-cases.txt`, and compares the named trace seams.

## Piece size check

`make check-piece-size` (`tests/check-piece-size.sh`) checks the imputation writer's split of a long cluster. The writer splits a long cluster into work items of at most `PIECE_RECORDS` reference markers (500). `PIECE_RECORDS` is a tuning value that must not change the output.

The check builds `build/beagle-piece1` with one marker per work item. It runs `build/beagle-piece1` and `build/beagle` on every oracle case with `ref=` at 2 and 18 threads. Both must write the same VCF and the same trace seam T5d. The VCF alone would miss a split cluster whose pieces do not use the whole cluster's hash, because rounding to printed precision hides the difference. T5d shows it.

## Unit checks

- `make check-jcompat` compares each Java library reproduction in `src/jcompat/` against output printed by real Java (`tests/jcompat/JcompatFixtures.java`), including DecimalFormat's NaN and infinity output.
- `make check-interval` tests `src/vcf/interval_it.c` over an in-memory record source (`tests/vcf/interval_it_test.c`).
- `make check-records`: `tests/output/record_fixture.c` writes phased, imputed, genotyped, haploid and multiallelic records through the window writer with no BGEN and in both `bgen=` modes. `tests/check_records.py` requires the same VCF from all three runs and the expected VCF fields. It also requires phased BGEN probabilities captured before the VCF rounds them.
- `make check-tracker` tests the composite haplotype tracker in `src/beagleutil/comp_hap_queue.c` through the interface every caller uses (`tests/beagleutil/tracker_test.c`).
- `make check-bgen-unit` tests:
  - the scaling rule, exactly (`tests/bgen/quantise_test.c`)
  - the packing of values at 1 to 16 bits (`tests/bgen/pack_test.c`)
  - the reading of INFO entries behind the `.info` and `bgen-min-dr2`, including keys that prefix longer keys (`tests/bgen/info_test.c`)

## Tabix index checks

`make check-vcf-index` writes synthetic VCFs with one and four BGZF threads and requires `src/main/vcf_index.c` to write the same `.tbi` bytes as htslib's `tbx_index_build3` (`tests/output/vcf_index_test.c`). The synthetic VCFs cover:

- three chromosomes
- lines longer than a block
- lines and a header ending exactly on a block boundary
- a multi-base REF
- INFO END= variants
- a header-only file

`make check-tbi` (`tests/check-tbi.sh`) runs `build/beagle` with `tbi=true` on four oracle cases at 1 and 18 threads. The VCF must keep its oracle hash and match a run without `tbi=true`. The `.tbi` must match `tbx_index_build3`'s byte for byte.

## BGEN checks

`tests/check-bgen.sh` runs `build/beagle` with `bgen=plink2` on every case in `tests/oracle-cases.txt` and `tests/bgen-cases.txt`, with and without the filters. The cases in `tests/bgen-cases.txt` have no oracle hash and run on fixtures moved to chromosomes 22 and 38.

Some cases run again at 1, 3, 12 and 16 bits and with `bgen-chr-set=38`. The `bgen-chr-set=38` runs use the `imp` fixture moved to chromosome 38, and `imp-chroms`, whose chromosome 23 is then an autosome. The script runs plink2 with the same `bits=` on the resulting VCF and compares the `.bgen` and `.sample` with `cmp`. It checks that the cases tagged `nonautosome` fail in both tools.

It also runs every case with `bgen=phased`, and some cases with `bgen=phased` at other bit depths. `tests/check_bgen_phased.py` then checks the BGEN against the VCF for:

- the same records
- certain GT alleles where the VCF has no DS
- each haplotype's GT allele as its most probable
- dosages within one stored unit per haplotype of DS, AP1 and AP2, at any bit depth

plink2 must load the BGEN of every autosomal case.

In both modes, `tests/check_bgen_reader.py` checks that [bgen-reader](https://pypi.org/project/bgen-reader/) 4.0.9 decodes every `.bgen` to the same variants, ploidy, phased flag and probabilities as our own decoder. The live checks need [uv](https://docs.astral.sh/uv/) on `PATH` and fail without it. `tests/check_bgen_info.py` checks that the `.info` has one row per BGEN variant and that each row copies the variant's VCF record.

Failed runs must leave no `.bgen`, `.sample` or `.info`. The rule covers runs that fail when the writer opens, when the VCF cannot be opened, and after records are written. `bgen-bits` values outside 1 to 16 or without `bgen=` must fail with a message. Every such refusal must exit 1.

### Recorded BGEN hashes

`tests/bgen-hashes.txt` records the SHA-256 prefixes of the `.bgen`, `.sample` and `.info` of every run above. Every run must match its row. `BGEN_ORACLE=recorded tests/check-bgen.sh` checks these hashes instead of running plink2, bgen-reader and the Python checks, so it needs neither plink2 nor uv. It still checks each run's exit status, its VCF oracle hash and the refusals, and the C tier of the gate runs it that way. After a change to the BGEN output, rewrite the table with the live checks:

```bash
RECORD=1 PLINK2=/path/to/plink2 tests/check-bgen.sh
```

The script writes the table only when plink2, bgen-reader and our own decoder accept every file.

### Pinned plink2 build

The live checks need `PLINK2` naming the pinned plink2 binary, and fail without it. The pinned build is PLINK v2.0.0-a.7.8 (19 Sep 2026), source tag `v2.0.0-a.7.8`, commit `d293523ae31bfd10f3e8461084ee53e398705ee5`:

- macOS arm64: `plink2_mac_arm64_20260919.zip`, SHA-256 `04be4b865ad4b79a61b61ba2eb7468b4dbf62674dc5f7c94484fe0e5471539e4`.
- Linux x86_64: `plink2_linux_x86_64_20260919.zip`, SHA-256 `7ded2a083cf6863e997099d1adf5e4b86ad6b5112d2934e2b020cfd77f9bdaeb`.

## Sanitizers

`tests/check-sanitizers.sh` builds `build/beagle` and the unit tests of `make check-bgen-unit`, `make check-records` and `make check-tracker` with AddressSanitizer and UndefinedBehaviorSanitizer in `build/san`. It runs those tests. It then runs every oracle case at 1 and 2 threads as VCF only, with `bgen=plink2` and with `bgen=phased`. The `bgen=plink2` runs skip the cases tagged `nonautosome`. Every run must exit 0 with the oracle hash and no sanitizer report.

- On Linux, LeakSanitizer also runs, so any memory still allocated at a normal exit fails the check. LeakSanitizer does not support macOS arm64.
- On macOS, the script then builds `build/beagle` with ThreadSanitizer in `build/tsan`. It runs every oracle case at 18 threads, and runs the cases with per-thread hashes again with `trace=`. ThreadSanitizer runs on macOS only, because it cannot start under the x86_64 emulation of the gate's docker leg.

## Differential fuzzing

`tests/check_fuzz.py` runs differential fuzzing with [Hypothesis](https://hypothesis.readthedocs.io/).

- It generates small target VCFs. Some examples also get a reference panel, a genetic map and options (windows, iterations, states, imputation, `gp`/`ap`, and `bgen=` for the C run). It runs the release jar and `build/beagle` with the same seed. Both must fail, or both must write the same VCF. Where Java repeats without end a window that cannot advance, `build/beagle` must instead exit with its "does not advance" error.
- Invalid-parameter examples then change one parameter of a generated input so that Beagle refuses it. Both tools must exit 1 with the same message and leave the inputs unchanged. Java may prefix the message with the exception class. The change is one of:
  - `out` naming an input or a directory
  - `window` below 1.1 times `overlap`
  - a value out of bounds or not a number
  - an unknown parameter
- The script shrinks a failure to a small input and saves it in `build/fuzz-fail` with both commands. Inputs from past failures go in `tests/fuzz-regressions/`, which runs first.
- The full tier runs a fixed set of 200 examples (about 30 s per 100 on an M5) and 2 for each invalid-parameter change. The nightly CI run fuzzes 200 new examples. `uv run --python 3.12 --script tests/check_fuzz.py --examples 1000 --random` tries new ones.

## Model check the pipelined writer

`tests/check-tla.sh` model-checks [tla/ParallelOrdered.tla](../tla/ParallelOrdered.tla), the protocol of `parallel_ordered` (the pipelined imputed writer). It runs TLC from tla2tools.jar v1.7.4 for several worker counts, item counts and windows. It checks that:

- at most `window` items are claimed but not consumed
- no slot is overwritten before it is consumed
- items are consumed in order
- there is no deadlock
- every run finishes with every item consumed

The model represents condition-variable waits with wait sets and spurious wakeups, so a lost wakeup fails the check.

## Benchmark

`tests/bench/` holds the 1000 Genomes chr20 benchmark. `fetch-chr20.sh <dir>` downloads and derives the inputs, and `bench.sh <dir> <rounds>` times Java and C alternately. [perf-baseline.md](perf-baseline.md) has the method and the current result.

## Run the pre-merge gate

`tests/gate-steps.sh` holds the gate's list of checks. It needs Java 21, htslib and uv. The full tier also needs `PLINK2` naming the [pinned plink2 build](#pinned-plink2-build).

The script has two tiers. The full tier, the default, runs every check. `GATE_TIER=c` runs the C tier, which compares `build/beagle` against recorded results only. Java then only builds the bref3 fixtures. The C tier skips every check that runs Java or the jar next to the C binary (`jcompat`, `oracle-jar`, `failures-jar`, `java-build`, `oracle-source`, `java-trace`, `oracle-trace`, `log-jar`, `trace`, `fuzz` and `trace-threads`), the fixture-cache check `cases` and the TLA+ model check. It runs the [sanitizers](#sanitizers). Its `bgen` step checks the BGEN output against `tests/bgen-hashes.txt` instead of plink2 ([recorded hashes](#recorded-bgen-hashes)). It runs the saved fuzz regressions in `tests/fuzz-regressions/` as `fuzz-regressions`. It prints a `skip` line for each check it leaves out. `GATE_FUZZ=random` makes the full tier fuzz 200 new examples instead of the fixed 200.

Each check belongs to one group, so CI can run the groups as parallel jobs. `GATE_GROUP` selects a group. The default, `all`, runs every check in order.

| Group | Checks |
| --- | --- |
| `setup` | `fixtures` and `c-build`. They run in every group, because every other group needs the fixtures and the `bgen`, `trace`, `trace-threads` and C-binary checks need `build/beagle`. |
| `core` | `gate-tier`, `log-recording`, `cases`, `jcompat`, `tracker`, `interval`, `oracle-c`, `failures-c`, `output-failures`, `log-c`, `piece-size`, `bgen-unit`, `records`, `vcf-index`, `tbi`, `tla`, `fuzz` and `fuzz-regressions` |
| `bgen` | `bgen` |
| `java` | `oracle-jar`, `failures-jar`, `log-jar`, `java-build`, `oracle-source`, `java-trace`, `oracle-trace`, `trace` and `trace-threads` |
| `sanitizers` | `sanitizers`, which builds its own binaries in `build/san` and `build/tsan` |

`GATE_LIST=1` prints the group and name of each check that the tier and group select, and runs none of them.

`tests/check-local.sh` is the pre-merge gate. It runs the lint hooks once, then every check in `tests/gate-steps.sh` natively and on Linux x86_64 in docker. On each platform it runs the full tier, then the C tier without plink2, as CI runs it on pull requests. It prints one pass or fail line per check. The C tier writes its logs to `build/check-c-<name>.log`.

```bash
tests/check-local.sh
```

Two GitHub Actions workflows define the same checks:

- `.github/workflows/gate.yml` runs `tests/gate-steps.sh` on GitHub-hosted `macos-latest` (arm64) and `ubuntu-latest` (x86_64) runners. Its `check` jobs run one job for each runner and group, `check (<runner>, <group>)`. The C tier runs no `java` jobs, because every check in that group is full-tier only. Pushes to `main` run the C tier. A pull request runs no checks when it changes only documentation: files under `docs/`, Markdown files, images and `LICENSE`. It runs the C tier when every other changed file is under `src/` (except `src/jcompat/`) or `third_party/`, and the full tier otherwise, so a change to any test script or table runs the full tier. `tests/gate-tier.sh` holds that rule, and the `gate-tier` step checks it with `tests/check-gate-tier.sh`. Manual runs use the full tier with random fuzz examples. The nightly run does the same, and skips itself when `main` has not moved since the last nightly run that passed.
  - The `gate` job is the one check that a pull request must pass. It passes when every `check` job passed, or when the plan ran no checks. It fails in every other case, including a failed or cancelled plan.
- `.github/workflows/lint.yml` runs every hook in `.pre-commit-config.yaml` on the macOS runner.

## Run the lint hooks

`.pre-commit-config.yaml` runs actionlint, zizmor, shellcheck, ruff, typos, markdownlint and the standard file checks. It skips `third_party/`, `java/src/` and `src/jcompat/fdlibm/`, which stay as upstream wrote them. Install [prek](https://github.com/j178/prek) (`brew install prek`), then:

```bash
prek install              # run the hooks on every commit
prek run --all-files      # run them on the whole tree
```
