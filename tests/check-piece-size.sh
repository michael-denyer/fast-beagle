#!/bin/bash
# Run two builds of the port that differ only in PIECE_RECORDS, the most
# reference markers in one imputation work item, on every imputation case in
# tests/oracle-cases.txt, and require the same VCF and the same trace seam T5d.
# A split cluster must use the whole cluster's hash in every piece; the VCF
# rounding hides a piece that does not, and T5d shows it. A case that imputes no
# marker (ref, imp-bigref) writes no T5d and is compared on its VCF.
#
# Usage: tests/check-piece-size.sh <beagle> <beagle-other-piece-size>
#   tests/check-piece-size.sh build/beagle build/beagle-piece1   (make check-piece-size)
# NTHREADS overrides the thread counts tried (default "2 18").
# CASES restricts the run to the named cases (default all with ref=).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=cases.sh
source "$ROOT/tests/cases.sh"
A=$1 B=$2
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

fail=0
t5d_lines=0
while read -r name _ _ args; do
  selected "$name" || continue
  [[ " $args " == *" ref="* ]] || continue
  for t in ${NTHREADS:-2 18}; do
    run_ok=1
    for side in a b; do
      bin=$A; [ "$side" = b ] && bin=$B
      dir="$OUT/$name.t$t.$side"
      mkdir -p "$dir"
      case_run "$args" "$dir/out" "$t" "$bin" "trace=$dir"
      rc=$?
      if [ $rc != 0 ]; then
        echo "FAIL $name nthreads=$t $bin exit=$rc"; tail -5 "$dir/out.log"; run_ok=0
      fi
      touch "$dir/T5d.txt"
    done
    if [ $run_ok = 0 ]; then fail=1; continue; fi
    a="$OUT/$name.t$t.a" b="$OUT/$name.t$t.b"
    hash_a=$(vcf_hash "$a/out.vcf.gz") hash_b=$(vcf_hash "$b/out.vcf.gz")
    lines=$(wc -l < "$a/T5d.txt" | tr -d ' ')
    if [ "$hash_a" != "$hash_b" ]; then
      echo "FAIL $name nthreads=$t VCF $hash_a from $A, $hash_b from $B"; fail=1
    elif ! cmp -s "$a/T5d.txt" "$b/T5d.txt"; then
      differ=$(diff "$a/T5d.txt" "$b/T5d.txt" | grep -c '^<')
      echo "FAIL $name nthreads=$t T5d differs on $differ of $lines lines from $A:"
      diff "$a/T5d.txt" "$b/T5d.txt" | head -4
      fail=1
    else
      echo "PASS $name nthreads=$t $hash_a T5d $lines lines"
    fi
    t5d_lines=$((t5d_lines + lines))
  done
done < <(cases)
[ "$t5d_lines" -gt 0 ] || { echo "FAIL no run wrote T5d"; fail=1; }
exit $fail
