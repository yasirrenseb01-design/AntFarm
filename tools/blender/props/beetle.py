# Part of tools/blender/build_props.py (loaded by it inside Blender, sharing its helpers: blobs, tube,
# ell, sheet, const, lerp, G/GV, OBJS, export).
# =============================================================== ground beetle (Carabidae)
# Facing +x, ~17 units long without the mandibles (25 mm), feet at y = 0. Alpha = part / 16 for
# shaders/creatures/beetle.gdshader: 0 body, 1 head, 2/3 left/right antenna, 4-9 legs
# (front-left, front-right, mid-left, mid-right, hind-left, hind-right), 10 mandibles.
# Hip pivots there: x = 3.6 / 1.2 / -0.6, y = 2.0, z = 1.3 * side; antenna bases (7.95, 3.0, 1.0 * side);
# mandible bases (8.2, 2.45, 0.6 * side).
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
BE_HIPS = [3.6, 1.2, -0.6]
BE_HIP_Y = 2.0

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
        if abs(g.z) > w - 0.3 and -0.3 < n.y < 0.55:
            c = BE_VIOLET                                 # the violet side margin
        elif abs(g.z) < 0.06 and n.y > 0.5:
            c = BE_GROOVE                                 # the suture
        elif n.y > 0.3 and abs(math.sin(g.z * 7.0)) < 0.1 and int((x + 20.0) * 2.6) % 2 == 0:
            c = BE_GROOVE                                 # rows of fine granules
    elif BE_PR[0] - 0.3 < x < BE_PR[1] + 0.1:
        if abs(g.z) > _be_pr_w(min(max(x, BE_PR[0]), BE_PR[1])) - 0.45:
            c = BE_VIOLET                                 # the raised violet side borders
        elif abs(g.z) < 0.05 and n.y > 0.6:
            c = BE_GROOVE                                 # the fine midline
    return (c[0], c[1], c[2], 0.0)


def loft(name, x0, x1, wfn, ybfn, ytfn, colfn, e=0.8, steps=40, segs=28, voxel=0.06, smooth=4, faces=2000):
    """A closed body lofted along x: at each x a rounded section, half width wfn(x), from ybfn(x) to ytfn(x)
    (e < 1 squarer, flatter on top). Remeshed and smoothed like blobs()."""
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
            z = w * math.copysign(abs(ca) ** e, ca)
            h = (yt - mid) if sa > 0 else (mid - yb)
            y = mid + h * math.copysign(abs(sa) ** e, sa)
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
    loft("elytra", BE_EL[0], BE_EL[1], _be_el_w, _be_el_bot, _be_el_top, beetle_body_col, 0.92, 44, 40, 0.09, 6, 3200)
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
        ell("eye", (7.2, 3.0, 1.22 * side), (0.42, 0.4, 0.33), 0, const((0.03, 0.03, 0.035, 1 / 16.0)), 12)
        # sickle-shaped mandibles curving in, their tips crossing in front of the head
        tube("mandible", [(8.2, 2.45, 0.6 * side), (8.95, 2.42, 0.78 * side), (9.65, 2.38, 0.5 * side), (9.95, 2.35, -0.12 * side)],
            [0.34, 0.26, 0.15, 0.04], 0, const((0.04, 0.03, 0.03, 10 / 16.0)), 7)
        # maxillary palps: four segments down and forward, the last broadened
        tube("palp", [(8.1, 2.15, 0.5 * side), (8.6, 1.75, 0.8 * side), (9.05, 1.35, 0.92 * side), (9.35, 1.05, 0.9 * side)],
            [0.1, 0.08, 0.075, 0.07], 0, const((0.06, 0.05, 0.05, 1 / 16.0)), 5)
        ell("palp_tip", (9.5, 0.92, 0.88 * side), (0.24, 0.1, 0.13), 0, const((0.06, 0.05, 0.05, 1 / 16.0)), 6)
        # 11-segmented antennae: a stout scape, a short pedicel, then nine beaded segments, held forward and out
        part = 2 if side < 0 else 3
        lens = [1.0, 0.4] + [0.82] * 9
        p = Vector((7.95, 3.0, 1.0 * side))
        d = Vector((0.72, 0.22, 0.62 * side)).normalized()
        turn = Vector((0.55, -0.12, 0.82 * side)).normalized()
        for k in range(11):
            dk = d.lerp(turn, k / 10.0).normalized()
            q = p + dk * lens[k]
            r = 0.17 if k == 0 else (0.11 if k == 1 else 0.115 - 0.003 * k)
            a, b = tuple(p), tuple(q)
            tube("antenna", [a, lerp(a, b, 0.5), b], [r * 0.75, r, r * 0.8], 0, const((0.05, 0.05, 0.06, part / 16.0)), 6, cap=False)
            p = q
    # six long running legs: femur up and out to a high knee, tibia down to the ground with two apical spurs,
    # a five-segmented tarsus along the ground ending in a pair of claws
    legs = [((5.0, 2.9, 3.3), (7.0, 0.3, 4.3), (8.9, 0.0, 5.0)),
        ((1.0, 3.0, 4.3), (-0.6, 0.3, 6.6), (-2.6, 0.0, 8.2)),
        ((-2.6, 3.0, 4.3), (-5.6, 0.3, 6.0), (-9.0, 0.0, 7.2))]
    for li in range(3):
        for side in (-1, 1):
            part = 4 + li * 2 + (0 if side < 0 else 1)
            pc = lambda g, n, p=part: (BE_LEG[0], BE_LEG[1], BE_LEG[2], p / 16.0)
            hip = (BE_HIPS[li], BE_HIP_Y, 1.3 * side)
            kd, ad, fd = legs[li]
            knee = (kd[0], kd[1], kd[2] * side)
            ankle = (ad[0], ad[1], ad[2] * side)
            foot = (fd[0], fd[1], fd[2] * side)
            ell("coxa", lerp(hip, knee, 0.08), (0.45, 0.38, 0.38), 0, pc, 8)
            tube("femur", [hip, lerp(hip, knee, 0.2), lerp(hip, knee, 0.6), knee], [0.3, 0.38, 0.34, 0.24], 0, pc, 8)
            tube("tibia", [knee, lerp(knee, ankle, 0.5), ankle], [0.2, 0.2, 0.24], 0, pc, 7)
            for sp in (-0.18, 0.18):
                tube("spur", [ankle, (ankle[0] + sp - 0.15, ankle[1] - 0.15, ankle[2] + 0.3 * side)], [0.06, 0.01], 0, pc, 4, cap=False)
            prev = ankle
            for k in range(5):
                q = lerp(ankle, foot, [0.27, 0.47, 0.64, 0.78, 1.0][k])
                q = (q[0], q[1] + 0.04, q[2])
                tube("tarsus", [prev, lerp(prev, q, 0.5), q], [0.11, 0.13 - 0.008 * k, 0.1 - 0.008 * k], 0, pc, 6, cap=False)
                prev = q
            fwd = Vector(foot) - Vector(ankle)
            fwd.normalize()
            for cs in (-1, 1):
                tip = Vector(foot) + fwd * 0.35 + Vector((0.0, -0.05, 0.12 * cs))
                tube("claw", [foot, tuple(tip)], [0.05, 0.01], 0, pc, 4, cap=False)
