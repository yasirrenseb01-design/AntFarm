# Part of tools/blender/build_ant.py (PART 0.14, v0.14.2): the wings of the alates - VARIANT gyne / male only, run after
# body, antennae, legs, setae, sharing its globals (QUEEN, GYNE, MALE, HI, G, _obj, PARTS).
# ---------------------------------------------------------------- wings (part 12)
#
# At rest an alate folds its four wings back over the gaster, the forewings on top, held like a roof and reaching past
# the gaster's tip [the keeper's photo reference/alate_gyne_side_user.png]. The membrane is clear; the veins brown and
# branching, closing cells [the keeper's venation figure (Dorylinae) for the names; laid out as in Formicinae - Lasius:
# a closed marginal (radial) cell beyond the pterostigma, one submarginal cell, a discoidal cell; positions eyeballed
# from photos, not measured]. Lengths: a gyne's forewing about her body length, a male's a little longer than his
# [inference; alates.md has no wing measurements].
# The membrane: a thin slab (both faces: Godot culls back faces), every vertex 1.0 - the shader leaves most of its
# pixels out (see-through, shaders/ants/ant.gdshader). The veins: thin strips of their own just over each face, value
# VEIN - drawn whole, brown; the stigma a filled patch. The value rides in UV.x (build_ant.py export: 20 + 10 x it).

WING = (1.0, 1.0, 1.0)
TENT = 0.55                  # the roof's slope across the wing (rise / width)
VEIN = 0.42
STIGMA = 0.3
TH = 0.018                   # the membrane's half thickness

# Veins as polylines in the wing's own (u along it from the root 0..1, v across from the costa 0 .. hind margin 1), and
# their half widths (in v of the wing's full width). The names as in the figure the keeper sent.
FORE = [
    ("C", [(0.0, 0.0), (0.3, 0.0), (0.56, 0.0)], 0.022),                          # costa, the leading edge to the stigma
    ("Sc+R", [(0.0, 0.07), (0.2, 0.06), (0.42, 0.07), (0.55, 0.06)], 0.016),
    ("R1", [(0.66, 0.02), (0.78, 0.05), (0.9, 0.09)], 0.011),                     # beyond the stigma, round to
    ("Rs-f", [(0.42, 0.07), (0.5, 0.17), (0.62, 0.22)], 0.012),                   # Rs out of the basal vein
    ("2r-rs", [(0.62, 0.22), (0.63, 0.08)], 0.011),                               # cross vein to the stigma
    ("Rs", [(0.62, 0.22), (0.76, 0.2), (0.9, 0.09)], 0.011),                      # ... closing the marginal cell at R1
    ("M+Cu", [(0.0, 0.16), (0.14, 0.24), (0.26, 0.3)], 0.014),
    ("M-f1", [(0.26, 0.3), (0.42, 0.07)], 0.012),                                 # the basal vein up to Sc+R
    ("M", [(0.42, 0.33), (0.6, 0.38), (0.78, 0.44), (0.93, 0.5)], 0.01),          # media on toward the margin
    ("Cu", [(0.26, 0.3), (0.42, 0.33), (0.5, 0.52)], 0.012),
    ("rs-m", [(0.62, 0.22), (0.6, 0.38)], 0.01),                                  # closing the submarginal cell
    ("Cu1", [(0.5, 0.52), (0.68, 0.64), (0.84, 0.76)], 0.01),
    ("cu-a", [(0.24, 0.42), (0.27, 0.62)], 0.01),
    ("A", [(0.0, 0.26), (0.24, 0.42), (0.38, 0.62)], 0.012),
]
HIND = [
    ("C+R", [(0.0, 0.02), (0.25, 0.03), (0.5, 0.04)], 0.015),
    ("Rs", [(0.32, 0.05), (0.5, 0.14), (0.72, 0.16)], 0.01),
    ("M+Cu", [(0.0, 0.18), (0.22, 0.3), (0.32, 0.34)], 0.012),
    ("M", [(0.32, 0.34), (0.55, 0.42)], 0.009),
    ("cu-a", [(0.22, 0.3), (0.26, 0.5)], 0.009),
]
STIGMA_UV = (0.55, 0.66, 0.0, 0.085)        # u from-to, v from-to


def _face(bm, verts, up):
    """A face whose front is toward up (+1: the wing's upper side, Blender +z) or down (-1)."""
    f = bm.faces.new(verts)
    f.normal_update()
    if f.normal.z * up < 0.0:
        f.normal_flip()
    return f


def _shape(u, width):
    """The wing's breadth at u: a narrow stalk at the root, widest past the middle, the tip rounded off."""
    w = width * (0.22 + 0.78 * math.sin(min(1.0, u * 1.25) * math.pi * 0.5))
    if u > 0.72:
        w *= math.sqrt(max(0.0, 1.0 - ((u - 0.72) / 0.28) ** 2))
    return max(w, width * 0.04)


def _at(p, u, v, face):
    """A point of the wing (Godot axes) at (u, v), on its upper (face 1), lower (-1) or middle (0) surface."""
    side, base, length, width, lift, spread, under = p
    w = _shape(u, width)
    x = base[0] - length * u
    # up off the root, then a steady slant over the gaster; held like a roof - the costa lowest, the hind margin up
    y = base[1] + lift * (0.3 * min(1.0, u * 3.0) + 0.7 * u) - (0.05 if under else 0.0)
    y += 0.02 * math.sin(v * math.pi) + w * v * TENT + face * (TH + 0.006)
    z = base[2] + side * spread * u - side * w * v
    return x, y, z


def _membrane(bm, p, vals):
    nu = 24 if HI else 8
    nv = 6 if HI else 2
    rows = []
    for i in range(nu + 1):
        u = i / nu
        top = []
        bot = []
        for j in range(nv + 1):
            v = j / nv
            x, y, z = _at(p, u, v, 0)
            top.append(bm.verts.new(G(x, y + TH, z)))
            vals.append(1.0)
            bot.append(bm.verts.new(G(x, y - TH, z)))
            vals.append(1.0)
        rows.append((top, bot))
    for i in range(nu):
        for j in range(nv):
            t0, b0 = rows[i]
            t1, b1 = rows[i + 1]
            _face(bm, (t0[j], t0[j + 1], t1[j + 1], t1[j]), 1)
            _face(bm, (b0[j], b1[j], b1[j + 1], b0[j + 1]), -1)


def _strip(bm, p, pts, hw, val, vals):
    """A vein: a thin band along the polyline (u, v) on each face of the wing, half width hw (of the wing's width)."""
    steps = []
    for a, b in zip(pts[:-1], pts[1:]):
        n = 3 if HI else 1
        for k in range(n):
            t = k / n
            steps.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    steps.append(pts[-1])
    for face in (1, -1):
        prev = None
        for i, (u, v) in enumerate(steps):
            # across the vein: its direction turned square, in lengths (u and v scaled to the wing's length and breadth)
            a = steps[max(0, i - 1)]
            b = steps[min(len(steps) - 1, i + 1)]
            wu = _shape(u, p[3])
            du = (b[0] - a[0]) * p[2]
            dv = (b[1] - a[1]) * wu
            ln = math.hypot(du, dv) or 1.0
            off = hw * p[3]                                    # the half width in length units
            off_u = -dv / ln * off / p[2]
            off_v = du / ln * off / wu
            l = bm.verts.new(G(*_at(p, min(1.0, max(0.0, u + off_u)), min(1.0, max(0.0, v + off_v)), face)))
            r = bm.verts.new(G(*_at(p, min(1.0, max(0.0, u - off_u)), min(1.0, max(0.0, v - off_v)), face)))
            vals.append(val)
            vals.append(val)
            if prev is not None:
                _face(bm, (prev[0], prev[1], r, l), face)
            prev = (l, r)


def _stigma(bm, p, vals):
    u0, u1, v0, v1 = STIGMA_UV
    n = 3 if HI else 1
    for face in (1, -1):
        grid = []
        for i in range(n + 1):
            row = []
            for j in range(2):
                u = u0 + (u1 - u0) * i / n
                v = v0 + (v1 - v0) * j * (1.0 - 0.5 * abs(2.0 * i / n - 1.0))   # (a lens, thickest in its middle)
                row.append(bm.verts.new(G(*_at(p, u, v, face))))
                vals.append(STIGMA)
            grid.append(row)
        for i in range(n):
            a, b = grid[i], grid[i + 1]
            _face(bm, (a[0], b[0], b[1], a[1]), face)


def _wing(name, side, base, length, width, lift, spread, under):
    """One wing folded back: from `base` (x, y, z) along -x for `length`, `width` across (costa outermost), rising by
    `lift` over the gaster, its tip `spread` further out to the side; `under`: a hindwing."""
    p = (side, base, length, width, lift, spread, under)
    bm = bmesh.new()
    vals = []
    _membrane(bm, p, vals)
    for _n, pts, hw in (HIND if under else FORE):
        _strip(bm, p, pts, hw * (1.0 if HI else 1.6), VEIN, vals)
    if not under:
        _stigma(bm, p, vals)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = _obj(name, me, 12, WING)
    for poly in me.polygons:
        poly.use_smooth = True
    o["vein"] = vals                 # (each vertex's value, in the order made: the colour pass and the export, build_ant.py)
    return o


# roots at the side of the thorax at the back of the scutum, behind the tegula (body.py)
if GYNE:
    L, W, X0, Y0, LIFT, Z0, SP = 8.4, 2.4, -0.72, 2.08, 1.2, 0.9, 0.45
else:
    L, W, X0, Y0, LIFT, Z0, SP = 6.4, 1.8, -0.08, 1.82, 1.05, 0.75, 0.36
for side in (-1, 1):
    _wing("hindwing", side, (X0 - 0.35, Y0 - 0.08, Z0 * side * 0.95), L * 0.72, W * 0.62, LIFT * 0.85, SP * 0.6, True)
    _wing("forewing", side, (X0, Y0, Z0 * side), L, W, LIFT, SP, False)
