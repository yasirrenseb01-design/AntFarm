#!/usr/bin/env bash
# The queen walking between chambers of a real colony, on a copy (the real saves are only read; --testsave never writes).
# Usage: tools/dev/queen_bench.sh <slot> "<chambers to walk to>" <rounds> [game options]
#   e.g. tools/dev/queen_bench.sh 3 "2 6 10" 2
S=${1:-3}; TO=${2:-"2 6 10"}; N=${3:-2}; shift 3
cd "$(dirname "$0")/../.."
A="$APPDATA/Godot/app_userdata/AntFarm"
D="queencopy$S"
OUT=$(mktemp -d)
mkdir -p "$A/growtest/$D/saves"
cp "$A/saves/slot$S.antfarm" "$A/saves/slot$S.json" "$A/growtest/$D/saves/"
for q in $TO; do
  for r in $(seq 1 "$N"); do
    echo "--- to chamber $q, round $r"
    GD_TIMEOUT=280 tools/dev/gd.sh --fixed-fps 60 --path . -- --testsave="$D" --slot="$S" --shot="$OUT/q.png" --view=nest \
      --seq=1 --seq-every=3600 --seq-speed=3 --queen-to="$q" --queen-walk --follow-queen --look=queen --dist=20 --xray "$@" 2>&1 \
      | grep -E -A2 "^queen walk|^  QW|^  queen |^    her way|normalized|SCRIPT ERROR" ; true
  done
done
rm -rf "$A/growtest/$D" "$OUT"
