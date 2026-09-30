#!/bin/bash
# Checks group planning against the declared check groups and CI's platform
# split. Planning must be read-only, including when asked about another OS.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
fail=0

expect_groups() {  # tier platform expected groups...
  local tier=$1 platform=$2 got want; shift 2
  want=$(printf '%s\n' "$@")
  got=$(GATE_LIST_GROUPS=1 GATE_TIER="$tier" GATE_PLATFORM="$platform" \
    "$ROOT/tests/gate-steps.sh" "$ROOT")
  if [ "$got" = "$want" ]; then
    echo "PASS $tier/$platform groups"
  else
    echo "FAIL $tier/$platform groups: got '$got', want '$want'"; fail=1
  fi
}

expect_groups full linux core cases java bgen sanitizers
expect_groups full darwin core java bgen sanitizers tsan
expect_groups c linux core bgen sanitizers
expect_groups c darwin core bgen sanitizers tsan

tmp=$(mktemp -d)
mkdir "$tmp/tests"
ln -s "$ROOT/tests/gate-steps.sh" "$tmp/tests/gate-steps.sh"
if GATE_LIST_GROUPS=1 GATE_TIER=full GATE_PLATFORM=darwin \
    "$tmp/tests/gate-steps.sh" "$tmp" > "$tmp/groups" && [ ! -e "$tmp/build" ]; then
  echo "PASS group listing is read-only"
else
  echo "FAIL group listing created files or failed"; fail=1
fi
if GATE_LIST_GROUPS=1 GATE_TIER=full GATE_PLATFORM=unsupported \
    "$ROOT/tests/gate-steps.sh" "$ROOT" > /dev/null 2>&1; then
  echo "FAIL invalid planning platform passed"; fail=1
else
  echo "PASS invalid planning platform rejected"
fi

if GATE_TIER=full GATE_GROUP=not-a-group GATE_LIST=1 \
    "$ROOT/tests/gate-steps.sh" "$ROOT" > /dev/null 2>&1; then
  echo "FAIL undeclared group selector passed"; fail=1
else
  echo "PASS undeclared group selector rejected"
fi

got=$(GATE_TIER=c GATE_GROUP=java GATE_LIST=1 "$ROOT/tests/gate-steps.sh" "$ROOT")
want=$'setup fixtures\nsetup c-build'
if [ "$got" = "$want" ]; then
  echo "PASS full-only group is a C-tier no-op"
else
  echo "FAIL full-only C-tier group selected checks: got '$got', want '$want'"; fail=1
fi

got=$(GATE_TIER=full GATE_GROUP=bgen GATE_LIST=1 "$ROOT/tests/gate-steps.sh" "$ROOT")
want=$'setup fixtures\nsetup c-build\nbgen bgen'
if [ "$got" = "$want" ]; then
  echo "PASS setup and selected checks retain declaration order"
else
  echo "FAIL selected check list: got '$got', want '$want'"; fail=1
fi

got=$(GATE_TIER=full GATE_GROUP=core GATE_LIST=1 "$ROOT/tests/gate-steps.sh" "$ROOT" \
  | awk '$2 == "oracle-c" || $2 == "gate-planning" || $2 == "failures-c"')
want=$'core oracle-c\ncore gate-planning\ncore failures-c'
if [ "$got" = "$want" ]; then
  echo "PASS local core check order and planner membership"
else
  echo "FAIL local core membership/order: got '$got', want '$want'"; fail=1
fi

# CI combines Linux then macOS plans so Linux-only cases and macOS-only tsan
# each occur once, in declaration order.
for tier in full c; do
  got=$( { GATE_LIST_GROUPS=1 GATE_TIER="$tier" GATE_PLATFORM=linux "$ROOT/tests/gate-steps.sh" "$ROOT"
           GATE_LIST_GROUPS=1 GATE_TIER="$tier" GATE_PLATFORM=darwin "$ROOT/tests/gate-steps.sh" "$ROOT"; } \
         | awk '!seen[$0]++')
  if [ "$tier" = full ]; then
    want=$'core\ncases\njava\nbgen\nsanitizers\ntsan'
  else
    want=$'core\nbgen\nsanitizers\ntsan'
  fi
  if [ "$got" = "$want" ]; then
    echo "PASS CI $tier matrix covers platform-specific groups in declaration order"
  else
    echo "FAIL CI $tier matrix: got '$got', want '$want'"; fail=1
  fi
done

rm -rf "$tmp"
exit "$fail"
