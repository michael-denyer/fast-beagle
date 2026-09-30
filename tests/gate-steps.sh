#!/bin/bash
# The gate's checks, in order, run in the checkout <root>. tests/check-local.sh
# runs them natively and on Linux x86_64 in docker, and CI runs them on each
# runner. Prints one pass or FAIL line per check; each check's output goes to
# build/check-<name>.log, or build/check-c-<name>.log in the C tier.
#
# Usage: [GATE_TIER=c] [GATE_GROUP=<group>] [GATE_FUZZ=random] [GATE_LIST=1]
#   [GATE_LIST_GROUPS=1 GATE_PLATFORM=darwin|linux]
#   tests/gate-steps.sh <root>
# Needs Java 21, htslib and uv; the full tier also needs PLINK2 naming the
# pinned plink2 binary (see tests/check-bgen.sh). GATE_TIER=c runs only the checks that compare the C
# binary against recorded results; Java then only builds the bref3 fixtures.
# It skips every check that runs Java or the jar alongside it, the
# fixture-cache check and the TLA+ model. It checks the
# BGEN output against the hashes in tests/bgen-hashes.txt instead of
# plink2, and runs the saved fuzz regressions but no new fuzz
# examples. The default is the full gate. GATE_FUZZ=random fuzzes new examples
# instead of the fixed 200.
#
# Each check names its group. GATE_GROUP selects one declared group, so CI can
# run the groups as parallel jobs; the setup checks run in every selected group.
# GATE_LIST_GROUPS=1 lists runnable, non-setup groups for an explicit tier and
# platform without creating files. The default, all,
# runs every check in order. The tsan check runs on macOS only and prints a
# skip line elsewhere. GATE_LIST=1 prints the group and name of each check the
# tier and group select, without running it.
# shellcheck disable=SC2329  # java_build, oracle_trace and trace_threads run through step
set -uo pipefail
cd "$1" || exit 1
SEAMS="T1a T1b T1c T1d T2 T2b T3a T3b0 T3b1 T3b T3c T3d T4a T4b T4c T4d T5a T5b T5c T5d"
# Seams whose content depends on nthreads, rechecked at 1 and 18 threads on the
# cases whose windows are long enough for the thread count to split them: the
# cases with per-thread hashes.
THREAD_SEAMS="T3b0 T3b1 T3b T3c T3d T4a T4b T4c T4d"

fail=0
tier=${GATE_TIER:-full}
case $tier in full|c) ;; *) echo "GATE_TIER must be full or c, not $tier"; exit 2 ;; esac
group=${GATE_GROUP:-all}
list_groups=${GATE_LIST_GROUPS:-}
platform=${GATE_PLATFORM:-}
if [ "$list_groups" = 1 ]; then
  case $platform in darwin|linux) ;; *) echo "GATE_PLATFORM must be darwin or linux when listing groups"; exit 2 ;; esac
fi
bgen_oracle=live logs=build/check-
[ "$tier" = c ] && bgen_oracle=recorded logs=build/check-c-
fuzz_args=(--examples 200)
case ${GATE_FUZZ:-fixed} in
  fixed) ;;
  random) fuzz_args+=(--random) ;;
  *) echo "GATE_FUZZ must be fixed or random, not $GATE_FUZZ"; exit 2 ;;
esac
in_group() { [ "$group" = all ] || [ "$1" = setup ] || [ "$1" = "$group" ]; }
step() {  # group name command...
  local owner=$1 name=$2; shift 2
  if [ "${discovering:-}" = 1 ]; then
    [ "$owner" = setup ] || declared_groups+=("$owner")
    return 0
  fi
  if [ "$owner" = tsan ] && [ "$(uname -s)" != Darwin ]; then
    in_group "$owner" && [ "${GATE_LIST:-}" != 1 ] && echo "  skip  $name (macOS only)"
    return 0
  fi
  in_group "$owner" || return 0
  if [ "${GATE_LIST:-}" = 1 ]; then echo "$owner $name"; return 0; fi
  if "$@" > "$logs$name.log" 2>&1; then
    echo "  pass  $name"
  else
    echo "  FAIL  $name ($logs$name.log)"; fail=1
  fi
}
planned_step() {  # platform group name command...; platform constrains CI planning only
  local planned_platform=$1; shift
  if [ "${discovering:-}" = 1 ] && [ -n "${plan_platform:-}" ] &&
     [ "$planned_platform" != "$plan_platform" ]; then
    return 0
  fi
  step "$@"
}
full_step() {  # group name command...: runs only in the full tier
  if [ "$tier" = full ]; then
    step "$@"
  elif [ "${discovering:-}" != 1 ] && in_group "$1" && [ "${GATE_LIST:-}" != 1 ]; then
    echo "  skip  $2 (full tier only)"
  fi
}
planned_full_step() {  # platform group name command...; platform constrains CI planning only
  local planned_platform=$1; shift
  if [ "$tier" = full ]; then
    planned_step "$planned_platform" "$@"
  elif [ "${discovering:-}" != 1 ] && in_group "$1" && [ "${GATE_LIST:-}" != 1 ]; then
    echo "  skip  $2 (full tier only)"
  fi
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

checks() {
step setup fixtures tests/fetch-fixtures.sh --ensure
step core gate-tier tests/check-gate-tier.sh
step core log-recording python3 tests/check_log_recording.py
planned_full_step linux cases cases python3 tests/check_cases.py
full_step core jcompat make check-jcompat
step core tracker make check-tracker
step core interval make check-interval
step core block-reader make check-block-reader
step core snv-perms make check-snv-perms
full_step java oracle-jar tests/check-oracle.sh java -ea -jar data/beagle.27Feb25.75f.jar
full_step java failures-jar tests/check-failures.sh java -ea -jar data/beagle.27Feb25.75f.jar
full_step java log-jar tests/check-log.sh java -ea -jar data/beagle.27Feb25.75f.jar
full_step java java-build java_build
full_step java oracle-source tests/check-oracle.sh java -ea -cp build/classes main.Main
full_step java java-trace make java-trace
full_step java oracle-trace oracle_trace
step setup c-build make build/beagle
step core oracle-c tests/check-oracle.sh build/beagle
step core gate-planning tests/check-gate-planning.sh
step core failures-c tests/check-failures.sh build/beagle
step core output-failures python3 tests/check_output_failures.py build/beagle
step core log-c tests/check-log.sh build/beagle
step core piece-size make check-piece-size
step core bgen-unit make check-bgen-unit
step core records make check-records
step core bgen-files make check-bgen-files
step core vcf-index make check-vcf-index
step core tbi make check-tbi
step bgen bgen env BGEN_ORACLE="$bgen_oracle" tests/check-bgen.sh
# shellcheck disable=SC2086  # the seam list splits into arguments
full_step java trace tests/check-trace.sh $SEAMS
step sanitizers sanitizers tests/check-sanitizers.sh
planned_step darwin tsan tsan tests/check-tsan.sh
full_step core tla tests/check-tla.sh
full_step core fuzz uv run --python 3.12 --script tests/check_fuzz.py "${fuzz_args[@]}"
if [ "$tier" = c ]; then
  step core fuzz-regressions uv run --python 3.12 --script tests/check_fuzz.py --examples 0 --invalid-examples 0
fi
full_step java trace-threads trace_threads
}

# Discover group names by evaluating the check declarations in dry-run mode.
# This keeps selector validation and CI planning tied to the declarations
# above, including checks added later such as PR-only checks.
declared_groups=()
declaring_tier=$tier
tier=full
discovering=1
checks
discovering=
tier=$declaring_tier
known_groups=" ${declared_groups[*]} "
if [ "$group" != all ] && [[ "$known_groups" != *" $group "* ]]; then
  echo "GATE_GROUP '$group' is not declared by tests/gate-steps.sh" >&2
  exit 2
fi

if [ "$list_groups" = 1 ]; then
  declared_groups=()
  plan_platform=$platform
  tier=$declaring_tier
  discovering=1
  checks
  seen_groups=" "
  for owner in "${declared_groups[@]}"; do
    [[ "$seen_groups" == *" $owner "* ]] && continue
    printf '%s\n' "$owner"
    seen_groups+="$owner "
  done
  exit 0
fi

mkdir -p build
checks
exit $fail
