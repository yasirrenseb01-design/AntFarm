# Part of tools/blender/build_props.py (loaded by it inside Blender, sharing its helpers: blobs, tube,
# ell, sheet, const, lerp, G/GV, OBJS, export).
# =============================================================== house fly (Musca domestica), dead
# Lying on its back, a little tipped to one side, legs curled in over the belly, wings spread on the
# ground. ~6.5 mm long (4.3 units), x forward. Built upright and then turned over (FLY_FLIP); the colour
# functions read the upright coordinates. Group 0 = body, legs, bristles and wing veins
# (assets/models/prey/fly.antmesh), group 1 = the wing membranes (fly_wings.antmesh, drawn see-through).

FLY_FLIP = math.radians(158.0)
FLY_LIFT = [0.0]
FLY_GREY = (0.36, 0.35, 0.33)
FLY_DARK = (0.09, 0.09, 0.09)


def _fly_up(g):
    """Final game coordinates -> the upright fly's coordinates."""
    y = g.y - FLY_LIFT[0]
    c, s = math.cos(-FLY_FLIP), math.sin(-FLY_FLIP)
    return Vector((g.x, y * c - g.z * s, y * s + g.z * c))


def _fly_upn(n):
    c, s = math.cos(-FLY_FLIP), math.sin(-FLY_FLIP)
    return Vector((n.x, n.y * c - n.z * s, n.y * s + n.z * c))


def upright(fn):
    return lambda g, n: fn(_fly_up(g), _fly_upn(n))


def fly_body_col(g, n):
    x, z = g.x, abs(g.z)
    if x > -0.15:                                   # thorax: grey dusting with four black stripes on top
        if n.y > 0.15 and (abs(z - 0.13) < 0.06 or abs(z - 0.4) < 0.07) and x > 0.0:
            c = (0.1, 0.1, 0.1)
        elif n.y < -0.3:
            c = (0.24, 0.23, 0.21)
        else:
            c = FLY_GREY
    else:                                           # abdomen: yellowish sides at the base, grey chequering
        c = (0.3, 0.29, 0.27)
        if z > 0.35 and x > -1.25 and n.y > -0.4:
            c = (0.42, 0.36, 0.25)
        if math.sin(x * 8.5) * math.sin(g.z * 8.0) > 0.35:
            c = (c[0] * 0.6, c[1] * 0.6, c[2] * 0.6)
        if z < 0.12 and n.y > 0.3:
            c = (0.12, 0.11, 0.1)                   # dark median stripe
        if abs(math.sin((x + 0.15) * 4.2)) < 0.12 and n.y > 0.0:
            c = (c[0] * 0.55, c[1] * 0.55, c[2] * 0.55)   # hind edges of the segments
        if n.y < -0.5:
            c = (0.34, 0.31, 0.25)                  # the belly: dull grey-yellow
    return (c[0], c[1], c[2], 0.0)


def fly_eye_col(g, n):
    # compound eye: brick red, a fine darker facet lattice
    f = math.sin(g.x * 40.0) * math.sin(g.y * 40.0) * math.sin(g.z * 40.0)
    k = 0.75 if f > 0.25 else 1.0
    return (0.58 * k, 0.15 * k, 0.09 * k, 0.0)


def fly_head_col(g, n):
    if g.x > 2.05 and abs(g.z) < 0.3:
        return (0.78, 0.74, 0.62, 0.0)              # silvery face between the eyes
    if abs(g.z) < 0.1 and n.y > 0.4:
        return (0.12, 0.1, 0.09, 0.0)               # dark frontal stripe
    return (0.4, 0.39, 0.36, 0.0)


def _wing_frame(side):
    base = Vector((0.45, 0.66, 0.32 * side))
    d = Vector((-0.78, 0.0, 0.62 * side)).normalized()
    up = Vector((0.0, 1.0, 0.0))
    w = d.cross(up) * side
    m = Matrix.Identity(4)
    for i in range(3):
        m[i][0], m[i][1], m[i][2], m[i][3] = d[i], up[i], w[i], base[i]
    return m


def fly():
    random.seed(7)
    flat = Matrix.Identity(4)
    blobs("fly_body", [((0.62, 0.2, 0), (0.95, 0.78, 0.78), flat), ((-0.3, 0.58, 0), (0.36, 0.2, 0.42), flat),
                       ((-0.95, 0.05, 0), (1.15, 0.7, 0.85), flat), ((-1.85, 0.0, 0), (0.42, 0.4, 0.45), flat)],
          0, upright(fly_body_col), 0.045, 6, 2600)
    blobs("fly_head", [((1.78, 0.22, 0), (0.42, 0.72, 0.8), flat)], 0, upright(fly_head_col), 0.04, 5, 900)
    for side in (-1, 1):
        ell("eye", (1.86, 0.36, 0.43 * side), (0.42, 0.6, 0.4), 0, upright(fly_eye_col), 18)
        ell("antenna", (2.18, 0.28, 0.12 * side), (0.12, 0.2, 0.08), 0, upright(const((0.35, 0.3, 0.25))), 8)
        tube("arista", [(2.24, 0.24, 0.13 * side), (2.5, 0.35, 0.22 * side)], [0.02, 0.008], 0, upright(const(FLY_DARK)), 4, cap=False)
        # legs, curled in over the belly as on a dead fly
        for hx, kn, an, tip in ((1.05, (0.55, -0.78, 0.72), (0.15, -1.18, 0.45), (-0.2, -1.02, 0.12)),
                                (0.65, (0.05, -0.8, 0.88), (-0.38, -1.18, 0.5), (-0.6, -1.0, 0.14)),
                                (0.25, (-0.5, -0.72, 0.88), (-0.98, -1.12, 0.45), (-0.82, -1.0, 0.1))):
            hip = (hx, -0.45, 0.25 * side)
            knee = (hx + kn[0], kn[1], kn[2] * side)
            ankle = (hx + an[0], an[1], an[2] * side)
            tp = (hx + tip[0], tip[1], tip[2] * side)
            legc = upright(const(FLY_DARK))
            tube("femur", [hip, lerp(hip, knee, 0.5), knee], [0.12, 0.11, 0.08], 0, legc, 6)
            tube("tibia", [knee, lerp(knee, ankle, 0.5), ankle], [0.075, 0.07, 0.06], 0, legc, 6)
            tube("tarsus", [ankle, lerp(ankle, tp, 0.5), tp], [0.05, 0.045, 0.035], 0, legc, 5)
            ell("pulvilli", tp, (0.07, 0.05, 0.07), 0, upright(const((0.5, 0.45, 0.35))), 6)
            for k in range(4):                       # bristles along the tibia
                at = lerp(knee, ankle, 0.2 + 0.2 * k)
                tube("leg_bristle", [at, (at[0] - 0.05, at[1] - 0.12, at[2] + 0.1 * side)], [0.015, 0.004], 0, legc, 3, cap=False)
        # halteres: the little knobbed balancers behind the wings
        tube("haltere", [(-0.15, 0.35, 0.55 * side), (-0.3, 0.4, 0.78 * side)], [0.03, 0.025], 0, upright(const((0.6, 0.55, 0.4))), 4)
        ell("haltere_knob", (-0.32, 0.4, 0.82 * side), (0.07, 0.06, 0.07), 0, upright(const((0.7, 0.64, 0.45))), 6)
    # proboscis and its sponging pad
    tube("proboscis", [(1.75, -0.4, 0), (1.92, -0.8, 0), (2.0, -1.0, 0)], [0.13, 0.11, 0.09], 0, upright(const((0.3, 0.27, 0.22))), 6)
    ell("labellum", (2.02, -1.08, 0), (0.18, 0.09, 0.24), 0, upright(const((0.42, 0.37, 0.3))), 8)
    # black bristles on the thorax
    for k in range(46):
        th = random.uniform(-1.2, 1.2)
        ph = random.uniform(0.25, 1.35)
        c = Vector((0.62, 0.2, 0.0))
        nrm = Vector((math.cos(ph) * math.cos(th) * 0.6 + 0.2, math.sin(ph), math.cos(ph) * math.sin(th))).normalized()
        base = c + Vector((nrm.x * 0.95, nrm.y * 0.78, nrm.z * 0.78)) * 0.97
        tip = base + (nrm * 0.75 + Vector((-0.6, 0.2, 0.0))).normalized() * random.uniform(0.18, 0.32)
        tube("bristle", [tuple(base), tuple(tip)], [0.018, 0.004], 0, upright(const(FLY_DARK)), 3, cap=False)
    # turn it over onto its back and set it on the ground
    gm = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
    c, s = math.cos(FLY_FLIP), math.sin(FLY_FLIP)
    rg = Matrix(((1, 0, 0), (0, c, -s), (0, s, c)))
    rb = (gm @ rg @ gm.inverted()).to_4x4()
    low = 1e9
    for o in OBJS:
        o.data.transform(rb)
        for v in o.data.vertices:
            low = min(low, GV(v.co).y)
    FLY_LIFT[0] = -low - 0.02
    for o in OBJS:
        o.data.transform(Matrix.Translation(G(0.0, FLY_LIFT[0], 0.0)))
        o.data.update()
    # the wings, added after turning it over: from their roots on the thorax they fall flat onto the
    # ground on either side (membrane in group 1, the dark veins of a Musca wing in group 0)
    for side in (-1, 1):
        r = Vector((0.45, 0.66, 0.32 * side))
        root = Vector((r.x, r.y * c - r.z * s + FLY_LIFT[0], r.y * s + r.z * c))
        sd = 1.0 if root.z > 0 else -1.0
        d = Vector((-0.75, 0.0, 0.66 * sd)).normalized()
        w = d.cross(Vector((0.0, 1.0, 0.0))) * sd
        xf = Matrix.Identity(4)
        for i in range(3):
            xf[i][0], xf[i][1], xf[i][2], xf[i][3] = d[i], (0.0, 1.0, 0.0)[i], w[i], root[i]
        h = root.y - 0.04
        lift = lambda u, v, h=h: -h * min(1.0, u / 1.1) ** 0.7
        outline = [(0.0, 0.0), (0.5, 0.33), (1.5, 0.58), (2.7, 0.66), (3.55, 0.48), (3.9, 0.12),
                   (3.75, -0.24), (2.9, -0.46), (1.6, -0.52), (0.6, -0.38), (0.12, -0.16)]
        sheet("wing", outline, xf, lift, 1, const((0.85, 0.88, 0.9)), 0.0)
        veins = [[(0.0, 0.05), (1.4, 0.55), (2.7, 0.66), (3.55, 0.48)],
                 [(0.1, 0.02), (1.6, 0.42), (2.9, 0.5), (3.6, 0.4)],
                 [(0.2, 0.0), (1.8, 0.18), (3.0, 0.25), (3.88, 0.14)],
                 [(0.25, -0.05), (1.9, -0.12), (2.9, -0.12), (3.3, 0.02), (3.82, 0.0)],
                 [(0.2, -0.12), (1.6, -0.33), (2.75, -0.44)],
                 [(1.95, 0.18), (1.9, -0.12)], [(2.75, -0.13), (2.65, -0.43)]]
        for vn in veins:
            pts = []
            for u, v in vn:
                gp = xf @ Vector((u, lift(u, v) + 0.012, v))
                pts.append((gp.x, gp.y, gp.z))
            tube("vein", pts, [0.016] * len(pts), 0, const((0.22, 0.19, 0.15)), 3, cap=False)
