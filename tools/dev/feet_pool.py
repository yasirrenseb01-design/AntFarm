"""Pool the --feet measurements of several runs (each one's lines as foot_check prints them, runs split by a line "==")
into one table: the planted feet's jumps and their causes (as a share of the jumps and of the planted feet), and the
TWIST numbers. A share of the jumps from one run is noisy when there are few jumps (each one is several percent):
pool six seeds or so.   python tools/dev/feet_pool.py <file>
Run the game at a fixed 60 fps (--fixed-fps 60): the measure itself slows the frames, and at its own ~7 fps every body
moved "far in one frame"."""
import re
import sys

txt = open(sys.argv[1], encoding="utf-8").read()
tot_j = tot_n = 0
cause = {}
tw = {}
for blk in txt.split("=="):
    m = re.search(r"jumping more than 0.12 between frames: ([\d.]+)% of (\d+)", blk)
    if not m:
        continue
    n = int(m.group(2))
    j = round(float(m.group(1)) / 100 * n)
    tot_j += j
    tot_n += n
    for c in re.finditer(r"jumping:\s+([\d.]+)% of the jumps \(([\d.]+)% of the planted feet\)\s+(.*)", blk):
        k = c.group(3).split(" (")[0] if "body moved far" in c.group(3) else c.group(3)
        cause[k] = cause.get(k, 0) + round(float(c.group(1)) / 100 * j)
    for t in re.finditer(r"TWIST (\w+): legs swept >45 deg round the hip ([\d.]+)% of (\d+), ant-frames with legs crossing ([\d.]+)% of (\d+)", blk):
        a = tw.setdefault(t.group(1), [0, 0, 0, 0])
        a[0] += float(t.group(2)) / 100 * int(t.group(3))
        a[1] += int(t.group(3))
        a[2] += float(t.group(4)) / 100 * int(t.group(5))
        a[3] += int(t.group(5))
print("planted feet jumping: %d of %d = %.2f%%" % (tot_j, tot_n, 100 * tot_j / max(1, tot_n)))
for k, v in sorted(cause.items(), key=lambda x: -x[1]):
    print("  %5.1f%% of the jumps (%.3f%% of the feet)  %s" % (100 * v / max(1, tot_j), 100 * v / max(1, tot_n), k))
for k, a in tw.items():
    print("TWIST %s: legs swept %.2f%%, ant-frames with legs crossing %.2f%%" % (k, 100 * a[0] / max(1, a[1]), 100 * a[2] / max(1, a[3])))
