"""Split one GDScript file into a chain of files without changing any code:
    base.gd  <- layer1.gd  <- ...  <- original.gd   (each `extends` the previous by path)
All member declarations (var/const/signal/enum) stay in the base so every layer sees them; each
function goes to the layer named in the plan. A function may only call functions of its own layer
or an earlier one, so order the layers by dependency (the final file is the top of the chain).

Usage: python tools/dev/split_gd.py plan.json
plan = {"file": "scripts/sim/simulation.gd",
        "layers": [{"path": "scripts/sim/parts/sim_base.gd", "doc": "...", "funcs": ["setup", ...]}, ...],
        "top_doc": "..."}            # functions not listed in any layer stay in the original file
"""
import io
import json
import re
import sys

plan = json.load(open(sys.argv[1], encoding="utf-8"))
src = io.open(plan["file"], encoding="utf-8").read().split("\n")

# ---- cut the file into top-level units (a declaration plus the comment lines directly above it)
units = []          # {"kind", "name", "lines"}
header = []
pending = []        # comments / blank lines waiting for the unit they introduce
i = 0
seen_unit = False
while i < len(src):
    line = src[i]
    top = line and not line[0].isspace()
    if not top or line.startswith("#"):
        if not seen_unit and not line.startswith("extends") and not line.startswith("class_name"):
            header.append(line) if not pending else pending.append(line)
        else:
            pending.append(line)
        i += 1
        continue
    if line.startswith(("extends", "class_name", "@tool")):
        header.append(line)
        i += 1
        continue
    seen_unit = True
    m = re.match(r"(static\s+)?func\s+(\w+)", line)
    kind = "func" if m else "decl"
    name = m.group(2) if m else line
    body = [line]
    i += 1
    # the body runs until the next top-level line (blank lines inside belong to it)
    while i < len(src) and (not src[i] or src[i][0].isspace()):
        body.append(src[i])
        i += 1
    # trailing blank lines go back to the pending pool for the next unit
    trail = []
    while body and body[-1] == "":
        trail.append(body.pop())
    # a comment block directly above (separated by at most blank lines) is the unit's doc
    lead = pending
    pending = trail
    units.append({"kind": kind, "name": name, "lines": lead + body})

# leftover header lines are the file doc; strip trailing blanks
while header and header[-1] == "":
    header.pop()
extends_line = next(l for l in header if l.startswith("extends"))
doc = [l for l in header if not l.startswith("extends")]

layers = plan["layers"]
where = {}
for li, L in enumerate(layers):
    for f in L["funcs"]:
        where[f] = li
top_index = len(layers)
buckets = [[] for _ in range(len(layers) + 1)]
missing = set(where)
for u in units:
    if u["kind"] == "decl":
        buckets[0].append(u)
    else:
        li = where.get(u["name"], top_index)
        missing.discard(u["name"])
        buckets[li].append(u)
if missing:
    print("functions in the plan but not in the file:", sorted(missing))
    sys.exit(1)


def emit(path, ext, doc_lines, bucket):
    out = [ext] + doc_lines
    for u in bucket:
        lines = list(u["lines"])
        if u["kind"] == "func":
            while lines and lines[0] == "":
                lines.pop(0)
            while out and out[-1] == "":
                out.pop()
            out += ["", ""] + lines
        else:
            if not lines[0].strip() == "" and lines[0].startswith("#"):
                while out and out[-1] == "":
                    out.pop()
                out.append("")
            out += lines
    nl = chr(10)
    text = nl.join(out).rstrip(nl) + nl
    io.open(path, "w", encoding="utf-8", newline=nl).write(text)
    print("%-50s %5d lines" % (path, text.count(nl)))


import os
prev = None
for li, L in enumerate(layers):
    os.makedirs(os.path.dirname(L["path"]), exist_ok=True)
    ext = extends_line if li == 0 else 'extends "res://%s"' % prev
    d = (doc if li == 0 else []) + ["## " + s for s in L["doc"].split("\n")]
    emit(L["path"], ext, d, buckets[li])
    prev = L["path"]
emit(plan["file"], 'extends "res://%s"' % prev, ["## " + s for s in plan["top_doc"].split("\n")], buckets[top_index])
