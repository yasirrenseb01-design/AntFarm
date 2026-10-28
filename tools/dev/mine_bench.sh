#!/usr/bin/env bash
# The bodies (--bodies) in a copy of the keeper's colony (growtest/<name>), several runs: the view's own randomness
# makes one run swing a lot (resting ants' skin in the soil 0.1% in three runs, 12% in the fourth).
# Usage: tools/dev/mine_bench.sh <out file> [project path] [testsave, default mine6] [slot, default 4] [runs, default 8]
OUT=${1:?out file}
P=${2:-.}
NAME=${3:-mine6}
SLOT=${4:-4}
RUNS=${5:-8}
cd "$(dirname "$0")/../.."
: > $OUT
for r in $(seq 1 $RUNS); do
	GD_TIMEOUT=1500 tools/dev/gd.sh --path $P --fixed-fps 60 -- --testsave=$NAME --slot=$SLOT --view=nest --xray --frames=60 \
		--shot=shots/still/m$(basename $OUT .txt)$r.png --seq=900 --seq-every=1 --seq-speed=1 --bodies >> $OUT 2>&1
	echo "==" >> $OUT
	rm -f shots/still/m$(basename $OUT .txt)${r}_*.png
done
python - "$OUT" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
acc = {}
for blk in t.split("=="):
    for m in re.finditer(r"^\s+(nurse, narrow|nurse, roomy|resting|walking|climbing/other)\s+(\d+) ant-frames: skin\s+([\d.]+)%\s+deep\s+([\d.]+)%", blk, re.M):
        a = acc.setdefault(m.group(1), [0, 0.0, 0.0, []])
        n = int(m.group(2))
        a[0] += n; a[1] += n * float(m.group(3)) / 100; a[2] += n * float(m.group(4)) / 100; a[3].append(m.group(3))
for k, a in acc.items():
    print("%-15s %7d ant-frames: skin %5.2f%%  deep %5.2f%%   (skin by run: %s)" % (k, a[0], 100 * a[1] / max(1, a[0]), 100 * a[2] / max(1, a[0]), " ".join(a[3])))
PY
