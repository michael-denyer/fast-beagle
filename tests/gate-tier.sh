#!/bin/bash
# Prints the gate tier a change needs, given its changed paths one per line on
# standard input: c when the C tier checks every path, full otherwise. Only
# files under src/ (except src/jcompat/), third_party/ and docs/, and Markdown
# files, qualify. Every other path, including every test script and table, runs
# the full tier, so a new full-tier check needs no entry here.
#
# Usage: git diff --name-only origin/main | tests/gate-tier.sh
set -uo pipefail
tier=c n=0
while IFS= read -r path; do
  n=$((n + 1))
  case $path in
    src/jcompat/*) tier=full ;;
    src/* | third_party/* | docs/* | *.md) ;;
    *) tier=full ;;
  esac
done
[ "$n" -gt 0 ] || { echo "gate-tier.sh: no changed paths on standard input" >&2; exit 1; }
echo "$tier"
