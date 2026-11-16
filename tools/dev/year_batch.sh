#!/usr/bin/env bash
# Runs the standard year_run set (PLAN_CROP "ขั้นงาน": keeper seed 22 x skip 0-5 + seeds 5/11/33, wild seeds 5/11/22 x
# skip 0-4, the big tank seed 5) in parallel on one checkout, one log per run, then summarises them (year_sum.py).
# Usage: tools/dev/year_batch.sh <project dir> <out dir> [jobs=8] [days=1100] [set=all|keeper|wild]
#   e.g. tools/dev/year_batch.sh ../AntFarm-base shots/yr/base 8      (a worktree of the code before the change)
# Compare two sets: python tools/dev/year_sum.py <out dir A> <out dir B>
G=/e/Godot_v4.7.2-stable_win64_console.exe
P=$(cd "$1" && pwd); OUT=$2; J=${3:-8}; D=${4:-1100}; SET=${5:-all}
mkdir -p "$OUT"
runs=()
if [ "$SET" != "wild" ]; then
  for k in 0 1 2 3 4 5; do runs+=("keeper 0 $D kept 22 skip=$k|k22s$k"); done
  for s in 5 11 33; do runs+=("keeper 0 $D kept $s|k${s}"); done
  runs+=("keeper 0 $D kept 5 - big|big5")
fi
if [ "$SET" != "keeper" ]; then
  for s in 5 11 22; do for k in 0 1 2 3 4; do runs+=("wild 0 $D alone $s skip=$k|w${s}s$k"); done; done
fi
[ -d "$P/.godot" ] || timeout 600 $G --headless --path "$P" --import >/dev/null 2>&1
printf '%s\n' "${runs[@]}" | xargs -P "$J" -I{} bash -c '
  line="{}"; args=${line%|*}; name=${line#*|}
  # (the big tank needs a save-name slot before "big": "-" is none)
  set -- $args
  if [ "$6" = "-" ]; then a="$1 $2 $3 $4 $5"; extra="x big"; else a="$args"; extra=""; fi
  timeout 7200 '"$G"' --headless --path '"$P"' --script res://tests/year_run.gd -- $a $extra > '"$OUT"'/$name.txt 2>&1
'
python "$(dirname "$0")/year_sum.py" "$OUT"
