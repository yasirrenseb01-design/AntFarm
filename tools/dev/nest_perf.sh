#!/usr/bin/env bash
# PART 0.12 step 3: the nest view of a grown colony (growtest copy, read only) - frame time and its parts, and with
# --fixed-fps the view hash (the same before and after a change that should not alter what is drawn).
# Usage: tools/dev/nest_perf.sh <testsave> <slot> <cap> [xray]
cd "$(dirname "$0")/../.."
x="--no-xray"; [ "$4" == "xray" ] && x=""
out=$(GD_TIMEOUT=400 tools/dev/gd.sh --path . -- --sandbox --tod=0.5 --live --frames=400 --perf --shot=shots/bench.png --testsave=$1 --slot=$2 --view=nest $x --draw-cap=$3 2>&1)
echo "$out" | grep "^perf: avg\|PARSE\|SCRIPT ERROR"
echo "$out" | grep "^perf parts" | sed 's/.*| nest view: //' | tr ',' '\n' | sed 's/^ //' | sort -t' ' -k1 | tr '\n' ',' ; echo
h=$(GD_TIMEOUT=400 tools/dev/gd.sh --path . --fixed-fps 60 -- --sandbox --tod=0.5 --live --frames=200 --view-hash=7 --shot=shots/bench.png --testsave=$1 --slot=$2 --view=nest $x --draw-cap=$3 2>&1 | grep "view hash")
echo "$h"
