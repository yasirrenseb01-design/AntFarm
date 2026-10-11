# Part of tools/blender/build_props.py (loaded by it inside Blender, sharing its helpers: blobs, tube,
# ell, sheet, const, lerp, G/GV, OBJS, export).
# =============================================================== wolf spider (Lycosidae)
# Facing +x, feet at y = 0, body length ~11 units before the game scales it by 0.85 (~14 mm).
# Hips, leg directions and lengths must match shaders/creatures/spider.gdshader (pivots
# (2.4 - 0.75 * li, 1.9, 0.9 * side)); vertex alpha = part / 16: 0 body, 1-4 left legs, 5-8 right legs.

SP_FUR = (0.31, 0.25, 0.19)
SP_DARK = (0.13, 0.1, 0.08)
SP_PALE = (0.52, 0.45, 0.35)


def with_part(fn, part):
    return lambda g, n: tuple(fn(g, n)[:3]) + (part / 16.0,)


def _mottle(g):
    return 0.88 + 0.24 * (0.5 + 0.5 * math.sin(g.x * 7.3 + g.z * 5.1) * math.sin(g.y * 6.7 - g.z * 3.3))


def carapace_col(g, n):
    # dark brown with a pale median band and pale bands along each side, like the reference photo
    c = SP_DARK
    if n.y > 0.2:
        if abs(g.z) < 0.32 + 0.12 * math.cos((g.x - 1.6) * 0.9):
            c = SP_PALE
        elif abs(abs(g.z) - 1.35) < 0.22:
            c = SP_PALE
        else:
            c = SP_FUR
    m = _mottle(g)
    return (c[0] * m, c[1] * m, c[2] * m, 0.0)


def abdomen_col(g, n):
    # grey-brown, a dark lance-shaped heart mark at the front, dark chevrons toward the spinnerets
    c = SP_FUR
    if n.y > 0.1:
        x = g.x
        if -4.6 < x < -1.0 and abs(g.z) < 0.5 * (x + 4.6) / 3.6 + 0.08:
            c = SP_DARK
        elif x < -4.4 and abs(((x + 4.4) * 1.6) % 1.0 - 0.5) < 0.18 and abs(g.z) < 1.6:
            c = SP_DARK
        elif abs(g.z) > 1.7:
            c = SP_PALE
    m = _mottle(g)
    return (c[0] * m, c[1] * m, c[2] * m, 0.0)


def wolf_spider():
    flat = Matrix.Identity(4)
    blobs("abdomen", [((-3.4, 2.1, 0), (3.3, 2.2, 2.4), flat), ((-1.0, 2.0, 0), (0.6, 0.6, 0.6), flat)], 0,
        abdomen_col, 0.07, 6, 1600)
    blobs("carapace", [((1.6, 2.2, 0), (2.5, 1.45, 1.95), flat), ((3.3, 2.5, 0), (1.0, 1.0, 1.3), flat)], 0,
        carapace_col, 0.06, 6, 1400)
    # eyes: a row of four small ones low on the face, two big forward-facing ones, two on top
    for side in (-1, 1):
        for z in (0.15, 0.42):
            ell("eye", (4.12, 2.55, z * side), (0.11, 0.11, 0.11), 0, const((0.03, 0.03, 0.03)), 8)
        ell("eye", (3.85, 3.15, 0.42 * side), (0.3, 0.3, 0.3), 0, const((0.02, 0.02, 0.02)), 12)
        ell("eye", (3.05, 3.5, 0.78 * side), (0.24, 0.24, 0.24), 0, const((0.02, 0.02, 0.02)), 10)
        # chelicerae (fangs folded under) and the short leg-like pedipalps
        tube("chelicera", [(3.9, 2.1, 0.32 * side), (4.25, 1.4, 0.35 * side), (4.15, 0.9, 0.3 * side)],
            [0.32, 0.28, 0.18], 0, const(SP_DARK), 8)
        tube("palp", [(3.6, 1.9, 0.7 * side), (4.6, 1.8, 1.2 * side), (5.1, 1.0, 1.1 * side), (5.3, 0.45, 1.0 * side)],
            [0.22, 0.2, 0.18, 0.14], 0, lambda g, n: (SP_FUR[0], SP_FUR[1], SP_FUR[2], 0.0), 6)
    tube("spinnerets", [(-6.5, 1.8, 0), (-6.9, 1.7, 0)], [0.3, 0.15], 0, const(SP_DARK), 6)
    spread = [0.55, 1.15, 1.9, 2.5]
    lens = [9.0, 8.0, 8.5, 10.5]
    for li in range(4):
        for side in (-1, 1):
            part = 1 + li + (0 if side < 0 else 4)
            a = spread[li]
            d = Vector((math.cos(a), 0, math.sin(a) * side))
            hip = Vector((2.4 - li * 0.75, 1.9, 0.9 * side))
            L = lens[li]
            knee = hip + d * L * 0.45 + Vector((0, 3.0, 0))
            foot = hip + d * L + Vector((0, -1.9, 0))
            ankle = knee.lerp(foot, 0.62) + Vector((0, 0.4, 0))
            coxa = hip + d * 0.7 + Vector((0, -0.15, 0))
            pts = [hip, coxa, coxa.lerp(knee, 0.5), knee, knee.lerp(ankle, 0.5), ankle, ankle.lerp(foot, 0.6), foot]
            radii = [0.5, 0.42, 0.36, 0.32, 0.27, 0.22, 0.17, 0.1]
            tl = [0.0, 0.08, 0.3, 0.45, 0.6, 0.75, 0.88, 1.0]

            def leg_col(g, n, hip=hip, foot=foot):
                # banded legs: dark rings at the joints on a furry grey-brown leg
                t = (Vector((g.x, g.y, g.z)) - hip).length / max(0.01, (foot - hip).length)
                ring = min(abs(t - j) for j in (0.3, 0.45, 0.75, 0.9))
                c = SP_DARK if ring < 0.045 else SP_FUR
                m = _mottle(g)
                return (c[0] * m, c[1] * m, c[2] * m, 0.0)
            tube("leg", [tuple(p) for p in pts], radii, 0, with_part(leg_col, part), 7)
            # spines along the leg
            for k in range(3):
                at = knee.lerp(ankle, 0.25 + k * 0.3)
                tube("spine", [tuple(at), tuple(at + Vector((0, 0.35, 0)) + d * 0.15)], [0.04, 0.01], 0,
                    with_part(lambda g, n: (0.1, 0.08, 0.06, 0.0), part), 4, cap=False)
    # every body piece carries part 0, legs their own id (with_part above)
    for o in OBJS:
        if o.name.startswith(("abdomen", "carapace", "eye", "chelicera", "palp", "spinnerets")):
            COLFNS[o["colfn"]] = with_part(COLFNS[o["colfn"]], 0)
