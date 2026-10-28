"""Pool the --feet STILL / STRETCH lines (dev/still_check.gd) of several runs (split by "==") into one table, with the
planted feet's jumps and the nestmate-frames with feet in the air.   python tools/dev/still_pool.py <file>"""
import re
import sys

txt = open(sys.argv[1], encoding="utf-8", errors="replace").read()
acc = {}


def add(k, pct, n):
    a = acc.setdefault(k, [0.0, 0])
    a[0] += float(pct) / 100 * int(n)
    a[1] += int(n)


why = {}
runs = 0
for blk in txt.split("=="):
    if "STILL" not in blk and "STRETCH" not in blk:
        continue
    runs += 1
    for m in re.finditer(r"STILL (.+?): ant-frames with a leg shifting > [\d.]+ ([\d.]+)% of (\d+), feet lifted ([\d.]+) a second per ant, "
                         r"shaking \(a foot to and fro within a second\) ([\d.]+)% of (\d+) ant-seconds\s+its body moved or turned in a frame "
                         r"([\d.]+)%, the body to and fro within a second \(>= [\d.]+\) ([\d.]+)%", blk):
        w = m.group(1)
        add(w + ": frames with a leg shifting", m.group(2), m.group(3))
        add(w + ": feet lifted a second (x100)", float(m.group(4)) * 100, m.group(3))
        add(w + ": ant-seconds with a foot shaking", m.group(5), m.group(6))
        add(w + ": frames the body moved/turned", m.group(7), m.group(3))
        add(w + ": ant-seconds the body to and fro", m.group(8), m.group(6))
        tail = blk[m.end():].split("STRETCH")[0].split("STILL")[0]
        nshift = float(m.group(2)) / 100 * int(m.group(3))
        for c in re.finditer(r"shifting:\s+([\d.]+)%\s+(.*)", tail):
            why[(w, c.group(2).strip())] = why.get((w, c.group(2).strip()), 0) + float(c.group(1)) / 100 * nshift
    for m in re.finditer(r"STRETCH (.+?): planted legs straight \(>= [\d.]+\) ([\d.]+)%, nearly \(0.93-[\d.]+\) ([\d.]+)% of (\d+)", blk):
        add(m.group(1) + ": planted legs straight", m.group(2), m.group(4))
        add(m.group(1) + ": planted legs nearly straight", m.group(3), m.group(4))
    m = re.search(r"jumping more than 0.12 between frames: ([\d.]+)% of (\d+)", blk)
    if m:
        add("all: planted feet jumping > 0.12", m.group(1), m.group(2))
    m = re.search(r"NESTMATE-frames with 2\+ planted feet in the air ([\d.]+)%, in the soil ([\d.]+)% of (\d+)", blk)
    if m:
        add("all: nestmate-frames 2+ feet in the air", m.group(1), m.group(3))
        add("all: nestmate-frames 2+ feet in the soil", m.group(2), m.group(3))
print("%d runs" % runs)
for k, (x, n) in sorted(acc.items()):
    if "x100" in k:
        print("%-52s %6.2f  (%d frames)" % (k.replace(" (x100)", ""), x / max(1, n), n))
    else:
        print("%-52s %6.2f%%  of %d" % (k, 100 * x / max(1, n), n))
for (w, c), v in sorted(why.items(), key=lambda x: -x[1]):
    print("  %-12s shifting %5.0f  %s" % (w, v, c))
# --bodies runs (FLAGS=--bodies): mouths with nothing at them (antennating by why), nestmates in the queen
lk = {}
for m in re.finditer(r"LICK (.+?): nothing at its mouth ([\d.]+)% of (\d+)", txt):
    a = lk.setdefault(m.group(1), [0.0, 0])
    a[0] += float(m.group(2)) / 100 * int(m.group(3))
    a[1] += int(m.group(3))
for m in re.finditer(r"QUEEN: nestmates in her body ([\d.]+)% \(deep ([\d.]+)%\) of (\d+)", txt):
    for k, g in (("QUEEN in her", 1), ("QUEEN deep in her", 2)):
        a = lk.setdefault(k, [0.0, 0])
        a[0] += float(m.group(g)) / 100 * int(m.group(3))
        a[1] += int(m.group(3))
for k, (x, n) in sorted(lk.items()):
    print("%-52s %6.2f%%  of %d" % (k, 100 * x / max(1, n), n))
ant = [v for k, v in lk.items() if k.startswith("antennating")]
if ant:
    x = sum(a[0] for a in ant)
    n = sum(a[1] for a in ant)
    print("%-52s %6.2f%%  of %d" % ("antennating (all): mouth more than a body away", 100 * x / max(1, n), n))
