# Part of tools/blender/build_props.py (loaded by it inside Blender, sharing its helpers: blobs, tube,
# ell, sheet, const, lerp, G/GV, OBJS, export).
# =============================================================== black bean aphid (Aphis fabae)
# Facing +x, back up (+y), legs down; about 1.35 units (2 mm) long for an adult.

def aphid(kind, ox):
    """kind 0 wingless adult, 1 nymph, 2 winged adult; built at x offset ox, group = kind."""
    s = 1.0 if kind != 1 else 0.6
    body = (0.17, 0.18, 0.2) if kind != 1 else (0.3, 0.31, 0.32)

    def body_col(g, n):
        # matt dark olive-black; transverse rows of white wax flecks on the back of the abdomen
        x = (g.x - ox) / s
        c = list(body)
        if n.y > 0.35 and -0.75 < x < 0.3:
            row = math.cos((x + 0.1) * math.pi / 0.22)
            if row > 0.55 and abs(math.sin(g.z / s * 14.0)) > 0.35:
                k = (row - 0.55) / 0.45 * (1.3 if kind == 1 else 1.0)
                c = [ci + (0.78 - ci) * min(1.0, k) for ci in c]
        return (c[0], c[1], c[2], 0.0)

    def X(x, y, z):
        return (ox + x * s, y * s, z * s)

    abd_items = [
        (X(-0.15, 0.42, 0), (0.62 * s, 0.42 * s, 0.46 * s), Matrix.Identity(4)),
        (X(0.42, 0.42, 0), (0.32 * s, 0.28 * s, 0.32 * s), Matrix.Identity(4)),       # thorax
        (X(0.72, 0.38, 0), (0.18 * s, 0.18 * s, 0.21 * s), Matrix.Identity(4)),       # head
    ]
    if kind == 2:
        abd_items[1] = (X(0.4, 0.5, 0), (0.36 * s, 0.34 * s, 0.33 * s), Matrix.Identity(4))
        abd_items[0] = (X(-0.2, 0.4, 0), (0.55 * s, 0.36 * s, 0.4 * s), Matrix.Identity(4))
    blobs("aphid_body", abd_items, kind, body_col, 0.018 * s, 5, 1400,
        carvefn=lambda g: -0.012 * s * max(0.0, math.cos(((g.x - ox) / s + 0.1) * math.pi / 0.2)) if g.y > 0.45 * s else 0.0)
    pale = (0.72, 0.72, 0.6)
    dark = (0.08, 0.08, 0.08)

    def leg_col(t):
        # pale legs with dark knees and feet
        return lambda g, n: (dark if False else pale) + (0.0,)

    for side in (-1, 1):
        ell("eye", X(0.8, 0.46, 0.15 * side), (0.06 * s, 0.065 * s, 0.05 * s), kind, const((0.3, 0.05, 0.03)), 8)
        # six-segmented antennae, about two thirds of the body, swept back over the back
        ant = [X(0.85, 0.5, 0.07 * side), X(0.98, 0.68, 0.18 * side), X(0.8, 0.88, 0.32 * side), X(0.35, 0.95, 0.42 * side),
            X(-0.15, 0.88, 0.48 * side), X(-0.45, 0.8, 0.5 * side)]
        tube("antenna", ant, [0.024 * s, 0.022 * s, 0.02 * s, 0.018 * s, 0.016 * s, 0.012 * s], kind,
            lambda g, n: ((0.18, 0.18, 0.16, 0.0) if (g.x - ox) / s < -0.2 else (0.68, 0.68, 0.56, 0.0)), 5)
        # siphunculi (cornicles): black tubes on the back of the abdomen, and the finger-like cauda
        tube("cornicle", [X(-0.5, 0.62, 0.17 * side), X(-0.6, 0.68, 0.2 * side), X(-0.7, 0.71, 0.22 * side)],
            [0.04 * s, 0.035 * s, 0.03 * s], kind, const(dark), 6)
        for li, x in enumerate((0.52, 0.38, 0.2)):
            hip = X(x, 0.24, 0.16 * side)
            knee = X(x + (0.1 if li < 2 else -0.15), 0.5, (0.62 + 0.1 * li) * side)
            foot = X(x + (0.18 if li < 2 else -0.35), 0.0, (0.82 + 0.12 * li) * side)
            tube("femur", [hip, knee], [0.035 * s, 0.03 * s], kind, const((0.3, 0.29, 0.24)), 5)
            tube("tibia", [knee, lerp(knee, foot, 0.85)], [0.028 * s, 0.024 * s], kind, const(pale), 5)
            tube("tarsus", [lerp(knee, foot, 0.85), foot], [0.024 * s, 0.015 * s], kind, const(dark), 4)
    tube("cauda", [X(-0.75, 0.38, 0), X(-0.88, 0.4, 0)], [0.05 * s, 0.03 * s], kind, const(dark), 6)
    # the beak: a jointed rostrum folded back under the body (in the plant while feeding)
    tube("rostrum", [X(0.8, 0.22, 0), X(0.55, 0.08, 0), X(0.2, 0.02, 0)], [0.03 * s, 0.025 * s, 0.015 * s], kind, const((0.25, 0.24, 0.2)), 5)
    if kind == 2:
        for side in (-1, 1):
            outline = []
            for j in range(16):
                a = math.tau * j / 16
                outline.append((math.cos(a) * 0.95 - 0.75, math.sin(a) * 0.3))
            xf = Matrix.Translation(Vector(X(0.45, 0.78, 0.1 * side))) @ Matrix.Rotation(-0.2 * side, 4, "Y") @ Matrix.Diagonal((s, s, s * side, 1))
            o = sheet("wing", outline, xf, lambda u, v: -0.04 * u, 3, const((0.9, 0.93, 1.0)), 0.0, True)
            # wing veins: the dark pterostigma near the front edge
            ell("stigma", X(0.05, 0.84, (0.12 + 0.22) * side), (0.18 * s, 0.01, 0.03 * s), 3, const((0.15, 0.15, 0.13)), 6)
