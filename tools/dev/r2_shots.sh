#!/usr/bin/env bash
# R2: every screen in a language at a window size, as screenshots (shots/r2/<lang>_<w>x<h>/<name>.png) to look over
# for words that run over or are cut off.
#   tools/dev/r2_shots.sh en 1366x768 [name ...]
cd "$(dirname "$0")/../.."
LANG_=${1:-en}
RES=${2:-1920x1080}
shift 2
OUT=shots/r2/${LANG_}_${RES}
mkdir -p "$OUT"
G=/e/Godot_v4.7.2-stable_win64_console.exe
BASE="--no-title --lang=$LANG_ --scenario=wild --workers=14 --warm=30 --seed=3 --tod=0.5 --frames=40"
declare -A S=(
  [outworld]="$BASE --view=outworld"
  [outworld_keeper]="--no-title --lang=$LANG_ --scenario=keeper --workers=14 --warm=30 --seed=3 --tod=0.5 --frames=40 --view=outworld"
  [keeper_side]="--no-title --lang=$LANG_ --scenario=keeper --workers=14 --warm=30 --seed=3 --tod=0.5 --frames=40 --view=outworld --side-open"
  [nest_side]="$BASE --view=nest --side-open"
  [named_queen]="$BASE --name-first=queen --stars"
  [nest]="$BASE --view=nest"
  [nest_select]="$BASE --view=nest --select"
  [settings]="$BASE --settings"
  [colonies]="$BASE --colonies"
  [newcolony]="$BASE --newcolony"
  [species]="$BASE --species"
  [enemies]="$BASE --enemy-panel"
  [stars]="$BASE --stars"
  [guide0]="$BASE --guide=0"
  [guide1]="--no-title --lang=$LANG_ --scenario=keeper --workers=14 --warm=30 --seed=3 --tod=0.5 --frames=40 --guide=1"
  [guide4]="$BASE --guide=4"
  [guide5]="$BASE --guide=5"
  [title]="--sandbox --windowed --lang=$LANG_ --title --frames=40"
  [home]="--sandbox --windowed --lang=$LANG_ --home --home-hour=12 --frames=40 --home-point=960,700"
  [shop]="--sandbox --windowed --lang=$LANG_ --home --home-hour=12 --frames=40 --shop"
  [wild]="--sandbox --windowed --lang=$LANG_ --colonies=wild --frames=30"
  [away]="--sandbox --windowed --lang=$LANG_ --pretend-away=30 --no-title --frames=30"
)
NAMES=("$@")
[ ${#NAMES[@]} -eq 0 ] && NAMES=(outworld outworld_keeper keeper_side nest_side named_queen nest nest_select settings colonies newcolony species enemies stars guide0 guide1 guide4 guide5 title home shop wild away)
for n in "${NAMES[@]}"; do
  r=$(timeout 300 $G --resolution "$RES" --path . -- ${S[$n]} --shot="$OUT/$n.png" 2>&1 | grep -E "SCRIPT ERROR|saved" | head -2)
  echo "$n: $r"
done
