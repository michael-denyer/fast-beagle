#!/bin/bash
# Model-checks the TLA+ specs in tla/ with TLC over a matrix of constants:
#   ParallelOrdered  parallel_ordered in src/blbutil/parallel.c
#   BlockReader      the three-stage pipeline in src/vcf/block_reader.c
#   SlidingWindow    the read-ahead hand-over in src/vcf/sliding_window.c
# Each run checks the spec's invariants, no deadlock, and its liveness
# properties. Needs Java; downloads tla2tools.jar TLA_VERSION into data/,
# checked against TLA_SHA256.
#
# Usage: tests/check-tla.sh [Spec ...]   (default: every spec above)
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
run=0

# check <Spec> <label> <<< "<constant assignments>": one TLC run of
# tla/<Spec>.tla with the spec's INVARIANTS and PROPERTIES lines.
check() {
  local spec=$1 label=$2
  run=$((run + 1))
  { echo "CONSTANTS"; cat; echo "SPECIFICATION Spec"; echo "$CHECKS"; } > "$OUT/MC.cfg"
  cp "$ROOT/tla/$spec.tla" "$OUT/"
  if java -XX:+UseParallelGC -cp "$JAR" tlc2.TLC -workers 4 -metadir "$OUT/states-$run" \
      -config "$OUT/MC.cfg" "$OUT/$spec.tla" > "$OUT/tlc.log" 2>&1 \
      && grep -q "No error has been found" "$OUT/tlc.log"; then
    echo "PASS $spec $label $(grep -o '[0-9,]* distinct states found' "$OUT/tlc.log" | head -1)"
  else
    echo "FAIL $spec $label: $(grep -m1 "^Error:" "$OUT/tlc.log")"; grep -v "^\s*$" "$OUT/tlc.log" | tail -60; fail=1
  fi
}

parallel_ordered() {
  CHECKS="INVARIANTS TypeOK WindowBound NoOverwrite ConsumesOwnItem InOrder
PROPERTIES Terminates AllConsumed"
  # workers items window
  for model in "1 3 1" "2 4 1" "2 5 2" "3 5 2" "3 6 3" "2 3 5" "3 8 3" "4 7 2"; do
    read -r nw ni win <<< "$model"
    workers=$(seq -f "w%g" 1 "$nw" | paste -sd, -)
    check ParallelOrdered "workers=$nw items=$ni window=$win" <<EOF
  Workers = {$workers}
  NItems = $ni
  Window = $win
EOF
  done
}

block_reader() {
  # The code has BLOCK_READER_SLOTS = 4; Slots = 1 is the boundary where a
  # missing broadcast stalls the pipeline.
  for slots in 1 2 3 4; do
    for nb in 0 1 3 5; do
      CHECKS="INVARIANTS TypeOK SlotsPartition ReaderSlotExclusive InOrder
PROPERTIES CloseTerminates WaitEnds Progress"
      check BlockReader "slots=$slots batches=$nb close=any" <<EOF
  Slots = $slots
  NBatches = $nb
  MayClose = TRUE
EOF
      CHECKS="INVARIANTS TypeOK SlotsPartition ReaderSlotExclusive InOrder
PROPERTIES WaitEnds SeesSentinel"
      check BlockReader "slots=$slots batches=$nb close=never" <<EOF
  Slots = $slots
  NBatches = $nb
  MayClose = FALSE
EOF
    done
  done
}

sliding_window() {
  CHECKS="INVARIANTS TypeOK InOrder AheadNotGiven NoLeak ErrorAfterPrefix ErrorNoAhead
PROPERTIES CloseTerminates NextReturns ExitOnlyOnError"
  # windows failat
  for model in "1 {}" "1 {1}" "2 {}" "2 {1,2}" "3 {}" "3 {1,2,3}" "4 {}" "4 {1,2,3,4}" "4 {3}"; do
    read -r nw failat <<< "$model"
    check SlidingWindow "windows=$nw failat=$failat" <<EOF
  NWindows = $nw
  FailAt = $failat
EOF
  done
}

fatal_exit() {
  CHECKS="INVARIANTS TypeOK LocksConsistent NoPartialAfterExit NoCreateAfterCleanup CompletedSurvive ErrorNotLost
PROPERTIES Terminates NoLockDeadlock DeferredRaised"
  # ChromLeaksLock = TRUE, the chrom_ids.c before str_set_try_index, fails
  # NoLockDeadlock and DeferredRaised. Two workers pass the invariants but
  # the liveness pass runs past ten minutes, so the gate checks one.
  check FatalExit "workers=1 chrom-unlocks" <<EOF
  Workers = {w1}
  ChromLeaksLock = FALSE
EOF
}

specs=("$@")
[ ${#specs[@]} -gt 0 ] || specs=(ParallelOrdered BlockReader SlidingWindow FatalExit)
for spec in "${specs[@]}"; do
  case $spec in
    ParallelOrdered) parallel_ordered ;;
    BlockReader) block_reader ;;
    SlidingWindow) sliding_window ;;
    FatalExit) fatal_exit ;;
    *) echo "FAIL unknown spec $spec"; fail=1 ;;
  esac
done
exit $fail
