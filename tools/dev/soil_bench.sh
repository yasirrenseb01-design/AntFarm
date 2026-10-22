#!/usr/bin/env bash
# Bodies in the soil by what the ants do, averaged over several nests and runs (dev/body_check.gd --bodies groups):
# the keeper's targets (2026-10-22) - resting <= 5%, nurses in a narrow chamber <= 20%, walking <= 10% ("skin").
# Also body bobbing (--feet). Usage: tools/dev/soil_bench.sh [runs per nest, default 2] [godot project path]
RUNS=${1:-2}
P=${2:-.}
cd "$(dirname "$0")/../.."
OUT=$(mktemp)
for scene in "mine3|--testsave=mine3" "mine2|--testsave=mine2" "w14|--seed=3 --workers=14 --warm=20" \
		"w14b|--seed=5 --workers=14 --warm=30" "f3|--seed=3 --workers=0 --warm=55" "w40|--seed=7 --workers=40 --warm=15"; do
	name=${scene%%|*}; args=${scene#*|}
	for k in $(seq 1 $RUNS); do
		GD_TIMEOUT=900 tools/dev/gd.sh --path $P -- $args --view=nest --frames=60 --shot=shots/soil/bench.png --seq=60 --seq-every=3 \
			--seq-speed=1 --bodies --feet 2>&1 | grep -E "ant-frames: skin|bodies bobbing|SCRIPT ERROR" | sed "s/^/$name /" >> $OUT
	done
done
grep "SCRIPT ERROR" $OUT | head -3
python - "$OUT" <<'EOF'
import re, sys, collections
n = collections.Counter(); sk = collections.Counter(); dp = collections.Counter(); bob = []
for line in open(sys.argv[1], encoding='utf-8'):
	m = re.search(r'(nurse, narrow|nurse, roomy|resting|walking|climbing/other)\s+(\d+) ant-frames: skin\s+([\d.]+)%\s+deep\s+([\d.]+)%', line)
	if m:
		g, c = m.group(1), int(m.group(2))
		n[g] += c; sk[g] += c * float(m.group(3)); dp[g] += c * float(m.group(4))
	b = re.search(r'bobbing.*: ([\d.]+)%', line)
	if b:
		bob.append(float(b.group(1)))
target = {"resting": 5, "nurse, narrow": 20, "walking": 10}
for g in ["nurse, narrow", "nurse, roomy", "resting", "walking", "climbing/other"]:
	if n[g]:
		t = target.get(g)
		print("%-15s %6d ant-frames  skin %5.1f%%  deep %4.1f%%%s" % (g, n[g], sk[g] / n[g], dp[g] / n[g],
			"  (target <= %d%%: %s)" % (t, "ok" if sk[g] / n[g] <= t else "NOT YET") if t else ""))
if bob:
	print("body bobbing %.2f%% (mean of %d runs)" % (sum(bob) / len(bob), len(bob)))
EOF
rm -f $OUT
