#!/bin/bash
# Model-checks tla/ParallelOrdered.tla, the protocol of parallel_ordered in
# src/blbutil/parallel.c, with TLC for several worker counts, item counts and
# windows: the invariants, no deadlock, and that every run terminates with
# every item consumed. Needs Java; downloads tla2tools.jar TLA_VERSION into
# data/, checked against TLA_SHA256.
#
# Usage: tests/check-tla.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TLA_VERSION=v1.7.4
TLA_SHA256=936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88
JAR="$ROOT/data/tla2tools-$TLA_VERSION.jar"
SHA=$(command -v sha256sum || echo "shasum -a 256")

mkdir -p "$ROOT/data"
if [ ! -f "$JAR" ]; then
  curl -LSf -o "$JAR.part" "https://github.com/tlaplus/tlaplus/releases/download/$TLA_VERSION/tla2tools.jar" \
    || { echo "FAIL download tla2tools.jar $TLA_VERSION"; exit 1; }
  mv "$JAR.part" "$JAR"
fi
got=$($SHA "$JAR" | cut -d' ' -f1)
[ "$got" = "$TLA_SHA256" ] || { echo "FAIL $JAR has sha256 $got, want $TLA_SHA256"; exit 1; }

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
fail=0
# workers items window
for model in "1 3 1" "2 4 1" "2 5 2" "3 5 2" "3 6 3" "2 3 5" "3 8 3" "4 7 2"; do
  read -r nw ni win <<< "$model"
  workers=$(seq -f "w%g" 1 "$nw" | paste -sd, -)
  cat > "$OUT/MC.cfg" <<EOF
CONSTANTS
  Workers = {$workers}
  NItems = $ni
  Window = $win
SPECIFICATION Spec
INVARIANTS TypeOK WindowBound NoOverwrite ConsumesOwnItem InOrder
PROPERTIES Terminates AllConsumed
EOF
  cp "$ROOT/tla/ParallelOrdered.tla" "$OUT/"
  if java -XX:+UseParallelGC -cp "$JAR" tlc2.TLC -workers 4 -metadir "$OUT/states-$nw-$ni-$win" \
      -config "$OUT/MC.cfg" "$OUT/ParallelOrdered.tla" > "$OUT/tlc.log" 2>&1 \
      && grep -q "No error has been found" "$OUT/tlc.log"; then
    echo "PASS workers=$nw items=$ni window=$win $(grep -o '[0-9,]* distinct states found' "$OUT/tlc.log" | head -1)"
  else
    echo "FAIL workers=$nw items=$ni window=$win: $(grep -m1 "^Error:" "$OUT/tlc.log")"; grep -v "^\s*$" "$OUT/tlc.log" | tail -40; fail=1
  fi
done
exit $fail
