# Part of tools/blender/build_props.py (loaded by it inside Blender, sharing its helpers: blobs, tube,
# ell, sheet, const, lerp, G/GV, OBJS, export).
# =============================================================== giant centipede (Scolopendra)
# Facing +x, ~37 units long (55 mm), legs on the ground. Alpha = part / 16 for
# shaders/creatures/centipede.gdshader: 0 body, 1 walking legs, 2 antennae, 3 ultimate (last) legs,
# 4 forcipules (venom claws). The shader sends the leg strokes and the body wave down the body by x.

CE_PLATE = (0.13, 0.14, 0.11)      # dark olive-black tergites
CE_BELLY = (0.42, 0.33, 0.16)
CE_HEAD = (0.55, 0.2, 0.07)        # red-orange head and first plate
CE_LEG = (0.88, 0.55, 0.14)        # orange-yellow legs
CE_TIP = (0.55, 0.3, 0.08)


def centipede():
    n = 21
    x0, x1 = 16.8, -16.8
    for i in range(n):
        x = x0 + (x1 - x0) * i / (n - 1)
        w = 1.5 - 0.35 * abs(i - 9) / 12.0
        col = CE_HEAD if i == 0 else CE_PLATE

        def plate(g, nn, col=col):
            c = col if nn.y > -0.3 else CE_BELLY
            k = 1.0 + 0.25 * max(0.0, nn.y) * (0.5 + 0.5 * math.sin(g.z * 2.0))     # sheen along the plate
            return (c[0] * k, c[1] * k, c[2] * k, 0.0)
        ell("segment", (x, 0.9, 0), (1.12, 0.42, w), 0, plate, 14)
        ell("sternite", (x, 0.62, 0), (0.95, 0.3, w * 0.8), 0, const(CE_BELLY), 10)
        # walking legs: one pair per segment, out and down to the ground, a little backward
        for side in (-1, 1):
            hip = (x, 0.7, 0.85 * side * w)
            knee = (x + 0.2, 1.35, 2.3 * side)
            foot = (x - 0.35, 0.0, 3.4 * side)
            tube("leg", [hip, knee, lerp(knee, foot, 0.6), foot], [0.2, 0.17, 0.13, 0.07], 0,
                lambda g, nn: (CE_LEG[0], CE_LEG[1], CE_LEG[2], 1 / 16.0), 6)
            tube("claw", [foot, (foot[0] - 0.25, 0.0, foot[2] + 0.12 * side)], [0.06, 0.02], 0,
                lambda g, nn: (CE_TIP[0], CE_TIP[1], CE_TIP[2], 1 / 16.0), 4, cap=False)
    # head capsule, antennae, venom claws
    ell("head", (18.4, 0.9, 0), (1.55, 0.62, 1.45), 0, const(CE_HEAD), 14)
    for side in (-1, 1):
        ell("eye", (18.9, 1.25, 1.05 * side), (0.18, 0.12, 0.14), 0, const((0.05, 0.03, 0.02)), 6)
        pts = [(19.7, 1.1, 0.45 * side)]
        for k in range(1, 19):
            t = k / 18.0
            pts.append((19.7 + 7.5 * t, 1.1 + 0.9 * math.sin(t * 2.0), (0.45 + 3.6 * t * t) * side))
        tube("antenna", pts, [0.16 - 0.1 * k / 18.0 for k in range(19)], 0,
            lambda g, nn: (0.75, 0.32, 0.1, 2 / 16.0), 5)
        fc = [(18.6, 0.45, 0.9 * side), (19.6, 0.35, 0.95 * side), (20.3, 0.35, 0.45 * side), (20.4, 0.38, 0.1 * side)]
        tube("forcipule", fc, [0.32, 0.26, 0.18, 0.06], 0,
            lambda g, nn: ((0.12, 0.05, 0.03, 4 / 16.0) if g.x > 20.0 else (0.5, 0.18, 0.06, 4 / 16.0)), 6)
        # the long last pair of legs, held out behind like tails
        ul = [(-17.3, 0.85, 0.8 * side), (-19.5, 0.8, 1.4 * side), (-22.0, 0.65, 1.9 * side), (-24.3, 0.5, 2.1 * side)]
        tube("ultimate_leg", ul, [0.28, 0.24, 0.18, 0.08], 0,
            lambda g, nn: (0.7, 0.3, 0.09, 3 / 16.0), 6)
