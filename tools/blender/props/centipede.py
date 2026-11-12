# Part of tools/blender/build_props.py (loaded by it inside Blender, sharing its helpers: blobs, tube,
# ell, sheet, const, lerp, G/GV, OBJS, export).
# =============================================================== stone centipede (Lithobius forficatus)
# The centipede of temperate gardens (v0.8.6, replacing the Mediterranean Scolopendra): 20–30 mm long,
# glossy chestnut-brown and flattened, 15 pairs of legs, tergites alternately long and short (the mark
# of the Lithobiomorpha), long many-jointed antennae, the last leg pair longer and held out behind.
# Facing +x, ~16.5 units long (25 mm), legs on the ground. Alpha = part / 16 for
# shaders/creatures/centipede.gdshader: 0 body, 1 walking legs, 2 antennae, 3 ultimate (last) legs,
# 4 forcipules (venom claws). The shader sends the leg strokes and the body wave down the body by x.
# Shader constants that depend on this shape: ANT_X (antenna base 9.2), FANG_X (8.6).
# Walking legs (v0.12.35): jointed like the spider's (knee bent upward: up_knee in beetle.py) - 30 of them, so each
# vertex's 11th number is 4 x the leg's number + its piece (1 coxa + femur, 2 tibia, 3 claw), the legs numbered pair by
# pair from the head, left then right; their joints at rest go to centipede.json for shaders/creatures/leg_ik.gdshaderinc.

LI_PLATE = (0.36, 0.17, 0.08)      # chestnut tergites
LI_EDGE = (0.22, 0.1, 0.05)        # darker hind margins
LI_BELLY = (0.62, 0.42, 0.24)
LI_HEAD = (0.4, 0.19, 0.08)
LI_LEG = (0.72, 0.48, 0.28)        # paler, translucent-looking legs
LI_TIP = (0.4, 0.25, 0.13)


LI_STRIDE = 1.4             # how far a foot is carried in a step (model units; the game's: creature_rig.gd)


def centipede():
    n = 15                                         # leg-bearing segments
    joints = {"hips": [], "knees": [], "ankles": [], "bends": [], "stride": LI_STRIDE, "knee_up": 1.0, "lift": 0.22}
    x0, x1 = 7.2, -7.4
    for i in range(n):
        x = x0 + (x1 - x0) * i / (n - 1)
        longp = i % 2 == 0 or i in (7, 9)          # alternately long and short back plates
        w = 1.25 - 0.3 * abs(i - 6) / 8.0
        lx = 0.74 if longp else 0.56            # overlapping: a continuous, flattened back

        def plate(g, nn, x=x, lx=lx):
            c = LI_PLATE if nn.y > -0.3 else LI_BELLY
            if nn.y > -0.3 and g.x < x - lx * 0.55:
                c = LI_EDGE                        # hind margin of the plate
            k = 1.0 + 0.35 * max(0.0, nn.y) * (0.5 + 0.5 * math.sin(g.z * 2.5))     # glossy
            return (c[0] * k, c[1] * k, c[2] * k, 0.0)
        ell("tergite", (x, 0.55, 0), (lx, 0.2, w), 0, plate, 14)
        ell("sternite", (x, 0.38, 0), (0.48, 0.17, w * 0.78), 0, const(LI_BELLY), 8)
        # walking legs (v0.12.35): one pair per segment, jointed - a coxa at the body's side, the femur up and out to a low
        # knee, the tibia down to the ground, a claw; the hind ones longer and swept back. Each vertex carries
        # 4 x the leg's number + its piece ("ANT2"), the joints go to centipede.json (see the top of the file).
        reach = 1.9 + 0.5 * i / (n - 1)
        for side in (-1, 1):
            idx = i * 2 + (0 if side < 0 else 1)
            lc = lambda g, nn: (LI_LEG[0], LI_LEG[1], LI_LEG[2], 1 / 16.0)
            hip = (x, 0.45, 0.72 * side * w)
            ankle = (x - 0.2 - 0.3 * i / (n - 1), 0.1, (0.72 * w + reach) * side)
            l1 = 0.5 * reach + 0.25
            l2 = 0.62 * reach + 0.35
            knee = up_knee(hip, ankle, l1, l2)
            for dx in (-0.5 * LI_STRIDE, 0.5 * LI_STRIDE):
                far = (Vector((ankle[0] + dx, ankle[1], ankle[2] + 0.6 * side)) - Vector(hip)).length      # (+ the body's sway)
                assert abs(l1 - l2) < far < l1 + l2, "centipede leg %d cannot reach its step" % idx
            joints["hips"].append(hip)
            joints["knees"].append(knee)
            joints["ankles"].append(ankle)
            joints["bends"].append((0.0, side))
            made = len(OBJS)
            ell("coxa", lerp(hip, knee, 0.12), (0.17, 0.14, 0.17), 0, lc, 6)
            tube("femur", [hip, lerp(hip, knee, 0.5), knee], [0.12, 0.115, 0.095], 0, lc, 6)
            for o in OBJS[made:]:
                o["seg"] = 4.0 * idx + 1.0
            made = len(OBJS)
            ell("knee", knee, (0.105, 0.105, 0.105), 0, lc, 6)
            tube("tibia", [knee, lerp(knee, ankle, 0.5), ankle], [0.095, 0.075, 0.05], 0, lc, 5)
            for o in OBJS[made:]:
                o["seg"] = 4.0 * idx + 2.0
            made = len(OBJS)
            tube("claw", [ankle, (ankle[0] - 0.1, 0.02, ankle[2] + 0.2 * side)], [0.045, 0.012], 0,
                lambda g, nn: (LI_TIP[0], LI_TIP[1], LI_TIP[2], 1 / 16.0), 4, cap=False)
            for o in OBJS[made:]:
                o["seg"] = 4.0 * idx + 3.0
    # the soft body under the plates, one continuous tube
    for i in range(n - 1):
        xm = x0 + (x1 - x0) * (i + 0.5) / (n - 1)
        wm = 1.15 - 0.3 * abs(i - 6) / 8.0
        ell("core", (xm, 0.5, 0), (0.6, 0.17, wm), 0, const(LI_EDGE), 10)
    # head: a flat rounded plate, clusters of simple eyes (ocelli) at the sides, antennae, venom claws
    ell("head", (8.3, 0.55, 0), (0.85, 0.3, 0.95), 0, const(LI_HEAD), 12)
    for side in (-1, 1):
        for k in range(5):
            ell("ocellus", (8.55 - 0.12 * (k % 3), 0.72, (0.62 + 0.08 * (k // 3)) * side), (0.06, 0.05, 0.06), 0,
                const((0.04, 0.03, 0.02)), 5)
        pts = [(9.2, 0.62, 0.3 * side)]
        for k in range(1, 25):
            t = k / 24.0
            pts.append((9.2 + 5.6 * t, 0.62 + 0.5 * math.sin(t * 2.2), (0.3 + 2.6 * t * t) * side))
        tube("antenna", pts, [0.08 - 0.045 * k / 24.0 for k in range(25)], 0,
            lambda g, nn: (0.55, 0.3, 0.15, 2 / 16.0), 4)
        fc = [(8.6, 0.32, 0.55 * side), (9.15, 0.28, 0.6 * side), (9.55, 0.28, 0.3 * side), (9.62, 0.3, 0.07 * side)]
        tube("forcipule", fc, [0.17, 0.14, 0.1, 0.035], 0,
            lambda g, nn: ((0.1, 0.05, 0.03, 4 / 16.0) if g.x > 9.4 else (0.42, 0.2, 0.09, 4 / 16.0)), 5)
        # the 15th (last) leg pair: longer, thicker, held out behind
        ul = [(-7.7, 0.48, 0.6 * side), (-8.8, 0.45, 1.2 * side), (-10.2, 0.35, 1.6 * side), (-11.4, 0.22, 1.75 * side)]
        tube("ultimate_leg", ul, [0.15, 0.13, 0.1, 0.05], 0,
            lambda g, nn: (0.62, 0.36, 0.18, 3 / 16.0), 5)
    return joints
