#!/usr/bin/env bash
# Planted feet through the soil surface, averaged over several nests and runs (dev/foot_check.gd --feet): the keeper's
# target (2026-10-24) - tips in the soil at most 1% - and what a change to the feet must not make worse: feet in the air,
# planted feet jumping (> 0.12 a frame) and flickering (up then down) - the legs "wriggling" before they settle.
# Usage: tools/dev/feet_bench.sh [runs per nest, default 2] [godot project path]
RUNS=${1:-2}
P=${2:-.}
cd "$(dirname "$0")/../.."
OUT=$(mktemp)
for scene in "mine3|--testsave=mine3" "mine2|--testsave=mine2" "w14|--seed=3 --workers=14 --warm=20" \
		"w40|--seed=7 --workers=40 --warm=15" "deep|--testsave=big_11 --slot=1" "garden|--scenario=wild --seed=5 --workers=150 --warm=25"; do
	name=${scene%%|*}; args=${scene#*|}
	for k in $(seq 1 $RUNS); do
		GD_TIMEOUT=900 tools/dev/gd.sh --path $P -- $args --view=nest --xray --frames=60 --shot=shots/soil/feet.png --seq=120 --seq-every=1 \
			--seq-speed=1 --feet 2>&1 | grep -E "^planted feet [0-9]|through the soil's surface|feet moving up or down more|jumping more than|SCRIPT ERROR" | sed "s/^/$name /" >> $OUT
	done
done
grep "SCRIPT ERROR" $OUT | head -3
python - "$OUT" <<'EOF'
import re, sys, collections
n = collections.Counter(); air = collections.Counter(); soil = collections.Counter(); jit = []; flick = []; pen = collections.Counter()
last = None
for line in open(sys.argv[1], encoding='utf-8'):
	m = re.search(r'^(\S+) planted feet (\d+): in the air ([\d.]+)%.*in the soil ([\d.]+)%', line)
	if m:
		k, c = m.group(1), int(m.group(2))
		n[k] += c; air[k] += c * float(m.group(3)); soil[k] += c * float(m.group(4)); last = (k, c)
	q = re.search(r'^(\S+) .*through the soil.s surface .*: ([\d.]+)%', line)
	if q and last:
		pen[last[0]] += last[1] * float(q.group(2))
	j = re.search(r'^(\S+) .*jumping more than 0.12 between frames: ([\d.]+)%', line)
	if j:
		jit.append(float(j.group(2)))
	f = re.search(r'^(\S+) .*flickering \(up then down\) ([\d.]+)%', line)
	if f:
		flick.append(float(f.group(2)))
tn = sum(n.values())
for k in [k for k in n if n[k]]:
	print("%-7s %7d feet  through the surface %5.2f%%  (in along its up %5.2f%%)  in the air %5.2f%%" % (k, n[k], pen[k] / n[k], soil[k] / n[k], air[k] / n[k]))
if tn:
	ts = sum(soil.values()) / tn
	tp = sum(pen.values()) / tn
	print("all     %7d feet  through the surface %5.2f%% (target <= 1%%: %s)  (in along its up %5.2f%%)  in the air %5.2f%%" % (tn, tp, "ok" if tp <= 1 else "NOT YET", ts, sum(air.values()) / tn))
if jit:
	print("planted feet jumping > 0.12 a frame %.2f%%, flickering %.2f%% (means of %d runs)" % (sum(jit) / len(jit), sum(flick) / max(1, len(flick)), len(jit)))
EOF
rm -f $OUT
