#!/usr/bin/env bash
# The nest view of a real colony, measured on a copy (the real saves are only read; --testsave never writes to the copy).
# Usage: tools/dev/first_nest_bench.sh <slot in the real saves> <rounds> <seconds in the nest> [game options, e.g. --no-warm --nest-kill-every=5]
# Prints the colony opened (check it is the one meant!), then every frame over 80 ms after the nest opened.
S=${1:-3}; N=${2:-3}; SECS=${3:-15}; shift 3
cd "$(dirname "$0")/../.."
A="$APPDATA/Godot/app_userdata/AntFarm"
D="benchcopy$S"
mkdir -p "$A/growtest/$D/saves"
cp "$A/saves/slot$S.antfarm" "$A/saves/slot$S.json" "$A/growtest/$D/saves/"
for r in $(seq 1 "$N"); do
  echo "--- round $r"
  GD_TIMEOUT=$((SECS + 90)) tools/dev/gd.sh --path . -- --testsave="$D" --slot="$S" --hitch-log --nest-after=8 --quit-after=$((SECS + 8)) "$@" 2>&1 \
    | awk '/nest made ready/ {print} /^view nest/ {p=1} p' | grep -E "^hitch|^killed|^io:|nest made ready|SCRIPT ERROR|Max recursion|SHADER ERROR" | cut -c1-330
done
rm -rf "$A/growtest/$D"
