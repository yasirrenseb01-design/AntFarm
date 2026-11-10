#!/usr/bin/env bash
# Dense multi-angle frames of ants pushing apart, climbing, bending round turns and fitting the ground, on a copy of the
# keeper's colony (--testsave=usercopy --slot=3), the views' random draws seeded (--view-hash) and godot's fixed 60 fps:
# the same code gives the same pictures to the pixel, so the files of two runs can be compared with md5sum (v0.12.25).
# Usage: tools/dev/native_shots.sh <out dir> [extra option...]
out="$1"; shift
mkdir -p "$out"
cd "$(dirname "$0")/../.."
base="--sandbox --tod=0.5 --live --view-hash=7 --testsave=usercopy --slot=3 --view=nest --seq=12 --seq-every=3 --seq-speed=0.5"
i=0
for f in "--follow-pushed" "--follow-soil" "--follow-fit=over" "--follow-fit=turn --side" "--follow-fit=over --xray"; do
  i=$((i+1))
  rm -rf "shots/seq/ns$i"
  GD_TIMEOUT=600 tools/dev/gd.sh --path . --fixed-fps 60 -- $base $f --shot="shots/seq/ns$i/f.png" "$@" > "$out/run$i.log" 2>&1
  mkdir -p "$out/ns$i"; cp shots/seq/ns$i/*.png "$out/ns$i/" 2>/dev/null
done
( cd "$out" && md5sum ns*/*.png > md5.txt; wc -l md5.txt )
