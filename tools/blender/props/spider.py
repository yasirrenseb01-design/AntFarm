# Part of tools/blender/build_props.py (loaded by it inside Blender, sharing its helpers: blobs, tube,
# ell, sheet, const, lerp, G/GV, OBJS, export).
# =============================================================== wolf spider (Lycosidae)
# Facing +x, feet at y = 0, body length ~11 units before the game scales it by 0.85 (~14 mm).
# Legs (v0.12.34): jointed like the ground beetle's (beetle.py: loft, be_knee) - the 11th number of each vertex is its
# leg piece (1 coxa + femur, 2 patella to metatarsus, 3 tarsus; "ANT2") and the joints at rest go to wolf_spider.json,
# which the game hands to shaders/creatures/leg_ik.gdshaderinc. Vertex alpha = part / 16: 0 body, 1-4 left legs front to
# back, 5-8 right legs (the json's legs in that order).

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
        elif abs(g.z) > 1.95 and n.y > 0.35:
            c = SP_PALE                                   # (a narrow pale edge: the abdomen is slimmer from v0.12.34)
    m = _mottle(g)
    return (c[0] * m, c[1] * m, c[2] * m, 0.0)


SP_STRIDE = 4.0             # how far a foot is carried in a step (model units; the game's: creature_rig.gd)
# each leg pair, front to back: hip (at the edge of the carapace's underside), which way the leg points (radians from
# straight ahead), how far out its ankle stands at mid-stance, the femur's length and the length from knee to ankle
# (patella, tibia, metatarsus) - one side (z > 0). The knee is bent upward (up_knee in beetle.py).
SP_LEGS = [
    {"hip": (3.0, 1.2, 1.3), "dir": 0.55, "out": 7.2, "femur": 3.6, "shin": 6.2},
    {"hip": (2.25, 1.2, 1.4), "dir": 1.15, "out": 6.6, "femur": 3.3, "shin": 5.6},
    {"hip": (1.5, 1.2, 1.4), "dir": 1.9, "out": 6.9, "femur": 3.4, "shin": 5.8},
    {"hip": (0.75, 1.2, 1.3), "dir": 2.5, "out": 8.2, "femur": 4.0, "shin": 7.0},
]


def _sp_car_w(x):
    # the carapace from above: a pear - broad over the legs, narrowing to the high head (x: 0 back edge .. 4.3 front)
    u = min(1.0, max(0.0, x / 4.3))
    thorax = 1.85 * max(0.0, math.sin(math.pi * min(1.0, (u + 0.1) / 0.9))) ** 0.6
    head = 1.2 * math.sqrt(max(0.0, 1.0 - max(0.0, (u - 0.8) / 0.2) ** 2.2))
    return max(thorax, head)


def _sp_car_top(x):
    # highest at the head (the eyes look over the grass), a shallow saddle behind it, sloping down to the waist
    u = min(1.0, max(0.0, x / 4.3))
    return 2.2 + 1.15 * math.sin(math.pi * (0.1 + 0.8 * u)) ** 0.7 + 0.3 * math.exp(-((u - 0.78) / 0.14) ** 2) - 0.12 * math.exp(-((u - 0.45) / 0.1) ** 2)


def _sp_ab_w(x):
    # the abdomen from above: an egg, broadest behind its middle (x: -6.6 spinnerets .. -0.4 waist)
    u = min(1.0, max(0.0, (x + 6.6) / 6.2))
    return 2.15 * math.sin(math.pi * u ** 0.85) ** 0.62


def wolf_spider():
    flat = Matrix.Identity(4)
    # the abdomen: an egg on a narrow waist, a little flattened under, highest behind its middle
    loft("abdomen", -6.6, -0.4, _sp_ab_w, lambda x: 1.0 + 0.5 * max(0.0, (-4.9 - x) / 1.7) ** 2,
        lambda x: 1.0 + 3.0 * math.sin(math.pi * min(1.0, max(0.0, (x + 6.6) / 6.2)) ** 0.9) ** 0.55, abdomen_col, 0.95, 40, 32, 0.08, 5, 1800,
        eb=0.7, wb=0.92)
    blobs("waist", [((-0.25, 1.75, 0), (0.55, 0.45, 0.5), flat)], 0, const(SP_DARK), 0.06, 3, 200)
    # the carapace: pear-shaped, the head high in front, the sides coming down over the legs' bases; under it the sternum
    loft("carapace", 0.0, 4.3, _sp_car_w, lambda x: 1.25, _sp_car_top, carapace_col, 0.8, 34, 32, 0.06, 4, 1700, eb=0.5, wb=0.7)
    ell("sternum", (1.9, 1.15, 0), (1.7, 0.3, 1.1), 0, const(SP_DARK), 10)
    # eyes: a row of four small ones low on the face, two big forward-facing ones, two on top
    for side in (-1, 1):
        for z in (0.15, 0.42):
            ell("eye", (4.27, 2.5, z * side), (0.11, 0.11, 0.11), 0, const((0.03, 0.03, 0.03)), 8)
        ell("eye", (4.08, 3.0, 0.42 * side), (0.3, 0.3, 0.3), 0, const((0.02, 0.02, 0.02)), 12)
        ell("eye", (3.45, 3.42, 0.72 * side), (0.24, 0.24, 0.24), 0, const((0.02, 0.02, 0.02)), 10)
        # chelicerae (fangs folded under) and the short leg-like pedipalps
        tube("chelicera", [(4.05, 2.0, 0.32 * side), (4.4, 1.4, 0.35 * side), (4.3, 0.9, 0.3 * side)],
            [0.34, 0.3, 0.18], 0, const(SP_DARK), 8)
        tube("palp", [(3.75, 1.7, 0.75 * side), (4.7, 1.9, 1.25 * side), (5.2, 1.1, 1.15 * side), (5.4, 0.45, 1.05 * side)],
            [0.22, 0.21, 0.18, 0.14], 0, lambda g, n: (SP_FUR[0], SP_FUR[1], SP_FUR[2], 0.0), 6)
    tube("spinnerets", [(-6.5, 1.75, 0), (-6.95, 1.6, 0)], [0.3, 0.15], 0, const(SP_DARK), 6)
    for o in OBJS:
        COLFNS[o["colfn"]] = with_part(COLFNS[o["colfn"]], 0)          # every body piece is part 0
    # eight jointed legs (see the top of the file): the coxa out from under the carapace, the femur up to a high knee, the
    # patella, tibia and metatarsus down to the ground in one gently bent piece, the tarsus on the ground
    joints = {"hips": [None] * 8, "knees": [None] * 8, "ankles": [None] * 8, "bends": [None] * 8, "stride": SP_STRIDE, "knee_up": 1.0}
    for li in range(4):
        L = SP_LEGS[li]
        hip1 = L["hip"]
        ankle1 = (hip1[0] + math.cos(L["dir"]) * L["out"], 0.3, hip1[2] + math.sin(L["dir"]) * L["out"])
        knee1 = up_knee(hip1, ankle1, L["femur"], L["shin"])
        for dx in (-0.5 * SP_STRIDE, 0.5 * SP_STRIDE):
            far = (Vector((ankle1[0] + dx, ankle1[1], ankle1[2])) - Vector(hip1)).length
            assert abs(L["femur"] - L["shin"]) < far < L["femur"] + L["shin"], "spider leg %d cannot reach its step" % li
        for side in (-1, 1):
            i = li + (0 if side < 0 else 4)
            part = 1 + i
            mz = lambda p3: (p3[0], p3[1], p3[2] * side)
            hip, knee, ankle = mz(hip1), mz(knee1), mz(ankle1)
            joints["hips"][i] = hip
            joints["knees"][i] = knee
            joints["ankles"][i] = ankle
            joints["bends"][i] = (0.0, side)
            hv, kv, av = Vector(hip), Vector(knee), Vector(ankle)
            flat1 = Vector((kv.x - hv.x, 0.0, kv.z - hv.z)).normalized()
            flat2 = Vector((av.x - kv.x, 0.0, av.z - kv.z)).normalized()
            foot = av + flat2 * 1.25
            foot.y = 0.06
            reach = (foot - hv).length

            def leg_col(g, n, hv=hv, reach=reach):
                # banded legs: dark rings at the joints on a furry grey-brown leg
                t = (Vector((g.x, g.y, g.z)) - hv).length / max(0.01, reach)
                ring = min(abs(t - j) for j in (0.22, 0.42, 0.62, 0.82))
                c = SP_DARK if ring < 0.04 else SP_FUR
                m = _mottle(g)
                return (c[0] * m, c[1] * m, c[2] * m, 0.0)
            pc = with_part(leg_col, part)
            made = len(OBJS)
            cox = hv + flat1 * 1.0
            ell("coxa", tuple(hv + flat1 * 0.45), (0.55, 0.42, 0.5), 0, pc, 8)
            tube("femur", [tuple(hv), tuple(cox), tuple(cox.lerp(kv, 0.35)), tuple(cox.lerp(kv, 0.75)), tuple(kv)],
                [0.36, 0.38, 0.44, 0.4, 0.33], 0, pc, 8)
            for o in OBJS[made:]:
                o["seg"] = 1.0
            made = len(OBJS)
            ell("patella", tuple(kv), (0.4, 0.4, 0.4), 0, pc, 8)
            mid = kv.lerp(av, 0.5) + Vector((0.0, 0.45, 0.0)) + flat2 * 0.2          # (the tibia-metatarsus joint, a little proud)
            tube("shin", [tuple(kv), tuple(kv.lerp(mid, 0.5)), tuple(mid), tuple(mid.lerp(av, 0.55)), tuple(av)],
                [0.33, 0.3, 0.26, 0.2, 0.15], 0, pc, 7)
            for k in range(4):
                at = kv.lerp(mid, 0.3 + k * 0.22) if k < 3 else mid.lerp(av, 0.4)
                tube("spine", [tuple(at), tuple(at + Vector((0, 0.4, 0)) + flat2 * 0.18)], [0.045, 0.01], 0,
                    with_part(lambda g, n: (0.1, 0.08, 0.06, 0.0), part), 4, cap=False)
            for o in OBJS[made:]:
                o["seg"] = 2.0
            made = len(OBJS)
            tube("tarsus", [tuple(av), tuple(av.lerp(foot, 0.5)), tuple(foot)], [0.15, 0.12, 0.07], 0, pc, 6)
            for cs in (-1, 1):
                tube("claw", [tuple(foot), tuple(foot + flat2 * 0.25 + Vector((0.0, -0.04, 0.08 * cs)))], [0.04, 0.008], 0,
                    with_part(lambda g, n: (0.08, 0.06, 0.05, 0.0), part), 4, cap=False)
            for o in OBJS[made:]:
                o["seg"] = 3.0
    return joints
