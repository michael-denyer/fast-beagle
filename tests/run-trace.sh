#!/bin/bash
# Run an implementation on every case in tests/oracle-cases.txt and
# tests/trace-cases.txt, writing each case's trace seams to <outdir>/<case>/
# and its output to <outdir>/<case>/out.log.
# The command's {trace} argument is replaced by that directory.
#
# Usage: tests/run-trace.sh <outdir> <command...>
#   tests/run-trace.sh /tmp/java java -Dbeagle.trace={trace} -cp build/java-trace/classes main.Main
#   tests/run-trace.sh /tmp/c build/beagle trace={trace}
# NTHREADS sets the thread count (default 2). CASES restricts the run to the named
# cases; SKIP leaves the named cases out.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=cases.sh
source "$ROOT/tests/cases.sh"
OUTDIR=$1
shift

check_selection "$ROOT/tests/oracle-cases.txt" "$ROOT/tests/trace-cases.txt" || exit 1
fail=0
while read -r name expected _ args; do
  selected "$name" || continue
  [[ " ${SKIP:-} " == *" $name "* ]] && continue
  dir="$OUTDIR/$name"
  mkdir -p "$dir"
  case_run "$args" "$dir/out" "${NTHREADS:-2}" "${@//\{trace\}/$dir}"
  rc=$?
  # shellcheck disable=SC2010  # the entries are seam file names the traced program writes
  echo "$name exit=$rc $(ls "$dir" | grep -v '^out\.' | tr '\n' ' ')"
  # Oracle rows require success; trace-only rows name their expected exit.
  [[ "$expected" = exit=* ]] || expected=exit=0
  if [ "exit=$rc" != "$expected" ]; then
    echo "FAIL $name exit=$rc, want $expected" >&2
    fail=1
  fi
done < <(cases "$ROOT/tests/oracle-cases.txt" "$ROOT/tests/trace-cases.txt")
exit $fail
