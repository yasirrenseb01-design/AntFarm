#!/usr/bin/env bash
# Ants standing still: legs shifting and shaking, bodies to and fro, legs stretched straight (dev/still_check.gd), and
# the planted feet's jumps and feet in the air - 12 seeds of a 20-worker colony at a fixed 60 fps, pooled
# (tools/dev/still_pool.py). The view's own randomness makes one seed swing a lot: compare before/after on the same
# seeds, run together (LESSONS 26). Don't edit scripts while it runs: each seed loads them again.
# Usage: [FLAGS=--bodies] tools/dev/still_bench.sh <out file> [project path] [seeds, default "1 2 ... 12"]
# (FLAGS=--bodies: the bodies instead - LICK, antennating, QUEEN)
OUT=${1:?out file}
P=${2:-.}
SEEDS=${3:-"1 2 3 4 5 6 7 8 9 10 11 12"}
cd "$(dirname "$0")/../.."
: > $OUT
for s in $SEEDS; do
	GD_TIMEOUT=900 tools/dev/gd.sh --path $P --fixed-fps 60 -- --seed=$s --workers=20 --warm=20 --view=nest --xray --frames=60 \
		--shot=shots/still/f$(basename $OUT .txt)$s.png --seq=300 --seq-every=1 --seq-speed=1 ${FLAGS:---feet} >> $OUT 2>&1
	echo "==" >> $OUT
done
python tools/dev/still_pool.py $OUT
