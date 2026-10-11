# Part of tools/blender/build_props.py (loaded by it inside Blender, sharing its helpers: blobs, tube,
# ell, sheet, const, lerp, G/GV, OBJS, export).
# =============================================================== broad bean shoot (Vicia faba)
# Square, slightly glaucous stem with nodes, alternate compound leaves (2-3 pairs of oval leaflets),
# a growing tip of folded young leaves, a few white flowers with the black blotch on the wings.
# Exported per variant with its stem line (assets/models/plants/plant<k>.json) so aphids and ants sit on it.

def plant(variant):
    rng = random.Random(1000 + variant)
    h = rng.uniform(22.0, 28.0)
    lean = Vector((rng.uniform(-1.6, 1.6), 0, rng.uniform(-1.6, 1.6)))
    stem_pts = []
    for i in range(9):
        t = i / 8.0
        p = Vector((0, h * t, 0)) + lean * t * t
        stem_pts.append((p.x, p.y, p.z))
    R = 0.55
    tube("stem", stem_pts, [R * (1.0 - 0.3 * i / 8.0) for i in range(9)], 0,
        lambda g, n: (0.33, 0.45, 0.24, 0.0), 8, cap=True, square=True)

    def stem_at(y):
        for i in range(len(stem_pts) - 1):
            a, b = stem_pts[i], stem_pts[i + 1]
            if y <= b[1] or i == len(stem_pts) - 2:
                return lerp(a, b, max(0.0, min(1.0, (y - a[1]) / max(0.001, b[1] - a[1]))))
        return stem_pts[-1]

    def leaf_col(base, tip_len):
        def f(g, n):
            return (base[0], base[1], base[2], 0.0)
        return f

    nodes = 5
    for nd in range(nodes):
        y = h * (0.16 + 0.72 * nd / (nodes - 1))
        at = stem_at(y)
        ang = nd * 2.4 + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(ang), 0, math.sin(ang)))
        size = 1.0 - 0.45 * nd / nodes
        # stipules: small toothed ears at the node
        ell("node", at, (R * 1.3, R * 0.9, R * 1.3), 0, const((0.3, 0.42, 0.22)), 8)
        for sd in (-1, 1):
            sp = Vector(at) + d.cross(Vector((0, 1, 0))) * sd * 0.7 + Vector((0, 0.2, 0))
            ell("stipule", tuple(sp), (0.45, 0.12, 0.3), 0, const((0.36, 0.5, 0.26)), 8)
        tip = Vector(at) + d * 3.6 * size + Vector((0, 1.4 * size, 0))
        tube("petiole", [at, tuple(Vector(at).lerp(tip, 0.5) + Vector((0, 0.3, 0))), tuple(tip)], [0.22, 0.18, 0.12], 0, const((0.33, 0.46, 0.24)), 6, cap=False)
        base_col = (0.24 + rng.uniform(-0.02, 0.03), 0.38 + rng.uniform(-0.03, 0.03), 0.2)
        pairs = 3 if nd < 2 else 2
        for pr in range(pairs):
            base = Vector(at).lerp(tip, 0.4 + 0.6 * pr / max(1, pairs - 1)) + Vector((0, 0.08, 0))
            for sd in (-1, 1):
                la = ang + sd * 1.15 + rng.uniform(-0.15, 0.15)
                length = rng.uniform(4.2, 5.6) * size
                width = length * 0.36
                outline = []
                for j in range(20):
                    a = math.tau * j / 20
                    u = (math.cos(a) + 1.0) * 0.5 * length
                    v = math.sin(a) * width * (0.85 + 0.15 * math.cos(a))
                    outline.append((u, v))
                droop = rng.uniform(0.1, 0.4)
                xf = Matrix.Translation(base) @ Matrix.Rotation(-la, 4, "Y") @ Matrix.Rotation(droop, 4, "Z")
                L = length
                sheet("leaflet", outline, xf, lambda u, v, L=L, w=width: -u * u * 0.018 + abs(v) * 0.22 - (v / w) ** 2 * 0.05 * L, 0,
                    lambda g, n, c=base_col: (c[0] + 0.04 * n.y, c[1] + 0.05 * n.y, c[2], 0.0), 0.04)
        if nd >= 2 and rng.random() < 0.7:
            # a raceme of broad bean flowers in the leaf axil: white standard, black-blotched wings
            fb = Vector(at) + d * 1.0 + Vector((0, 0.8, 0))
            for fl in range(2):
                fp = fb + Vector((math.cos(ang + fl), 0.5 * fl, math.sin(ang + fl))) * 0.8
                ell("calyx", tuple(fp), (0.35, 0.25, 0.25), 0, const((0.36, 0.48, 0.28)), 8)
                ell("standard", tuple(fp + Vector((0, 0.35, 0)) + d * 0.3), (0.55, 0.5, 0.15), 0, const((0.93, 0.92, 0.88)), 10)
                for sd in (-1, 1):
                    wp = fp + d.cross(Vector((0, 1, 0))) * sd * 0.25 + d * 0.25
                    ell("wing_petal", tuple(wp), (0.35, 0.22, 0.12), 0, const((0.08, 0.07, 0.07)), 8)
    # the growing tip: young leaves still folded around the shoot
    top = Vector(stem_pts[-1])
    for i in range(4):
        a = i * 1.9
        ell("bud", tuple(top + Vector((math.cos(a) * 0.4, 0.5 + i * 0.35, math.sin(a) * 0.4))), (0.45, 1.3 - i * 0.2, 0.3),
            0, const((0.4, 0.55, 0.3)), 10, Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(0.3, 4, "X"))
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
