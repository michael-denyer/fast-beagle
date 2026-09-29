#!/bin/bash
# Runs Java Beagle and build/beagle on each oracle case and compares their
# <out>.log files. Timings, timestamps, out= and the lines that name the program are
# masked, and build/beagle's added CPU time and max memory lines are dropped;
# every other line must match. build/beagle's standard output must equal its
# log, and a run that fails on a malformed reference must print one error
# message and end its log with it, even when every parse worker fails at once.
#
# Usage: tests/check-log.sh    (after make build/beagle)
# CASES restricts the run to the named cases (default all); NTHREADS sets the
# thread count (default 2).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=cases.sh
source "$ROOT/tests/cases.sh"
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
JAVA_BEAGLE=(java -ea -jar "$DATA/beagle.27Feb25.75f.jar")
T=${NTHREADS:-2}

mask() {  # log
  sed -E \
    -e '/^Enter "java -jar /d' \
    -e '/^(CPU time|Max memory): /d' \
    -e 's/^(beagle\.27Feb25\.75f\.jar|fast-beagle: a C port of beagle\.27Feb25\.75f\.jar) \(version 5\.5\)$/<banner>/' \
    -e 's/^(Start|End) time: .*/\1 time: <time>/' \
    -e 's/^Command line: .*/Command line: <program>/' \
    -e 's/^  out=.*/  out=<out>/' \
    -e 's/^(beagle\.27Feb25\.75f\.jar|fast-beagle) finished$/<program> finished/' \
    -e 's/^(.{31})([0-9]+ hours? )?([0-9]+ minutes? )?[0-9]+ seconds?$/\1<elapsed>/' \
    "$1"
}

check_selection "$ROOT/tests/oracle-cases.txt" || exit 1
fail=0
while read -r name _ _ args; do
  selected "$name" || continue
  j="$OUT/$name.java" c="$OUT/$name.c"
  case_run "$args" "$j" "$T" "${JAVA_BEAGLE[@]}"
  case_run "$args" "$c" "$T" "$ROOT/build/beagle"
  if [ ! -s "$j.log" ]; then
    echo "FAIL $name: Java Beagle wrote no log"; tail -3 "$j.run.log"; fail=1
  elif [ ! -s "$c.log" ]; then
    echo "FAIL $name: build/beagle wrote no log"; tail -3 "$c.run.log"; fail=1
  elif ! cmp -s "$c.log" "$c.run.log"; then
    echo "FAIL $name: build/beagle's standard output differs from its log"
    diff "$c.log" "$c.run.log" | head -10; fail=1
  elif ! diff <(mask "$j.log") <(mask "$c.log") > "$OUT/$name.diff"; then
    echo "FAIL $name: the logs differ"; head -20 "$OUT/$name.diff"; fail=1
  else
    echo "PASS $name nthreads=$T $(wc -l < "$c.log" | tr -d ' ') lines"
  fi
done < <(cases)

# A run that fails after the log exists prints one error message, and its log
# ends with that message. bad-alleles makes every parse worker fail at once.
check_bad_ref() {  # label ref
  local label=$1 out="$OUT/$1" rc
  "$ROOT/build/beagle" gt="$DATA/target.vcf.gz" ref="$2" out="$out" nthreads=18 > /dev/null 2> "$out.err"
  rc=$?
  if [ "$rc" -ne 1 ] || [ "$(wc -l < "$out.err")" -ne 1 ] || [ "$(tail -1 "$out.log")" != "$(cat "$out.err")" ]; then
    echo "FAIL $label: exit=$rc, log ends '$(tail -1 "$out.log")', stderr:"; head -c 600 "$out.err"; echo; fail=1
  else
    echo "PASS $label: the log ends with '$(cat "$out.err")'"
  fi
}
if [ -z "${CASES:-}" ]; then
  echo junk | gzip > "$OUT/junk.vcf.gz"
  check_bad_ref bad-ref "$OUT/junk.vcf.gz"
  gzip -dc "$DATA/ref.vcf.gz" | awk 'BEGIN {OFS = "\t"} /^#/ {print; next} {$NF = "7|7"; print}' | gzip > "$OUT/bad-alleles.ref.vcf.gz"
  check_bad_ref bad-alleles "$OUT/bad-alleles.ref.vcf.gz"
fi
exit $fail
