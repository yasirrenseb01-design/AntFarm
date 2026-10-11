# Part of tools/blender/build_props.py (loaded by it inside Blender, sharing its helpers: blobs, tube,
# ell, sheet, const, lerp, G/GV, OBJS, export).
# =============================================================== ground beetle (Carabidae)
# Facing +x, ~17 units long (25 mm), feet at y = 0. Alpha = part / 16 for
# shaders/creatures/beetle.gdshader: 0 body, 1 head, 2/3 left/right antenna, 4-9 legs
# (front-left, front-right, mid-left, mid-right, hind-left, hind-right), 10 mandibles.
# Hip pivots there: x = 3.6 / 1.2 / -0.6, y = 1.5, z = 1.4 * side.

BE_BLACK = (0.07, 0.07, 0.09)
BE_VIOLET = (0.17, 0.15, 0.34)
BE_GROOVE = (0.03, 0.03, 0.04)
BE_LEG = (0.05, 0.05, 0.06)
BE_HIPS = [3.6, 1.2, -0.6]


def beetle_body_col(g, n):
    c = BE_BLACK
    x = g.x
    if x < 1.0:                                   # elytra: fine lengthwise striae, violet edges, the suture
        if n.y > 0.2 and abs(math.sin(g.z * 9.0)) < 0.14:
            c = BE_GROOVE
        elif abs(g.z) < 0.08 and n.y > 0.5:
            c = BE_GROOVE
        elif abs(g.z) > 2.6:
            c = BE_VIOLET
    elif x < 5.3:                                 # pronotum with violet side margins
        if abs(g.z) > 2.0:
            c = BE_VIOLET
    return (c[0], c[1], c[2], 0.0)


def ground_beetle():
    flat = Matrix.Identity(4)
    blobs("elytra", [((-2.5, 2.1, 0), (6.2, 1.65, 3.1), flat)], 0,
        beetle_body_col, 0.06, 6, 2000)
    blobs("pronotum", [((3.2, 2.15, 0), (1.1, 0.95, 1.9), flat), ((4.4, 2.3, 0), (1.25, 1.05, 2.55), flat)], 0,
        beetle_body_col, 0.05, 6, 1000)
    blobs("thorax_under", [((1.0, 1.35, 0), (3.0, 0.7, 1.6), flat)], 0, const(BE_BLACK), 0.07, 4, 400)
    blobs("head", [((6.4, 2.0, 0), (1.55, 0.95, 1.4), flat), ((7.6, 1.85, 0), (0.7, 0.5, 0.9), flat)], 0,
        lambda g, n: (BE_BLACK[0], BE_BLACK[1], BE_BLACK[2], 1 / 16.0), 0.05, 5, 800)
    for side in (-1, 1):
        ell("eye", (6.9, 2.35, 1.2 * side), (0.42, 0.38, 0.3), 0, const((0.02, 0.02, 0.02, 1 / 16.0)), 10)
        # sickle-shaped mandibles crossing in front of the head
        tube("mandible", [(7.6, 1.75, 0.65 * side), (8.7, 1.7, 0.75 * side), (9.5, 1.65, 0.4 * side), (9.75, 1.62, 0.0)],
            [0.32, 0.26, 0.16, 0.05], 0, const((0.04, 0.03, 0.03, 10 / 16.0)), 7)
        tube("palp", [(7.9, 1.4, 0.5 * side), (8.6, 1.0, 0.8 * side), (9.0, 0.8, 0.9 * side)], [0.1, 0.08, 0.06], 0,
            const((0.06, 0.05, 0.05, 1 / 16.0)), 5)
        # 11-segmented antennae, long and slightly beaded
        part = 2 if side < 0 else 3
        pts = [(7.4, 2.4, 0.95 * side)]
        for k in range(1, 12):
            t = k / 11.0
            pts.append((7.4 + 7.0 * t, 2.4 + 1.6 * math.sin(t * 2.2), (0.95 + 4.2 * t * t) * side))
        for k in range(11):
            a, b = pts[k], pts[k + 1]
            r = 0.15 - 0.05 * k / 10.0
            tube("antenna", [a, lerp(a, b, 0.5), b], [r * 0.8, r, r * 0.85], 0, const((0.05, 0.05, 0.06, part / 16.0)), 5, cap=False)
    # six long running legs: coxa, femur up and out, tibia down with spurs, five-segmented tarsus
    legs = [((1.5, 2.6, 4.0), (3.5, 0.0, 5.6)), ((-0.2, 2.75, 4.5), (-1.2, 0.0, 7.0)), ((-1.8, 2.6, 4.0), (-6.0, 0.0, 6.3))]
    for li in range(3):
        for side in (-1, 1):
            part = 4 + li * 2 + (0 if side < 0 else 1)
            hx = BE_HIPS[li]
            hip = (hx, 1.5, 1.4 * side)
            kd, fd = legs[li]
            knee = (hx + kd[0], kd[1], kd[2] * side)
            foot = (hx + fd[0], fd[1], fd[2] * side)
            ankle = lerp(knee, foot, 0.72)
            ankle = (ankle[0], ankle[1] + 0.25, ankle[2])
            pc = lambda g, n, p=part: (BE_LEG[0], BE_LEG[1], BE_LEG[2], p / 16.0)
            tube("femur", [hip, lerp(hip, knee, 0.15), lerp(hip, knee, 0.55), knee], [0.42, 0.42, 0.4, 0.28], 0, pc, 7)
            tube("tibia", [knee, lerp(knee, ankle, 0.5), ankle], [0.24, 0.24, 0.27], 0, pc, 7)
            for sp in (-0.15, 0.15):
                tube("spur", [ankle, (ankle[0] + sp, ankle[1] - 0.3, ankle[2] + 0.35 * side)], [0.06, 0.01], 0, pc, 4, cap=False)
            prev = ankle
            for k in range(5):
                p = lerp(ankle, foot, (k + 1) / 5.0)
                tube("tarsus", [prev, p], [0.14 - 0.015 * k, 0.12 - 0.015 * k], 0, pc, 5, cap=False)
                prev = p
