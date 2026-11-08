#!/usr/bin/env bash
# Needs the grown colonies of tests/year_run.gd (keeper 0 2555 kept <seed> g012b_s<seed>). Usage: tools/dev/big_view_bench.sh > out.txt
# PART 0.12: the views of grown colonies (growtest copies, read only) at several draw caps.

cd "$(dirname "$0")/../.."
run() {  # label, args...
  local lab="$1"; shift
  local out
  out=$(GD_TIMEOUT=400 tools/dev/gd.sh --path . -- --sandbox --tod=0.5 --live --frames=400 --perf --shot=shots/bench.png "$@" 2>&1)
  local held=$(echo "$out" | grep -o "held [0-9]*" | tail -1)
  local w=$(echo "$out" | grep -o "workers [0-9]*" | head -1)
  echo "== $lab | $held | $(echo "$out" | grep '^perf: avg')"
  echo "$out" | grep "^perf parts\|^memory" | cut -c1-900
}
for sv in "g012b_s2 2" "g012b_s4 3" "g012b_s3 4" "g012b_s1 2"; do
  set -- $sv
  run "$1/$2 outworld" --testsave=$1 --slot=$2 --view=outworld
  for cap in 250 600 1000; do
    run "$1/$2 nest cap$cap" --testsave=$1 --slot=$2 --view=nest --no-xray --draw-cap=$cap
    run "$1/$2 xray cap$cap" --testsave=$1 --slot=$2 --view=nest --draw-cap=$cap
  done
done
echo ALLDONE
