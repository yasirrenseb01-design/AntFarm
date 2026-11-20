"""Summarise year_run logs (tools/dev/year_batch.sh): per run the workers at days 360/730/1090, the days from 200 to
300 workers, starved workers, the queen dying, and the mean of the keeper's steady stretch (days 730-1090).
Usage: python tools/dev/year_sum.py <dir> [<dir after>]   (two dirs: side by side, before -> after)"""
import re
import sys
from pathlib import Path

ROW = re.compile(r"workers\s+(\d+) eggs\s+(\d+)")


def read(path):
    w = []
    queen = ""
    by = {}
    done = False
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = ROW.search(line)
        if m and " y" in line:
            w.append(int(m.group(1)))
        if line.startswith("QUEEN DIED"):
            queen = line[11:].strip()
        if line.startswith("workers dead"):
            done = True
            for k, v in re.findall(r'"(\w+)":\s*(\d+)', line):
                by[k] = int(v)
    at = lambda d: w[d // 10] if d // 10 < len(w) else None
    cross = None
    i200 = next((i for i, x in enumerate(w) if x >= 200), None)
    if i200 is not None:
        i300 = next((i for i, x in enumerate(w) if i >= i200 and x >= 300), None)
        cross = (i300 - i200) * 10 if i300 is not None else f">{(len(w) - i200) * 10}"
    steady = w[73:110]
    return {"d360": at(360), "d730": at(730), "d1090": at(1090), "cross": cross, "starve": by.get("starve", 0),
            "queen": queen, "steady": round(sum(steady) / len(steady)) if steady else None, "by": by, "rows": len(w),
            "done": done}


def table(d):
    return {p.stem: read(p) for p in sorted(Path(d).glob("*.txt"))}


def fmt(r):
    if r is None:
        return "-"
    q = f" QUEEN DIED {r['queen']}" if r["queen"] else ""
    # (a log with no closing "workers dead" line: the run was cut off - its starved count is not known, not 0;
    # PART 0.14 step 5: a set killed half way read as "starve 0" against a finished one)
    u = "" if r["done"] else f" UNFINISHED after {r['rows'] * 10} d"
    return f"{r['d360']}/{r['d730']}/{r['d1090']} 200->300 {r['cross']} steady {r['steady']} starve {r['starve']}{q}{u}"


def totals(t, prefix):
    rs = [r for k, r in t.items() if k.startswith(prefix)]
    if not rs:
        return ""
    mean = lambda key: sum((r[key] or 0) for r in rs) / len(rs)
    return (f"{prefix}*: n {len(rs)}  d360 {mean('d360'):.1f}  d730 {mean('d730'):.1f}  d1090 {mean('d1090'):.1f}  "
            f"starve {sum(r['starve'] for r in rs)} (runs {sum(1 for r in rs if r['starve'] > 0)})  "
            f"queen died {sum(1 for r in rs if r['queen'])}  died out {sum(1 for r in rs if r['d1090'] == 0)}"
            + (f"  UNFINISHED {sum(1 for r in rs if not r['done'])}" if any(not r["done"] for r in rs) else ""))


a = table(sys.argv[1])
b = table(sys.argv[2]) if len(sys.argv) > 2 else None
for k in sorted(set(a) | set(b or {})):
    print(f"{k:8s} {fmt(a.get(k))}" + (f"   ->   {fmt(b.get(k))}" if b is not None else ""))
for t, name in [(a, sys.argv[1])] + ([(b, sys.argv[2])] if b is not None else []):
    print(f"== {name}")
    for p in ["k22", "k5", "k11", "k33", "big", "w"]:
        s = totals(t, p)
        if s:
            print("  " + s)
