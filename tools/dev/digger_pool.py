# Pool --feet --bodies runs for the diggers (and nestmates): ant-frames with 2+ planted feet in the air or the soil,
# diggers with a body part in the soil.   python tools/dev/digger_pool.py <file>
import re
import sys

t = open(sys.argv[1], encoding="utf-8").read()
acc = {}


def add(k, pct, n):
    a = acc.setdefault(k, [0.0, 0])
    a[0] += float(pct) / 100 * int(n)
    a[1] += int(n)


for m in re.finditer(r"(DIGGER|NESTMATE)-frames with 2\+ planted feet in the air ([\d.]+)%, in the soil ([\d.]+)% of (\d+)", t):
    add(m.group(1) + " feet in the air", m.group(2), m.group(4))
    add(m.group(1) + " feet in the soil", m.group(3), m.group(4))
for m in re.finditer(r"diggers in the soil ([\d.]+)% of digger-frames\s+diggers in the air [\d.]+% of (\d+)", t):
    add("DIGGER body in the soil", m.group(1), m.group(2))
for k, (x, n) in sorted(acc.items()):
    print("%-28s %6.2f%%  of %d" % (k, 100 * x / max(1, n), n))
