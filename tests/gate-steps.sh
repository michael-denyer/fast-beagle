#!/bin/bash
# The gate's checks, in order, run in the checkout <root>. tests/check-local.sh
# runs them natively and on Linux x86_64 in docker, and CI runs them on each
# runner. Prints one pass or FAIL line per check; each check's output goes to
# build/check-<name>.log.
#
# Usage: [GATE_TIER=pr] tests/gate-steps.sh <root>
# Needs Java 21, htslib, uv, and PLINK2 naming the pinned plink2 binary (see
# tests/check-bgen.sh). GATE_TIER=pr runs the fast pull-request tier: it skips
# the checks that re-prove the Java side of the recorded hashes, the sanitizers,
# the TLA+ model and the thread-seam reruns, and fuzzes 50 examples, not 200.
# The default is the full gate.
# shellcheck disable=SC2329  # java_build, oracle_trace and trace_threads run through step
set -uo pipefail
cd "$1" || exit 1
SEAMS="T1a T1b T1c T1d T2 T2b T3a T3b0 T3b1 T3b T3c T3d T4a T4b T4c T4d T5a T5b T5c T5d"
# Seams whose content depends on nthreads, rechecked at 1 and 18 threads on the
# cases whose windows are long enough for the thread count to split them: the
# cases with per-thread hashes.
THREAD_SEAMS="T3b0 T3b1 T3b T3c T3d T4a T4b T4c T4d"

mkdir -p build
fail=0
tier=${GATE_TIER:-full}
case $tier in full|pr) ;; *) echo "GATE_TIER must be full or pr, not $tier"; exit 2 ;; esac
fuzz_examples=200
[ "$tier" = pr ] && fuzz_examples=50
step() {  # name command...
  local name=$1; shift
  if "$@" > "build/check-$name.log" 2>&1; then
    echo "  pass  $name"
  else
    echo "  FAIL  $name (build/check-$name.log)"; fail=1
  fi
}
full_step() {  # name command...: runs only in the full tier
  if [ "$tier" = full ]; then step "$@"; else echo "  skip  $1 (full tier only)"; fi
}

java_build() {
  mkdir -p build/classes \
    && find java/src -name '*.java' > build/java-sources.txt \
    && javac -nowarn -d build/classes @build/java-sources.txt
}

oracle_trace() {
  mkdir -p build/trace-oracle \
    && tests/check-oracle.sh java -Dbeagle.trace=build/trace-oracle -cp build/java-trace/classes main.Main
}

trace_threads() {
  local t thread_cases
  # shellcheck source=cases.sh
  thread_cases=$(ROOT=$PWD; source tests/cases.sh; cases | while read -r name expect _; do
    if thread_dependent "$expect"; then printf '%s ' "$name"; fi; done) || return 1
  for t in 1 18; do
    # shellcheck disable=SC2086  # the seam list splits into arguments
    NTHREADS=$t CASES="$thread_cases" tests/check-trace.sh $THREAD_SEAMS || return 1
  done
}

step fixtures tests/fetch-fixtures.sh
step cases python3 tests/check_cases.py
step jcompat make check-jcompat
step tracker make check-tracker
step interval make check-interval
full_step oracle-jar tests/check-oracle.sh java -ea -jar data/beagle.27Feb25.75f.jar
full_step failures-jar tests/check-failures.sh java -ea -jar data/beagle.27Feb25.75f.jar
full_step java-build java_build
full_step oracle-source tests/check-oracle.sh java -ea -cp build/classes main.Main
step java-trace make java-trace
full_step oracle-trace oracle_trace
step c-build make build/beagle
step oracle-c tests/check-oracle.sh build/beagle
step failures-c tests/check-failures.sh build/beagle
full_step log tests/check-log.sh
step piece-size make check-piece-size
step bgen-unit make check-bgen-unit
step records make check-records
step vcf-index make check-vcf-index
step tbi make check-tbi
step bgen tests/check-bgen.sh
# shellcheck disable=SC2086  # the seam list splits into arguments
step trace tests/check-trace.sh $SEAMS
full_step sanitizers tests/check-sanitizers.sh
full_step tla tests/check-tla.sh
step fuzz uv run --python 3.12 --script tests/check_fuzz.py --examples "$fuzz_examples"
full_step trace-threads trace_threads
exit $fail
