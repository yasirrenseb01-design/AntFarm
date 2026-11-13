# Part of tools/blender/build_props.py (loaded by it inside Blender, sharing its helpers: blobs, tube,
# ell, sheet, const, lerp, G/GV, OBJS, export).
# =============================================================== wolf spider (Lycosidae)
# Facing +x, feet at y = 0, body length ~11 units before the game scales it by 0.85 (~14 mm).
# Legs (v0.12.34): jointed like the ground beetle's (beetle.py: loft, be_knee) - the 11th number of each vertex is its
# leg piece (1 coxa + femur, 2 patella to metatarsus, 3 tarsus; "ANT2") and the joints at rest go to wolf_spider.json,
# which the game hands to shaders/creatures/leg_ik.gdshaderinc. Vertex alpha = part / 16: 0 body, 1-4 left legs front to
# back, 5-8 right legs (the json's legs in that order), 9/10 left/right pedipalps, 11/12 left/right chelicerae (v0.13.4:
# they move - holding prey, chewing). The 11th number 9 on the eyes: glossy (spider.gdshader).
# The face (v0.13.4, the keeper's close-up photos of a wolf spider): the two big posterior median eyes looking forward
# over a straight row of four small anterior eyes, the posterior laterals on top behind; under them the chelicerae, big
# and furry, banded, side by side to the ground, a red-brown boss at the top of each; the pedipalps thick and furry,
# reaching forward beside them.
SP_PALP_BASE = (3.85, 1.75, 0.72)    # the pedipalp's base, one side (spider.gdshader: PALP_BASE)
SP_CHEL_TOP = (4.3, 2.35, 0.36)      # the chelicera's top, one side (spider.gdshader: CHEL_TOP)

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
    # (v0.13.11, the keeper: "the middle of the body looks odd" - its back end was cut off square, ~2 wide and 1.4 high,
    # over a ball of a waist: now it rounds in to the narrow pedicel, as a lycosid's does)
    thorax = 1.85 * max(0.0, math.sin(math.pi * min(1.0, (u + 0.015) / 0.915))) ** 0.6
    thorax *= 0.3 + 0.7 * math.sqrt(max(0.0, 1.0 - max(0.0, (0.3 - u) / 0.3) ** 2))     # (its back rounded, seen from above)
    head = 1.2 * math.sqrt(max(0.0, 1.0 - max(0.0, (u - 0.8) / 0.2) ** 2.2))
    return max(thorax, head)


def _sp_car_top(x):
    # highest at the head (the eyes look over the grass), a shallow saddle behind it, sloping down to the waist
    u = min(1.0, max(0.0, x / 4.3))
    back = 0.3 + 0.7 * min(1.0, u / 0.2) ** 0.5           # (sloping down to the waist at its back edge: v0.13.11)
    return 1.25 + back * (0.95 + 1.15 * math.sin(math.pi * (0.1 + 0.8 * u)) ** 0.7 + 0.3 * math.exp(-((u - 0.78) / 0.14) ** 2) - 0.12 * math.exp(-((u - 0.45) / 0.1) ** 2))


def _sp_ab_w(x):
    # the abdomen from above: an egg, broadest behind its middle (x: -6.6 spinnerets .. -0.4 waist)
    u = min(1.0, max(0.0, (x + 6.6) / 6.2))
    return 2.15 * math.sin(math.pi * u ** 0.85) ** 0.62


def hairs(name, spots, colfn):
    """Fine hairs, one mesh: each a thin three-sided cone from root to tip. spots: (root, direction, length, radius)."""
    bm = bmesh.new()
    for root, d, ln, r in spots:
        d = Vector(d).normalized()
        a = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        n1 = d.cross(a).normalized()
        n2 = d.cross(n1)
        base = [bm.verts.new(G(*(Vector(root) + (n1 * math.cos(k * math.tau / 3) + n2 * math.sin(k * math.tau / 3)) * r)))
                for k in range(3)]
        tip = bm.verts.new(G(*(Vector(root) + d * ln)))
        for k in range(3):
            bm.faces.new((base[k], base[(k + 1) % 3], tip))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return _obj(name, me, 0, colfn)


def _hair_col(g, n):
    # light and dark hairs mixed, the light ones grey-buff (wolf spiders' pile: photographs)
    k = 0.5 + 0.5 * math.sin(g.x * 41.0 + g.y * 29.0 + g.z * 37.0)
    c = SP_PALE if k > 0.8 else (SP_FUR if k > 0.3 else SP_DARK)
    c = (c[0] * 1.1, c[1] * 1.1, c[2] * 1.1)
    return (c[0], c[1], c[2], 0.0)


def _loft_surface(x, a, wfn, ybfn, ytfn, e, eb=None, wb=1.0):
    """A point on loft()'s surface (beetle.py) at x, angle a round the section, and its outward normal (numerically)."""
    def pt(x, a):
        w = max(0.02, wfn(x))
        yb, yt = ybfn(x), ytfn(x)
        mid = yb + (yt - yb) * 0.3
        ca, sa = math.cos(a), math.sin(a)
        under = sa < -1e-9
        ee = eb if (under and eb is not None) else e
        z = w * (wb if under else 1.0) * math.copysign(abs(ca) ** ee, ca)
        h = (yt - mid) if sa > 0 else (mid - yb)
        return Vector((x, mid + h * math.copysign(abs(sa) ** ee, sa), z))
    p = pt(x, a)
    nn = (pt(x + 0.01, a) - pt(x - 0.01, a)).cross(pt(x, a + 0.01) - pt(x, a - 0.01))
    if nn.dot(p - Vector((x, p.y - math.sin(a), 0.0))) < 0:
        nn = -nn
    return p, nn.normalized()


def _body_hairs(rnd, x0, x1, n, wfn, ybfn, ytfn, e, eb, wb, ln):
    spots = []
    for _ in range(n):
        x = rnd.uniform(x0, x1)
        a = rnd.uniform(-0.25, math.pi + 0.25)          # the back and sides (the belly is on the ground)
        p, nn = _loft_surface(x, a, wfn, ybfn, ytfn, e, eb, wb)
        # laid back toward the rear, lifted off the surface a little
        d = (nn * 0.55 + Vector((-1.0, 0.0, 0.0)) * 0.8 + Vector((rnd.uniform(-0.2, 0.2), 0, rnd.uniform(-0.3, 0.3)))).normalized()
        spots.append((p - nn * 0.04, d, ln * rnd.uniform(0.6, 1.2), 0.03))
    return spots


def _leg_hairs(rnd, pts, radii, n):
    """Hairs on a leg piece along the polyline pts (radii at them), slanted toward the leg's tip."""
    spots = []
    for _ in range(n):
        t = rnd.uniform(0.05, 0.95) * (len(pts) - 1)
        k = min(int(t), len(pts) - 2)
        f = t - k
        a, b = Vector(pts[k]), Vector(pts[k + 1])
        axis = (b - a).normalized()
        c = a.lerp(b, f)
        r = radii[k] + (radii[k + 1] - radii[k]) * f
        side = Vector((0, 1, 0)) if abs(axis.y) < 0.9 else Vector((1, 0, 0))
        n1 = axis.cross(side).normalized()
        n2 = axis.cross(n1)
        ang = rnd.uniform(0.0, math.tau)
        out = n1 * math.cos(ang) + n2 * math.sin(ang)
        spots.append((c + out * r * 0.85, (out * 0.6 + axis * 0.8).normalized(), rnd.uniform(0.16, 0.3), 0.025))
    return spots


def wolf_spider():
    flat = Matrix.Identity(4)
    # the abdomen: an egg on a narrow waist, a little flattened under, highest behind its middle
    loft("abdomen", -6.6, -0.4, _sp_ab_w, lambda x: 1.0 + 0.5 * max(0.0, (-4.9 - x) / 1.7) ** 2,
        lambda x: 1.0 + 3.0 * math.sin(math.pi * min(1.0, max(0.0, (x + 6.6) / 6.2)) ** 0.9) ** 0.55, abdomen_col, 0.95, 40, 32, 0.08, 5, 1800,
        eb=0.7, wb=0.92)
    blobs("waist", [((-0.2, 1.65, 0), (0.42, 0.3, 0.3), flat)], 0, const(SP_DARK), 0.05, 3, 160)     # (the pedicel: v0.13.11)
    # the carapace: pear-shaped, the head high in front, the sides coming down over the legs' bases; under it the sternum
    loft("carapace", 0.0, 4.3, _sp_car_w, lambda x: 1.25, _sp_car_top, carapace_col, 0.8, 34, 32, 0.06, 4, 1700, eb=0.5, wb=0.7)
    ell("sternum", (1.9, 1.15, 0), (1.7, 0.3, 1.1), 0, const(SP_DARK), 10)
    # eyes: a straight row of four small ones low on the face, the two big posterior medians above them looking
    # forward, the two posterior laterals on top behind - glossy black (the 11th number 9)
    made = len(OBJS)
    for side in (-1, 1):
        # (set into the carapace, only their fronts showing: v0.13.6 - the keeper, "the eyes bulge out")
        for z in (0.13, 0.4):
            ell("eye", (4.18, 2.52, z * side), (0.11, 0.12, 0.12), 0, const((0.02, 0.02, 0.025)), 10)
        ell("eye", (3.9, 3.0, 0.36 * side), (0.3, 0.32, 0.3), 0, const((0.015, 0.015, 0.02)), 16)
        ell("eye", (3.38, 3.36, 0.74 * side), (0.21, 0.21, 0.21), 0, const((0.015, 0.015, 0.02)), 12)
    for o in OBJS[made:]:
        o["seg"] = 9.0
    tube("spinnerets", [(-6.5, 1.75, 0), (-6.95, 1.6, 0)], [0.3, 0.15], 0, const(SP_DARK), 6)
    # fur (v0.13.11, the keeper: "make the spider look a little hairy"): a pile of fine hairs laid back over the abdomen
    # and the carapace, light and dark mixed [photographs of Lycosidae; the counts and lengths: inference, for the look]
    rnd = random.Random(7)
    hairs("abdomen_hair", _body_hairs(rnd, -6.3, -0.8, 1100, _sp_ab_w, lambda x: 1.0 + 0.5 * max(0.0, (-4.9 - x) / 1.7) ** 2,
        lambda x: 1.0 + 3.0 * math.sin(math.pi * min(1.0, max(0.0, (x + 6.6) / 6.2)) ** 0.9) ** 0.55, 0.95, 0.7, 0.92, 0.28), _hair_col)
    hairs("carapace_hair", _body_hairs(rnd, 0.3, 3.4, 450, _sp_car_w, lambda x: 1.25, _sp_car_top, 0.8, 0.5, 0.7, 0.22), _hair_col)
    for o in OBJS:
        COLFNS[o["colfn"]] = with_part(COLFNS[o["colfn"]], 0)          # every body piece is part 0
    for side in (-1, 1):
        si = 0 if side < 0 else 1
        # the chelicerae: big, furry, banded light and dark down their length, side by side to the ground; a red-brown
        # boss at the outer top, the fang folded under at the bottom (part 11 / 12: they open and chew)
        def chel_col(g, n, part=11 + si):
            band = 0.5 + 0.5 * math.sin(g.y * 9.0 + math.sin(g.z * 21.0) * 0.6)
            c = SP_DARK if band < 0.42 else SP_FUR
            m = _mottle(g)
            return (c[0] * m, c[1] * m, c[2] * m, part / 16.0)
        ct = SP_CHEL_TOP
        blobs("chelicera", [((ct[0] + 0.1, ct[1] - 0.8, ct[2] * side), (0.5, 0.95, 0.4), Matrix.Rotation(0.14, 4, "Z"))],
            0, chel_col, 0.05, 3, 700)
        ell("boss", (ct[0] + 0.26, ct[1] - 0.08, (ct[2] + 0.28) * side), (0.12, 0.07, 0.13), 0,
            const((0.3, 0.09, 0.05), (11 + si) / 16.0), 8)
        tube("fang", [(ct[0] + 0.3, ct[1] - 1.55, ct[2] * side), (ct[0] + 0.42, ct[1] - 1.72, ct[2] * side * 0.5),
                      (ct[0] + 0.35, ct[1] - 1.8, ct[2] * side * 0.15)], [0.07, 0.05, 0.015], 0,
            const((0.22, 0.06, 0.03), (11 + si) / 16.0), 5, cap=False)
        # the pedipalps: thick, furry, reaching forward and down beside the chelicerae (part 9 / 10: they hold prey)
        pb = SP_PALP_BASE
        tube("palp", [(pb[0], pb[1], pb[2] * side), (4.75, 1.95, 1.05 * side), (5.35, 1.35, 1.0 * side), (5.55, 0.65, 0.86 * side),
                      (5.5, 0.3, 0.75 * side)], [0.27, 0.27, 0.25, 0.21, 0.16], 0,
            lambda g, n, part=9 + si: (SP_FUR[0] * _mottle(g), SP_FUR[1] * _mottle(g), SP_FUR[2] * _mottle(g), part / 16.0), 8)
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
            hairs("femur_hair", _leg_hairs(rnd, [hv, cox, kv], [0.36, 0.42, 0.33], 40), with_part(_hair_col, part))
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
            hairs("shin_hair", _leg_hairs(rnd, [kv, mid, av], [0.33, 0.26, 0.15], 50), with_part(_hair_col, part))
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
