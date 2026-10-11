# Part of tools/blender/build_props.py (loaded by it inside Blender, sharing its helpers: blobs, tube,
# ell, sheet, const, lerp, G/GV, OBJS, export).
# =============================================================== house cricket (Acheta domesticus)
# A dead female lying slightly on its side, facing +x, ~13 units (20 mm) long. Exported in pieces so
# the game can deflate the abdomen and let a hind leg fall off as the ants hollow it out:
# 0 head + pronotum + antennae, 1 abdomen + wings + cerci + ovipositor, 2/4 left/right hind leg, 3 fore/mid legs.

TAN = (0.5, 0.39, 0.25)
DARKB = (0.18, 0.12, 0.07)


def cricket_col(g, n):
    c = list(TAN)
    dark = 0.0
    x = g.x
    if x > 3.0:                                                    # head: dark band between the eyes, pale face
        dark = max(dark, math.exp(-((x - 4.15) / 0.35) ** 2) * (1.0 if g.y > 2.1 else 0.0))
        dark = max(dark, 0.6 * math.exp(-((g.y - 2.6) / 0.25) ** 2) * math.exp(-((x - 3.5) / 0.4) ** 2))
    elif x > 0.6:                                                  # pronotum: two dark blotches on the disc
        dark = max(dark, math.exp(-((x - 2.1) / 0.5) ** 2) * math.exp(-((abs(g.z) - 0.6) / 0.3) ** 2) * (1.0 if g.y > 2.6 else 0.0))
        dark = max(dark, 0.5 * math.exp(-((x - 0.85) / 0.15) ** 2))
    else:                                                          # abdomen: dark hind edge on each plate
        ph = ((x + 0.4) / 0.95) % 1.0
        dark = max(dark, 0.75 * math.exp(-((ph - 0.08) / 0.08) ** 2) * (1.0 if n.y > -0.2 else 0.3))
    k = min(1.0, dark)
    return (c[0] + (DARKB[0] - c[0]) * k, c[1] + (DARKB[1] - c[1]) * k, c[2] + (DARKB[2] - c[2]) * k, 0.0)


def cricket():
    flat = Matrix.Identity(4)
    blobs("abdomen", [
        (( -1.6, 1.6, 0), (3.6, 1.35, 1.55), flat),
        (( 0.5, 1.75, 0), (1.2, 1.3, 1.4), flat),
    ], 1, cricket_col, 0.09, 6, 2200,
        carvefn=lambda g: (-0.07 * math.exp(-((((g.x + 0.4) / 0.95) % 1.0 - 0.02) / 0.06) ** 2)) if g.x < 0.4 else 0.0)
    blobs("pronotum", [((2.0, 1.85, 0), (1.45, 1.25, 1.45), flat), ((2.0, 2.4, 0), (1.3, 0.7, 1.35), flat)], 0, cricket_col, 0.08, 6, 1200)
    blobs("head", [((3.75, 1.75, 0), (1.15, 1.2, 1.2), flat), ((4.6, 1.2, 0), (0.6, 0.65, 0.8), flat)], 0, cricket_col, 0.07, 6, 1200)
    for side in (-1, 1):
        ell("eye", (4.25, 2.2, 0.85 * side), (0.38, 0.42, 0.3), 0, const((0.05, 0.04, 0.03)), 12)
        # filiform antennae, longer than the body
        pts = [(4.7, 2.45, 0.35 * side)]
        for i in range(1, 9):
            t = i / 8.0
            pts.append((4.7 + 13.0 * t, 2.45 + 1.2 * math.sin(t * 2.2) - 2.2 * t * t, (0.35 + 4.6 * t) * side))
        tube("antenna", pts, [0.07 - 0.04 * i / 8.0 for i in range(9)], 0, const((0.42, 0.32, 0.2)), 4, cap=False)
        # mouthparts: palps
        tube("palp", [(4.8, 0.95, 0.35 * side), (5.2, 0.55, 0.55 * side), (5.3, 0.15, 0.5 * side)], [0.1, 0.08, 0.07], 0, const(TAN), 5)
        # cerci: long, pale, tapering
        tube("cercus", [(-4.9, 1.75, 0.3 * side), (-6.6, 1.65, 1.0 * side), (-8.2, 1.5, 1.5 * side)], [0.12, 0.08, 0.03], 1, const((0.56, 0.45, 0.3)), 5)
        # forewings: short, veined wing pads over the back of the abdomen
        outline = [(0.0, 0.0), (-1.5, 0.25), (-3.6, 0.35), (-4.4, 0.1), (-4.2, -0.6), (-2.0, -1.05), (0.0, -0.9)]
        xf = Matrix.Translation(Vector((0.7, 2.85, 0.0))) @ Matrix.Diagonal((1, 1, side, 1))
        sheet("forewing", outline, xf, lambda u, v: -0.18 * v * v, 1,
            lambda g, n: (0.42, 0.33, 0.21, 0.0) if abs(math.sin(g.x * 3.2 + g.z * 2.0)) > 0.9 else (0.52, 0.42, 0.28, 0.0), 0.05)
        # hind leg: a massive femur striped with dark chevrons, a spiny tibia, three tarsal segments
        fem = [(0.6, 1.9, 1.5 * side), (-0.6, 2.3, 1.85 * side), (-2.2, 2.0, 2.0 * side), (-3.4, 1.35, 2.05 * side)]
        hg = 2 if side < 0 else 4                                    # each hind leg its own piece: it can come off
        tube("hind_femur", fem, [0.42, 0.62, 0.48, 0.25], hg,
            lambda g, n: (DARKB + (0.0,)) if (math.sin((g.x + g.y * 0.8) * 4.2) > 0.75 and n.y > -0.3) else (0.58, 0.46, 0.3, 0.0), 8)
        knee = (-3.4, 1.35, 2.05 * side)
        heel = (-5.7, 0.28, 2.35 * side)
        tube("hind_tibia", [knee, lerp(knee, heel, 0.5), heel], [0.2, 0.17, 0.15], hg, const((0.56, 0.44, 0.29)), 6)
        for row in (-1, 1):
            for sp in range(5):
                at = lerp(knee, heel, 0.25 + sp * 0.15)
                tube("spine", [at, (at[0] - 0.12, at[1] + 0.5, at[2] + 0.18 * side * row)], [0.05, 0.01], hg, const((0.66, 0.55, 0.38)), 4, cap=False)
        tars = [heel, (-6.3, 0.12, 2.6 * side), (-6.9, 0.05, 2.75 * side), (-7.3, 0.0, 2.8 * side)]
        tube("hind_tarsus", tars, [0.14, 0.12, 0.1, 0.06], hg, const((0.52, 0.41, 0.27)), 5)
        for li, x in enumerate((3.0, 1.4)):
            hip = (x, 1.0, 0.9 * side)
            k_ = (x + 0.6, 0.75, 2.0 * side)
            f_ = (x + 1.1, 0.05, 2.7 * side)
            tube("leg", [hip, k_], [0.22, 0.17], 3, const((0.55, 0.43, 0.28)), 6)
            tube("leg", [k_, lerp(k_, f_, 0.8), f_], [0.14, 0.12, 0.08], 3, const((0.52, 0.41, 0.27)), 5)
    tube("ovipositor", [(-4.7, 1.45, 0), (-6.5, 1.45, 0), (-8.1, 1.6, 0)], [0.12, 0.1, 0.07], 1, const((0.15, 0.1, 0.06)), 6)
