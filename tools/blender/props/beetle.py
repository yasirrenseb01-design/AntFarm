# Part of tools/blender/build_props.py (loaded by it inside Blender, sharing its helpers: blobs, tube,
# ell, sheet, const, lerp, G/GV, OBJS, export).
# =============================================================== ground beetle (Carabidae)
# Facing +x, ~17 units long without the mandibles (25 mm), feet at y = 0. Alpha = part / 16 for
# shaders/creatures/beetle.gdshader: 0 body, 1 head, 2/3 left/right antenna, 4-9 legs
# (front-left, front-right, mid-left, mid-right, hind-left, hind-right), 10 mandibles.
# Legs (v0.12.33): jointed - the 11th number of each vertex is its leg segment (1 coxa + femur, 2 tibia, 3 tarsus; "ANT2"),
# and the joints at rest (hip, knee, ankle of each leg, parts 4-9 in order) are written to ground_beetle.json beside the
# model: the game hands them to the shader, which bends each leg at its knee (nothing about the legs is written twice).
# The body is built as before and then raised BE_UP: the belly flat and clear of the ground, the hips under the thorax.
# Antenna bases there (7.7, 2.95 + BE_UP, 0.72 * side); mandible bases (8.2, 2.45 + BE_UP, 0.6 * side).
#
# Shape after Carabus violaceus / C. problematicus, the black ground beetles with violet margins of
# European gardens (docs/BIOLOGY.md "ด้วงดิน", reference/ด้วงดิน.jpg):
#  - 20-30 mm long; pronotum broader than long, heart-shaped, sides narrowing to the base, the hind angles
#    drawn back into lobes, side borders raised; violet along the sides of pronotum and elytra
#  - elytra a long oval, broadest behind the middle, nearly smooth with rows of fine granules
#  - a narrow waist between pronotum and elytra; head narrower than the pronotum, eyes standing out,
#    sickle mandibles, the last palp segment broadened; 11-segmented antennae to about the pronotum's base
#  - long running legs held well clear of the ground, the hind leg about three quarters of the body
#  Proportions: pronotum width/length 1.46, elytra length/width 1.55, elytra/pronotum width 1.46 (a Carabus
#  in a Slovenian key) - the rest (heights, leg segments, how the legs stand) taken from photographs.

BE_BLACK = (0.07, 0.07, 0.09)
BE_VIOLET = (0.2, 0.15, 0.4)
BE_GROOVE = (0.04, 0.04, 0.05)
BE_LEG = (0.05, 0.05, 0.06)
BE_UP = 0.65                # the body raised this much once it is built (the legs come out from under it)
BE_STRIDE = 3.0             # how far a foot is carried in a step (the game's: outworld_view "stride")
# each leg pair: hip, the foot's ankle at mid-stance, the femur's length along the ground and the knee's height, the tibia's
# length, which way the knee is bent out (+x forward, or out to the side for the hind legs) - one side (z > 0), mirrored
BE_LEGS = [
    {"hip": (4.2, 2.3, 0.95), "ankle": (6.8, 0.35, 4.35), "femur": 3.0, "knee_y": 2.45, "tibia": 3.4, "bend": (0.0, 1.0)},
    {"hip": (1.6, 2.1, 0.95), "ankle": (1.0, 0.35, 6.55), "femur": 3.6, "knee_y": 2.25, "tibia": 3.9, "bend": (1.0, 0.0)},
    {"hip": (0.0, 2.05, 0.95), "ankle": (-3.4, 0.35, 5.95), "femur": 4.0, "knee_y": 2.2, "tibia": 4.6, "bend": (0.0, 1.0)},
]


def up_knee(hip, ankle, l1, l2):
    """The knee bent upward in the upright plane through hip and ankle (leg_ik.gdshaderinc, knee_up 1)."""
    h, a = Vector(hip), Vector(ankle)
    d = a - h
    dist = d.length
    d.normalize()
    al = (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
    up = math.sqrt(max(0.0, l1 * l1 - al * al))
    nn = (Vector((0.0, 1.0, 0.0)) - d * d.y).normalized()
    return tuple(h + d * al + nn * up)


def be_knee(hip, ankle, femur, knee_y, tibia, bend):
    """The knee for an ankle there: the femur swings level round the hip (its end at knee_y), the tibia reaches down to
    the ankle - two circles on the ground plan. The same sums as shaders/creatures/leg_ik.gdshaderinc."""
    r2 = math.sqrt(max(0.01, tibia * tibia - (knee_y - ankle[1]) ** 2))
    ux, uz = ankle[0] - hip[0], ankle[2] - hip[2]
    rho = math.hypot(ux, uz)
    ux, uz = ux / rho, uz / rho
    rho = min(max(rho, abs(femur - r2) + 0.01), femur + r2 - 0.01)
    a = (femur * femur - r2 * r2 + rho * rho) / (2.0 * rho)
    h = math.sqrt(max(0.0, femur * femur - a * a))
    nx, nz = uz, -ux
    if nx * bend[0] + nz * bend[1] < 0.0:
        nx, nz = -nx, -nz
    return (hip[0] + ux * a + nx * h, knee_y, hip[2] + uz * a + nz * h)

# elytra and pronotum outlines (half widths), shared by the shapes and their colouring
BE_EL = (-8.1, 2.1)        # elytra from the tip to the shoulders
BE_PR = (2.35, 5.85)       # pronotum from the base to the front edge


def _be_el_w(x):
    u = (x - BE_EL[0]) / (BE_EL[1] - BE_EL[0])          # 0 at the tip, 1 at the shoulders
    if u >= 0.42:
        t = (u - 0.42) / 0.58
        w = 3.35 * math.sqrt(max(0.0, 1.0 - 0.8 * t ** 2.4))
    else:
        t = (0.42 - u) / 0.42
        w = 3.35 * max(0.0, 1.0 - t ** 2.1) ** 0.5
    return w * min(1.0, (1.0 - u) / 0.035) ** 0.5 if u > 0.965 else w


def _be_pr_w(x):
    u = (x - BE_PR[0]) / (BE_PR[1] - BE_PR[0])          # 0 at the base, 1 at the front
    return 1.75 + 0.75 * math.sin(math.pi * min(1.0, max(0.0, u)) ** 0.85) + 0.15 * (1.0 - u)


def beetle_body_col(g, n):
    c = BE_BLACK
    x = g.x
    if x < BE_EL[1] + 0.1:
        w = _be_el_w(min(max(x, BE_EL[0]), BE_EL[1]))
        if abs(g.z) > w - 0.14 and 3.12 < g.y < 3.5 and n.y > -0.35:
            c = BE_VIOLET                                 # the violet side margin: a narrow line along the elytra's edge
                                                          # (v0.12.33: the whole side wall before - the beetle read violet)
        elif abs(g.z) < 0.06 and n.y > 0.5:
            c = BE_GROOVE                                 # the suture
        elif n.y > 0.3 and abs(math.sin(g.z * 7.0)) < 0.1 and int((x + 20.0) * 2.6) % 2 == 0:
            c = BE_GROOVE                                 # rows of fine granules
    elif BE_PR[0] - 0.3 < x < BE_PR[1] + 0.1:
        if abs(g.z) > _be_pr_w(min(max(x, BE_PR[0]), BE_PR[1])) - 0.22 and n.y > 0.25:
            c = BE_VIOLET                                 # the raised violet side borders
        elif abs(g.z) < 0.05 and n.y > 0.6:
            c = BE_GROOVE                                 # the fine midline
    return (c[0], c[1], c[2], 0.0)


def loft(name, x0, x1, wfn, ybfn, ytfn, colfn, e=0.8, steps=40, segs=28, voxel=0.06, smooth=4, faces=2000, eb=None, wb=1.0):
    """A closed body lofted along x: at each x a rounded section, half width wfn(x), from ybfn(x) to ytfn(x)
    (e < 1 squarer, flatter on top; eb, wb: the underside's own squareness and its width as a share of the top's - a
    flat belly set in under the side margin). Remeshed and smoothed like blobs()."""
    bm = bmesh.new()
    rings = []
    for i in range(steps + 1):
        x = x0 + (x1 - x0) * i / steps
        w = max(0.02, wfn(x))
        yb, yt = ybfn(x), ytfn(x)
        mid = yb + (yt - yb) * 0.3
        ring = []
        for k in range(segs):
            a = math.tau * k / segs
            ca, sa = math.cos(a), math.sin(a)
            under = sa < -1e-9
            ee = eb if (under and eb is not None) else e
            z = w * (wb if under else 1.0) * math.copysign(abs(ca) ** ee, ca)
            h = (yt - mid) if sa > 0 else (mid - yb)
            y = mid + h * math.copysign(abs(sa) ** ee, sa)
            ring.append(bm.verts.new(G(x, y, z)))
        rings.append(ring)
    for i in range(steps):
        for k in range(segs):
            k2 = (k + 1) % segs
            bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = _obj(name, me, 0, colfn)
    rm = o.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = voxel
    sm = o.modifiers.new("smooth", "SMOOTH")
    sm.factor = 0.5
    sm.iterations = smooth
    _bake(o)
    n = len(o.data.polygons)
    if n > faces:
        d = o.modifiers.new("dec", "DECIMATE")
        d.ratio = faces / n
        _bake(o)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def _be_el_top(x):
    u = (x - BE_EL[0]) / (BE_EL[1] - BE_EL[0])
    return 2.0 + 2.7 * math.sin(math.pi * (0.04 + 0.9 * u) ** 0.85) ** 0.55 - 0.3 * u   # highest behind the middle


def _be_el_bot(x):
    u = (x - BE_EL[0]) / (BE_EL[1] - BE_EL[0])
    return 1.75 + 0.5 * max(0.0, (0.3 - u) / 0.3) ** 2                  # the belly curving up to the tip


def ground_beetle():
    flat = Matrix.Identity(4)
    head_col = lambda g, n: (BE_BLACK[0], BE_BLACK[1], BE_BLACK[2], 1 / 16.0)
    # elytra: the wing cases over the abdomen, a convex oval coming down the sides to the belly
    loft("elytra", BE_EL[0], BE_EL[1], _be_el_w, _be_el_bot, _be_el_top, beetle_body_col, 0.92, 44, 40, 0.09, 6, 3200, eb=0.45, wb=0.84)
    # the narrow waist (mesothorax) between pronotum and elytra
    blobs("waist", [((2.3, 3.0, 0), (0.6, 0.62, 1.05), flat)], 0, const(BE_BLACK), 0.05, 3, 300)
    # pronotum: flat-topped heart shape, its hind angles drawn back as lobes either side of the waist
    loft("pronotum", BE_PR[0], BE_PR[1], _be_pr_w, lambda x: 2.35,
        lambda x: 3.55 + 0.45 * math.sin(math.pi * (x - BE_PR[0]) / (BE_PR[1] - BE_PR[0])), beetle_body_col, 0.55, 30, 32,
        0.05, 3, 1400)
    for side in (-1, 1):
        ell("hind_angle", (2.35, 3.2, 1.62 * side), (0.42, 0.14, 0.26), 0, const(BE_VIOLET + (0.0,)), 8)
    # underside: thorax between the leg bases
    blobs("thorax_under", [((1.4, 2.0, 0), (2.8, 0.5, 1.25), flat), ((3.9, 2.2, 0), (1.5, 0.45, 1.0), flat)], 0,
        const(BE_BLACK), 0.07, 3, 400)
    # head: a short neck, then the capsule narrowing to the clypeus; it slopes down to the front
    loft("head", 5.6, 8.45, lambda x: 1.0 + 0.32 * math.sin(math.pi * min(1.0, (x - 5.6) / 2.4)) - 0.25 * max(0.0, (x - 7.6) / 0.85),
        lambda x: 2.25, lambda x: 3.35 - 0.45 * max(0.0, (x - 6.6) / 1.85), head_col, 0.8, 24, 24, 0.05, 3, 900)
    ell("labrum", (8.45, 2.55, 0), (0.25, 0.18, 0.55), 0, head_col, 10)
    for side in (-1, 1):
        # the compound eyes: bulging at the sides, glossy (the 11th number 9: beetle.gdshader - v0.13.5)
        eye = ell("eye", (7.25, 3.02, 1.24 * side), (0.44, 0.42, 0.36), 0, const((0.03, 0.03, 0.035, 1 / 16.0)), 14)
        eye["seg"] = 9.0
        # sickle-shaped mandibles curving in, their tips crossing in front of the head: stout, with a tooth on the
        # inner edge and a dark red-brown sheen toward the tip (v0.13.5: bigger, after Carabus photographs)
        tube("mandible", [(8.15, 2.45, 0.62 * side), (8.95, 2.43, 0.84 * side), (9.75, 2.39, 0.55 * side), (10.1, 2.36, -0.14 * side)],
            [0.4, 0.31, 0.18, 0.04], 0, lambda g, n: ((0.16, 0.06, 0.04, 10 / 16.0) if g.x > 9.4 else (0.04, 0.03, 0.03, 10 / 16.0)), 8)
        ell("tooth", (9.2, 2.42, 0.6 * side), (0.14, 0.09, 0.12), 0, const((0.05, 0.03, 0.03, 10 / 16.0)), 6)
        # a shallow groove and two pits on the clypeus, and the frons' furrows beside the eyes
        ell("fovea", (8.05, 3.02, 0.42 * side), (0.18, 0.06, 0.1), 0, const((0.02, 0.02, 0.025, 1 / 16.0)), 6)
        # maxillary palps: four segments down and forward, the last broadened
        tube("palp", [(8.1, 2.15, 0.5 * side), (8.6, 1.75, 0.8 * side), (9.05, 1.35, 0.92 * side), (9.35, 1.05, 0.9 * side)],
            [0.1, 0.08, 0.075, 0.07], 0, const((0.06, 0.05, 0.05, 1 / 16.0)), 5)
        ell("palp_tip", (9.5, 0.92, 0.88 * side), (0.24, 0.1, 0.13), 0, const((0.06, 0.05, 0.05, 1 / 16.0)), 6)
        # 11-segmented antennae: a stout scape, a short pedicel, then nine beaded segments, held forward and out
        part = 2 if side < 0 else 3
        lens = [1.0, 0.4] + [0.82] * 9
        # (from inside the head's side, in front of the eye: at its surface before, the smoothed head came out smaller
        # and the antennae stood off it - the keeper, 2026-11-03, "the beetle's antennae float")
        p = Vector((7.7, 2.95, 0.72 * side))
        d = Vector((0.72, 0.22, 0.62 * side)).normalized()
        turn = Vector((0.55, -0.12, 0.82 * side)).normalized()
        for k in range(11):
            dk = d.lerp(turn, k / 10.0).normalized()
            q = p + dk * lens[k]
            r = 0.19 if k == 0 else (0.11 if k == 1 else 0.115 - 0.003 * k)
            a, b = tuple(p), tuple(q)
            tube("antenna", [a, lerp(a, b, 0.5), b], [r * 0.75, r, r * 0.8], 0, const((0.05, 0.05, 0.06, part / 16.0)), 6, cap=False)
            p = q
    # the body as built so far stands BE_UP higher: its belly clear of the ground, the legs coming out from under it
    for o in OBJS:
        o.data.transform(Matrix.Translation((0.0, 0.0, BE_UP)))
    # the underside between the hips, and the abdomen's plates showing as shallow steps under the elytra
    blobs("sternum", [((2.2, 2.55, 0), (2.6, 0.42, 1.15), flat), ((4.3, 2.75, 0), (1.3, 0.4, 0.95), flat)], 0,
        const(BE_BLACK), 0.07, 3, 400)
    for k in range(5):
        x = -1.6 - 1.25 * k
        ell("sternite", (x, 2.42 + 0.06 * k, 0), (0.72, 0.16, 0.84 * _be_el_w(x) * 0.9), 0, const(BE_BLACK), 10)
    # six running legs, jointed (see the top of the file): coxa and trochanter at the hip, the femur a thick spindle held
    # about level under the elytra's margin to the knee beyond it, the tibia slender at the knee widening down to the ankle
    # with two rows of short spines and two spurs, a five-segmented tarsus along the ground ending in a pair of claws
    # (shaped as in photographs of Carabus - the keeper, 2026-11-03: "give the legs some shape")
    joints = {"hips": [], "knees": [], "ankles": [], "bends": [], "stride": BE_STRIDE}
    for li in range(3):
        L = BE_LEGS[li]
        for side in (-1, 1):
            part = 4 + li * 2 + (0 if side < 0 else 1)
            pc = lambda g, n, p=part: (BE_LEG[0], BE_LEG[1], BE_LEG[2], p / 16.0)
            mz = lambda p3: (p3[0], p3[1], p3[2] * side)
            hip1, ankle1 = L["hip"], L["ankle"]
            knee1 = be_knee(hip1, ankle1, L["femur"], L["knee_y"], L["tibia"], L["bend"])
            # (the reach at both ends of a step must be within the leg's: else the foot would be pulled off its place)
            for dx in (-0.5 * BE_STRIDE, 0.5 * BE_STRIDE):
                r2 = math.sqrt(L["tibia"] ** 2 - (L["knee_y"] - ankle1[1]) ** 2)
                rho = math.hypot(ankle1[0] + dx - hip1[0], ankle1[2] - hip1[2])
                assert abs(L["femur"] - r2) < rho < L["femur"] + r2, "leg %d cannot reach its step" % li
            hip, knee, ankle = mz(hip1), mz(knee1), mz(ankle1)
            joints["hips"].append(hip)
            joints["knees"].append(knee)
            joints["ankles"].append(ankle)
            joints["bends"].append((L["bend"][0], L["bend"][1] * side))
            kv, av = Vector(knee), Vector(ankle)
            flatdir = Vector((av.x - kv.x, 0.0, av.z - kv.z)).normalized()
            foot = (ankle[0] + flatdir.x * 1.7, 0.04, ankle[2] + flatdir.z * 1.7)
            made = len(OBJS)
            ell("coxa", lerp(hip, knee, 0.06), (0.58, 0.46, 0.5), 0, pc, 8)
            ell("trochanter", lerp(hip, knee, 0.2), (0.4, 0.3, 0.32), 0, pc, 8)
            tube("femur", [hip, lerp(hip, knee, 0.25), lerp(hip, knee, 0.55), lerp(hip, knee, 0.85), knee],
                [0.26, 0.4, 0.42, 0.34, 0.24], 0, pc, 10)
            for o in OBJS[made:]:
                o["seg"] = 1.0
            made = len(OBJS)
            tube("tibia", [knee, lerp(knee, ankle, 0.35), lerp(knee, ankle, 0.7), ankle], [0.2, 0.21, 0.25, 0.29], 0, pc, 8)
            axis = (av - kv).normalized()
            out = Vector((0.0, 0.0, side)).cross(axis).normalized()          # (across the leg, in its plane)
            for k in range(7):
                c = kv.lerp(av, 0.22 + 0.1 * k)
                for row in (-1, 1):
                    base = c + out * (0.2 * row) + Vector((0.0, -0.05, 0.0))
                    tip = base + (out * (0.26 * row) + axis * 0.2 + Vector((0.0, -0.08, 0.0)))
                    tube("spine", [tuple(base), tuple(tip)], [0.045, 0.006], 0, pc, 4, cap=False)
            for sp in (-0.18, 0.18):
                tube("spur", [ankle, (ankle[0] + sp - 0.15, ankle[1] - 0.15, ankle[2] + 0.3 * side)], [0.06, 0.01], 0, pc, 4, cap=False)
            for o in OBJS[made:]:
                o["seg"] = 2.0
            made = len(OBJS)
            prev = ankle
            for k in range(5):
                q = lerp(ankle, foot, [0.27, 0.47, 0.64, 0.78, 1.0][k])
                q = (q[0], q[1] + 0.04, q[2])
                r = 0.13 - 0.01 * k
                tube("tarsus", [prev, lerp(prev, q, 0.6), q], [r * 0.55, r * 0.8, r], 0, pc, 6, cap=False)
                seg = (Vector(q) - Vector(prev)).normalized()
                for cs in (-1, 1):
                    bt = Vector(q) + Vector((0.0, 0.0, 0.09 * cs)) + seg * 0.12 + Vector((0.0, -0.06, 0.06 * cs))
                    tube("bristle", [q, tuple(bt)], [0.025, 0.004], 0, pc, 3, cap=False)
                prev = q
            fwd = (Vector(foot) - av).normalized()
            for cs in (-1, 1):
                tip = Vector(foot) + fwd * 0.35 + Vector((0.0, -0.05, 0.12 * cs))
                tube("claw", [foot, tuple(tip)], [0.05, 0.01], 0, pc, 4, cap=False)
            for o in OBJS[made:]:
                o["seg"] = 3.0
    return joints
