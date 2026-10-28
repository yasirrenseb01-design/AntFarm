# Part of tools/blender/build_props.py (loaded by it inside Blender, sharing its helpers: blobs, tube,
# ell, sheet, const, lerp, G/GV, OBJS, export).
# =============================================================== broad bean shoot (Vicia faba)
# Built at four growth stages (0 a young shoot with two leaves ... 3 the grown shoot in flower), the same plant each
# time: a node keeps its place and its leaf, older ones only bigger (scripts/view/common/parts/mesh_kit_base.gd picks the
# stage from the plant's age). Exported per variant and stage with its stem line (plant<k>_<g>.json) so aphids and ants
# sit on it.
# After Vicia faba (docs/BIOLOGY.md "ถั่วปากอ้า"): a square, hollow, ribbed stem; leaves of 2-6 leaflets with no tendril
# (a small point ends the rachis), the lowest leaves with one pair; glaucous blue-green, oval leaflets with a pale midrib;
# stipules with a dark purple nectary spot underneath; flowers in short clusters in the leaf axils, white with a black
# blotch on the wings and fine dark veins on the standard. [Inference: how long each stage takes, the shoot's size -
# a few cm, the box's scale, not a field bean's metre.]

PL_STAGE_H = [0.36, 0.58, 0.8, 1.0]       # of the grown height
PL_STAGE_R = [0.62, 0.78, 0.92, 1.0]      # stem thickness
PL_STAGE_NODES = [3, 4, 6, 7]
PL_NODES = 7
PL_STEM = (0.33, 0.46, 0.25)
PL_LEAF = (0.22, 0.37, 0.24)              # glaucous, a little blue


def _pl_leaflet(name, base, ang, droop, length, width, base_col, rng):
    """One oval leaflet from `base`, pointing along `ang`; cupped a little, a pale midrib and faint side veins,
    paler underneath."""
    outline = []
    for j in range(26):
        a = math.tau * j / 26
        u = (math.cos(a) + 1.0) * 0.5
        # broadest a little beyond the middle, a rounded tip with a tiny point (mucronate)
        w = math.sin(a) * width * (0.78 + 0.32 * u - 0.2 * u ** 4)
        outline.append((u * length * (1.0 + (0.03 if abs(math.sin(a)) < 0.12 and u > 0.5 else 0.0)), w))
    twist = rng.uniform(-0.15, 0.15)
    xf = Matrix.Translation(base) @ Matrix.Rotation(-ang, 4, "Y") @ Matrix.Rotation(droop, 4, "Z") @ Matrix.Rotation(twist, 4, "X")
    inv = xf.inverted()
    L, W = length, width

    def lift(u, v):
        return -u * u * 0.014 + (v / W) ** 2 * 0.12 * W - abs(v) * 0.04 + 0.05 * math.sin(u / L * 9.0 + v) * (abs(v) / W)

    def col(g, n):
        q = inv @ Vector((g.x, g.y, g.z))
        u, v = q.x, q.z
        c = list(base_col)
        under = n.y < 0.0
        if under:
            c = [ci * 1.2 + 0.05 for ci in c]                      # paler underneath
        if abs(v) < 0.035 * L + 0.02:
            c = [min(1.0, ci * 1.35 + 0.06) for ci in c]          # the midrib
        elif abs(math.sin((u - abs(v) * 1.4) / L * 18.0)) < 0.09 and abs(v) < W * 0.8:
            c = [min(1.0, ci * 1.12 + 0.02) for ci in c]          # side veins
        k = 0.93 + 0.1 * math.sin(u * 3.1 + v * 5.3) * math.sin(v * 2.3)
        return (c[0] * k, c[1] * k, c[2] * k, 0.0)

    return sheet(name, outline, xf, lift, 0, col, 0.035)


def plant(variant, stage=3):
    rng = random.Random(1000 + variant)
    H = rng.uniform(22.0, 28.0)
    lean = Vector((rng.uniform(-1.6, 1.6), 0, rng.uniform(-1.6, 1.6)))
    nodes = PL_STAGE_NODES[stage]
    node_y = [H * (0.1 + 0.78 * nd / (PL_NODES - 1)) for nd in range(PL_NODES)]
    h = H * PL_STAGE_H[stage]
    grow = 0.55 + 0.45 * stage / 3.0                    # how big the young leaves at the top are yet
    stem_pts = []
    for i in range(9):
        t = i / 8.0
        y = h * t
        p = Vector((0, y, 0)) + lean * (y / H) ** 2
        stem_pts.append((p.x, p.y, p.z))
    R = 0.55 * PL_STAGE_R[stage]

    def stem_col(g, n):
        # four green ribs at the corners of the square stem, slightly paler and bluish
        ax = stem_at(g.y)
        dx, dz = g.x - ax[0], g.z - ax[2]
        a = math.atan2(dz, dx)
        rib = abs(math.cos(2.0 * a))
        k = 0.92 + 0.1 * rib + 0.04 * math.sin(g.y * 2.7)
        return (PL_STEM[0] * k, PL_STEM[1] * k, PL_STEM[2] * (k + 0.06 * rib), 0.0)

    def stem_at(y):
        for i in range(len(stem_pts) - 1):
            a, b = stem_pts[i], stem_pts[i + 1]
            if y <= b[1] or i == len(stem_pts) - 2:
                return lerp(a, b, max(0.0, min(1.0, (y - a[1]) / max(0.001, b[1] - a[1]))))
        return stem_pts[-1]

    tube("stem", stem_pts, [R * (1.0 - 0.32 * i / 8.0) for i in range(9)], 0, stem_col, 12, cap=True, square=True)
    for nd in range(nodes):
        nr = random.Random(5000 + variant * 31 + nd)       # the node's own leaf: the same at every stage
        y = node_y[nd]
        if y > h - 1.2:
            break
        at = stem_at(y)
        ang = nd * 2.4 + nr.uniform(-0.3, 0.3)
        d = Vector((math.cos(ang), 0, math.sin(ang)))
        side = d.cross(Vector((0, 1, 0)))
        age = (nodes - 1 - nd)                              # leaves below are older and full grown
        size = (1.0 - 0.4 * nd / PL_NODES) * min(1.0, grow + 0.22 * age)
        ell("node", at, (R * 1.25, R * 0.7, R * 1.25), 0, const((0.3, 0.42, 0.22)), 10)
        # stipules: two small half-arrow ears at the node, a dark purple nectary spot on each (ants drink there)
        for sd in (-1, 1):
            sp = Vector(at) + side * sd * (R + 0.25) + Vector((0, 0.15, 0))
            outline = [(0.0, 0.0), (0.55, 0.12), (0.75, 0.32), (0.45, 0.42), (0.6, 0.6), (0.2, 0.45), (-0.25, 0.3)]
            xf = Matrix.Translation(sp) @ Matrix.Rotation(-(ang + sd * 1.3), 4, "Y") @ Matrix.Rotation(0.5, 4, "Z")
            sheet("stipule", [(u * size, v * size * sd) for u, v in outline], xf, lambda u, v: 0.04, 0,
                const((0.38, 0.52, 0.28)), 0.03)
            ell("nectary", tuple(sp + Vector((0, -0.04, 0)) + side * sd * 0.18 * size), (0.09, 0.05, 0.09), 0,
                const((0.22, 0.06, 0.2)), 6)
        # the leaf: a stalk out and up, leaflets in pairs not quite opposite, a small point at the end
        pairs = 1 if nd == 0 else (2 if nd < 3 else 3)
        reach = (2.2 + 1.6 * pairs) * size
        tip = Vector(at) + d * reach + Vector((0, (1.1 + 0.3 * pairs) * size, 0))
        mid = Vector(at).lerp(tip, 0.5) + Vector((0, 0.35 * size, 0))
        tube("rachis", [at, tuple(mid), tuple(tip)], [0.2, 0.15, 0.08], 0, const((0.33, 0.46, 0.25)), 6, cap=False)
        tube("mucro", [tuple(tip), tuple(tip + d * 0.5 * size + Vector((0, 0.2, 0)))], [0.06, 0.01], 0,
            const((0.36, 0.5, 0.27)), 4, cap=False)
        leaf_col = (PL_LEAF[0] + nr.uniform(-0.02, 0.03), PL_LEAF[1] + nr.uniform(-0.03, 0.03), PL_LEAF[2] + nr.uniform(-0.02, 0.02))
        for pr in range(pairs):
            for sd in (-1, 1):
                t = (0.35 + 0.65 * (pr + (0.12 if sd > 0 else 0.0)) / max(1, pairs)) if pairs > 1 else 0.85
                base = Vector(at).lerp(tip, min(1.0, t)) + Vector((0, 0.06, 0))
                la = ang + sd * nr.uniform(0.9, 1.3)
                length = nr.uniform(5.0, 6.6) * size
                _pl_leaflet("leaflet", base, la, nr.uniform(0.05, 0.35), length, length * 0.27, leaf_col, nr)
        if stage >= 2 and nd >= 2 and nr.random() < 0.8:
            # a short cluster of flowers in the leaf axil: green calyx, white standard with dark veins, black-blotched wings
            fb = Vector(at) + d * 0.9 + Vector((0, 0.6, 0))
            for fl in range(2 if stage == 2 else 3):
                fa = ang + 0.9 * (fl - 1)
                fd = Vector((math.cos(fa), 0, math.sin(fa)))
                fp = fb + fd * 0.6 + Vector((0, 0.35 * fl, 0))
                tube("pedicel", [tuple(fb), tuple(fp)], [0.07, 0.05], 0, const((0.33, 0.46, 0.25)), 4, cap=False)
                tube("calyx", [tuple(fp), tuple(fp + fd * 0.45 + Vector((0, 0.05, 0)))], [0.16, 0.22], 0, const((0.34, 0.47, 0.27)), 7)
                fc = fp + fd * 0.7
                std_out = [(math.cos(a) * 0.45 + 0.1, math.sin(a) * 0.5) for a in [math.tau * j / 14 for j in range(14)]]
                xf = Matrix.Translation(fc + Vector((0, 0.15, 0))) @ Matrix.Rotation(-fa, 4, "Y") @ Matrix.Rotation(1.25, 4, "Z")
                inv = xf.inverted()

                def std_col(g, n, inv=inv):
                    q = inv @ Vector((g.x, g.y, g.z))
                    vein = abs(math.sin(math.atan2(q.z, q.x + 0.4) * 9.0)) < 0.15 and q.x < 0.25
                    return (0.42, 0.33, 0.36, 0.0) if vein else (0.95, 0.94, 0.9, 0.0)
                sheet("standard", std_out, xf, lambda u, v: -(v * v) * 0.5, 0, std_col, 0.03)
                for sd in (-1, 1):
                    wp = fc + fd.cross(Vector((0, 1, 0))) * sd * 0.2 + fd * 0.15 + Vector((0, 0.02, 0))
                    ell("wing_petal", tuple(wp), (0.32, 0.18, 0.12), 0,
                        lambda g, n, wp=wp: (0.06, 0.05, 0.05, 0.0) if (Vector((g.x, g.y, g.z)) - wp).length < 0.2 else (0.93, 0.92, 0.88, 0.0), 10)
                ell("keel", tuple(fc + fd * 0.1 + Vector((0, -0.08, 0))), (0.28, 0.12, 0.1), 0, const((0.9, 0.9, 0.84)), 8)
    # the growing tip: young leaves still folded round the shoot (smaller each stage toward the top)
    top = Vector(stem_pts[-1])
    for i in range(4):
        a = i * 1.9 + variant
        ell("bud", tuple(top + Vector((math.cos(a) * 0.35, 0.45 + i * 0.3, math.sin(a) * 0.35))),
            (0.38 * grow + 0.1, (1.15 - i * 0.18) * grow, 0.26), 0, const((0.4, 0.56, 0.32)), 10,
            Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(0.3, 4, "X"))
    return stem_pts


def flex_export(path, stem):
    """Plants bend with the wind away from the stem: alpha = distance from the stem axis, capped."""
    def stem_axis(y):
        for i in range(len(stem) - 1):
            a, b = stem[i], stem[i + 1]
            if y <= b[1] or i == len(stem) - 2:
                return lerp(a, b, max(0.0, min(1.0, (y - a[1]) / max(0.001, b[1] - a[1]))))
        return stem[-1]
    for o in OBJS:
        fn = COLFNS[o["colfn"]]

        def wrap(g, n, fn=fn):
            c = fn(g, n)
            ax = stem_axis(g.y)
            d = math.hypot(g.x - ax[0], g.z - ax[2])
            return (c[0], c[1], c[2], max(0.0, min(0.4, (d - 0.8) * 0.08)))
        COLFNS[o["colfn"]] = wrap
    export(path)
