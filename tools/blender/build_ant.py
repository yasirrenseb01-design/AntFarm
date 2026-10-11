# Blender-side builder for the Lasius niger worker and queen models used by the game.
# Run inside Blender (python tools/blender/bl.py tools/blender/build_ant.py VARIANT=worker LOD=hi)
# or headless (blender --background --python tools/blender/build_ant.py -- worker hi).
#
# Modelled in the game's "design units" (1 unit ~ 0.5 mm, ant facing +x, feet at y = 0) so the
# joints line up with the pivots in shaders/ant.gdshader; exported scaled by K = 0.34.
# Every vertex carries colour (a multiplier on the per-ant tint) and in alpha the body-part id / 16:
# 0 trunk, 1 head, 2/3 left/right antenna, 4-9 legs (FL, FR, ML, MR, HL, HR), 10 gaster, 11 mandibles.
# "Left" is the -z side in Godot. Output: assets/models/ants/<variant>_<lod>.antmesh (see ant_model3d.gd).
# Leg vertices also carry which leg segment they belong to (1 coxa, 2 femur, 3 tibia, 4 tarsus; 0 elsewhere),
# so the shader can bend the knee and plant the foot (inverse kinematics on the joints listed in LEGS).
import bpy
import bmesh
import math
import os
import random
import struct
import sys
from mathutils import Vector, Matrix

if "--" in sys.argv:
    _a = sys.argv[sys.argv.index("--") + 1:]
    VARIANT, LOD = (_a + ["worker", "hi"])[:2]
VARIANT = globals().get("VARIANT", "worker")
LOD = globals().get("LOD", "hi")
OUT = globals().get("OUT", "E:/AntFarm/assets/models/ants")
SHOT = globals().get("SHOT", "")
QUEEN = VARIANT == "queen"
HI = LOD == "hi"
K = 0.34
random.seed(7 if not QUEEN else 11)

BODY = (0.55, 0.55, 0.55)
SUTURE = (0.47, 0.47, 0.47)
LIMB = (0.9, 0.82, 0.76)
TARSUS = (1.0, 0.93, 0.86)
MAND = (1.0, 0.72, 0.45)
EYE = (0.07, 0.07, 0.07)
HAIR = (1.0, 0.9, 0.72)
FUNICLE = (0.5, 0.46, 0.46)


def G(x, y, z):
    """Godot axes (x forward, y up, z to the right) -> Blender (z up)."""
    return Vector((x, -z, y))


# ---------------------------------------------------------------- scene

scn = bpy.data.scenes.get("AntFarm") or bpy.data.scenes.new("AntFarm")
if bpy.context.window:
    bpy.context.window.scene = scn
cname = "%s_%s" % (VARIANT, LOD)
coll = bpy.data.collections.get(cname)
if coll is None:
    coll = bpy.data.collections.new(cname)
    scn.collection.children.link(coll)
for o in list(coll.objects):
    bpy.data.objects.remove(o, do_unlink=True)
# only the model being built is shown
for c in scn.collection.children:
    c.hide_render = c != coll
    c.hide_viewport = c != coll

PARTS = []
CUR_SEG = [0, None]          # leg segment for new objects (-1 = per vertex, by nearest joint line) and the joints


def _obj(name, me, part, col):
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)
    o["part"] = part
    o["rgb"] = col
    o["seg"] = CUR_SEG[0]
    if CUR_SEG[1] is not None:
        o["joints"] = [c for p in CUR_SEG[1] for c in p]
    for p in me.polygons:
        p.use_smooth = True
    PARTS.append(o)
    return o


def _bake(o):
    """Apply the object's modifiers into its mesh."""
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
    o.modifiers.clear()
    old = o.data
    o.data = me
    bpy.data.meshes.remove(old)


def blob_group(name, blobs, part, col, voxel, smooth, faces):
    """Union of ellipsoids [(centre, (rx, ry, rz) in Godot axes, pitch about z)], remeshed into one
    smooth skin and reduced to about `faces` faces."""
    bm = bmesh.new()
    for c, r, pitch in blobs:
        geom = bmesh.ops.create_uvsphere(bm, u_segments=28, v_segments=18, radius=1.0)
        m = Matrix.Translation(c) @ Matrix.Rotation(pitch, 4, "Y") @ Matrix.Diagonal((r[0], r[2], r[1], 1.0))
        bmesh.ops.transform(bm, matrix=m, verts=[v for v in geom["verts"]])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = _obj(name, me, part, col)
    rm = o.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = voxel
    sm = o.modifiers.new("smooth", "SMOOTH")
    sm.factor = 0.6
    sm.iterations = smooth
    _bake(o)
    o["faces"] = faces
    return o


def finish(o):
    """Smooth over any carving, then reduce to the face budget."""
    sm = o.modifiers.new("smooth", "SMOOTH")
    sm.factor = 0.5
    sm.iterations = 2
    _bake(o)
    n = len(o.data.polygons)
    if n > o["faces"]:
        d = o.modifiers.new("dec", "DECIMATE")
        d.ratio = o["faces"] / n
        _bake(o)
    for p in o.data.polygons:
        p.use_smooth = True


def carve(o, fn):
    """Displace vertices along their normal by fn(godot_point) (sutures, plate margins)."""
    me = o.data
    me.update()
    for v in me.vertices:
        g = Vector((v.co.x, v.co.z, -v.co.y))
        d = fn(g)
        if d != 0.0:
            v.co += v.normal * d
    me.update()


def tube(name, pts, radii, part, col, segs, cap=True):
    """A tapered tube along points (Godot axes) with a radius per point."""
    pts = [G(*p) for p in pts]
    bm = bmesh.new()
    rings = []
    prev_n = None
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        if prev_n is None:
            a = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
            prev_n = t.cross(a).normalized()
        n = (prev_n - t * prev_n.dot(t)).normalized()
        prev_n = n
        b = t.cross(n)
        ring = []
        for k in range(segs):
            ang = math.tau * k / segs
            ring.append(bm.verts.new(p + (n * math.cos(ang) + b * math.sin(ang)) * radii[i]))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(segs):
            k2 = (k + 1) % segs
            bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
    if cap:
        for ring, p, sgn in ((rings[0], pts[0], -1), (rings[-1], pts[-1], 1)):
            d = (pts[1] - pts[0]) if sgn < 0 else (pts[-1] - pts[-2])
            tip = bm.verts.new(p + d.normalized() * sgn * radii[0 if sgn < 0 else -1] * 0.6)
            for k in range(segs):
                k2 = (k + 1) % segs
                f = (ring[k2], ring[k], tip) if sgn < 0 else (ring[k], ring[k2], tip)
                bm.faces.new(f)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return _obj(name, me, part, col)


def ellipsoid(name, c, r, part, col, segs=12, rot=Matrix.Identity(4)):
    bm = bmesh.new()
    geom = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=max(4, segs * 2 // 3), radius=1.0)
    m = Matrix.Translation(G(*c)) @ rot @ Matrix.Diagonal((r[0], r[2], r[1], 1.0))
    bmesh.ops.transform(bm, matrix=m, verts=geom["verts"])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return _obj(name, me, part, col)


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


# ---------------------------------------------------------------- body

voxel = 0.035 if HI else 0.07
budget = 0.5 if HI else 0.09
ms = 1.28 if QUEEN else 1.0
gs = 1.35 if QUEEN else 1.0
gx = -2.75 if QUEEN else -2.5

# gaster: four overlapping tergites, covered in fine pubescence; the queen's swollen with ovaries
gaster = blob_group("gaster", [
    (G(gx, 1.05, 0), (1.9 * gs, 1.3 * gs, 1.42 * gs), 0.0),
    (G(gx + 1.35 * gs, 1.05, 0), (0.75 * gs, 0.9 * gs, 0.95 * gs), 0.0),     # first segment narrows to the petiole
], 10, BODY, voxel * gs, 8, int(2600 * budget))
plate_edges = [gx + gs * e for e in (0.62, -0.18, -0.92)]


def _tergites(g):
    if g.y < 1.05 - 0.9 * gs:
        return 0.0                                           # sternites underneath: smooth
    d = 0.0
    for xb in plate_edges:
        d += -0.06 * gs * math.exp(-((g.x - xb) / 0.07) ** 2) + 0.03 * gs * math.exp(-((g.x - (xb + 0.14)) / 0.1) ** 2)
    return d


carve(gaster, _tergites)
finish(gaster)

# petiole: a single upright scale, thin front to back, its top margin slightly notched
petiole = blob_group("petiole", [
    (G(-0.74, 1.2, 0), (0.17, 0.66, 0.48), -0.25),
    (G(-0.7, 0.75, 0), (0.24, 0.24, 0.24), 0.0),
], 0, BODY, voxel * 0.7, 4, int(500 * budget))
carve(petiole, lambda g: -0.06 * math.exp(-(g.z / 0.1) ** 2) * max(0.0, (g.y - 1.65) / 0.2))
finish(petiole)

# mesosoma: pronotum, mesonotum, the metanotal groove, propodeum; in the queen a deep thorax for the
# flight muscles with scutum, scutellum and the stubs where the wings were broken off
if not QUEEN:
    meso = [
        (G(0.78, 1.18, 0), (0.75, 0.6, 0.62), 0.0),
        (G(0.08, 1.25, 0), (0.62, 0.56, 0.52), 0.0),
        (G(-0.38, 1.0, 0), (0.45, 0.5, 0.48), 0.25),
        (G(1.3, 1.12, 0), (0.28, 0.24, 0.24), 0.0),            # neck
        (G(0.4, 0.75, 0), (0.85, 0.35, 0.5), 0.0),             # pleura and coxal bases
    ]
else:
    meso = [
        (G(1.0, 1.2, 0), (0.42, 0.5, 0.52), 0.0),              # pronotum: a narrow collar
        (G(0.2, 1.72, 0), (0.98, 1.08, 0.74), 0.0),            # scutum: the big dome over the flight muscles
        (G(-0.6, 2.05, 0), (0.4, 0.34, 0.44), 0.0),            # scutellum
        (G(-0.62, 1.15, 0), (0.42, 0.6, 0.55), 0.35),          # propodeum, dropping steeply
        (G(0.3, 0.8, 0), (0.95, 0.42, 0.6), 0.0),              # pleura and coxal bases
        (G(1.32, 1.12, 0), (0.26, 0.24, 0.24), 0.0),           # neck
    ]
thorax = blob_group("mesosoma", meso, 0, BODY, voxel, 6, int(1800 * budget))
groove_x = -0.12 if not QUEEN else -0.2
if QUEEN:
    # sutures around the scutum and scutellum
    carve(thorax, lambda g: -0.05 * math.exp(-((g.x - groove_x) / 0.05) ** 2) * max(0.0, min(1.0, (g.y - 1.6) / 0.3))
        - 0.04 * math.exp(-((g.x - 0.78) / 0.05) ** 2) * max(0.0, min(1.0, (g.y - 1.4) / 0.3)))
else:
    carve(thorax, lambda g: (-0.09 * math.exp(-((g.x - groove_x) / 0.07) ** 2) * max(0.0, min(1.0, (g.y - 1.0) / 0.3)))
        + (-0.03 * math.exp(-((g.x - 0.42) / 0.04) ** 2) * max(0.0, min(1.0, (g.y - 1.3) / 0.2))))   # pro-mesonotal suture
finish(thorax)
if QUEEN:
    for side in (-1, 1):
        ellipsoid("wing_stub", (-0.15, 1.75, 0.66 * side), (0.24, 0.1, 0.13), 0, SUTURE, 10)

# head: oval capsule slightly longer than broad, posterior margin shallowly concave between two lobes,
# clypeus with a faint median keel, compound eyes at the sides (the queen also has three ocelli)
hs = 0.9 if QUEEN else 1.0
head = blob_group("head", [
    (G(2.15, 1.15, 0), (0.95 * hs, 0.72 * hs, 0.86 * hs), 0.0),
    (G(2.15 - 0.57 * hs, 1.18, 0.4 * hs), (0.5 * hs, 0.62 * hs, 0.46 * hs), 0.0),
    (G(2.15 - 0.57 * hs, 1.18, -0.4 * hs), (0.5 * hs, 0.62 * hs, 0.46 * hs), 0.0),
    (G(2.15 + 0.73 * hs, 1.05, 0), (0.34 * hs, 0.28 * hs, 0.5 * hs), 0.0),            # clypeus
], 1, BODY, voxel, 6, int(1800 * budget))
carve(head, lambda g: -0.05 * math.exp(-(g.z / 0.12) ** 2) * math.exp(-((g.x - 1.12) / 0.12) ** 2)
    + 0.025 * math.exp(-(g.z / 0.05) ** 2) * math.exp(-((g.x - 2.85) / 0.15) ** 2) * (1.0 if g.y > 1.2 else 0.0))
finish(head)
for side in (-1, 1):
    ellipsoid("eye", (2.15 + 0.2 * hs, 1.3, 0.8 * side * hs), (0.25 * hs, 0.3 * hs, 0.13), 1, EYE, 12 if HI else 6)
if QUEEN and HI:
    for o in [(2.05, 1.86, 0.0), (1.9, 1.82, 0.16), (1.9, 1.82, -0.16)]:
        ellipsoid("ocellus", o, (0.07, 0.05, 0.07), 1, EYE, 8)


# mandibles: triangular blades crossing in front of the clypeus, a row of teeth on the chewing edge
def mandible(side):
    s = side
    outline = [(2.72, 0.5 * s), (3.15, 0.56 * s), (3.48, 0.34 * s), (3.62, 0.04 * s)]
    teeth = 7 if HI else 3
    a = (3.62, 0.04 * s)
    b = (3.0, 0.2 * s)
    for i in range(1, teeth * 2):
        t = i / (teeth * 2)
        x = a[0] + (b[0] - a[0]) * t
        z = a[1] + (b[1] - a[1]) * t
        dent = 0.05 if i % 2 == 1 else 0.0
        outline.append((x - dent * 0.6, z + dent * 0.8 * s))
    outline += [b, (2.8, 0.24 * s)]
    if s < 0:
        outline.reverse()
    bm = bmesh.new()
    top = [bm.verts.new(G(x, 0.98, z)) for x, z in outline]
    bot = [bm.verts.new(G(x, 0.84, z)) for x, z in outline]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((top[i], bot[i], bot[j], top[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    me = bpy.data.meshes.new("mandible")
    bm.to_mesh(me)
    bm.free()
    o = _obj("mandible", me, 11, MAND)
    for p in me.polygons:
        p.use_smooth = False


for side in (-1, 1):
    mandible(side)

# ---------------------------------------------------------------- antennae (12 segments: scape + 11)

segs = 6 if HI else 3
for side in (-1, 1):
    part = 2 if side < 0 else 3
    root = (2.7, 1.45, 0.38 * side)
    elbow = (3.45, 2.45, 1.25 * side)
    mid = lerp(root, elbow, 0.5)
    mid = (mid[0] - 0.05, mid[1] + 0.08, mid[2])
    tube("scape", [root, lerp(root, mid, 0.5), mid, lerp(mid, elbow, 0.5), elbow], [0.09, 0.085, 0.095, 0.11, 0.12], part, LIMB, segs)
    pts = [elbow]
    n = 11 if HI else 3
    for b in range(n):
        t = (b + 1) / n
        pts.append((elbow[0] + 1.55 * t, elbow[1] - 0.95 * t + 0.35 * math.sin(t * math.pi), elbow[2] + 0.45 * t * side))
    for b in range(n):
        a, c = pts[b], pts[b + 1]
        r = 0.075 + 0.035 * (b / max(1, n - 1)) if HI else 0.09        # funiculus thickens gradually toward the tip
        if HI:
            tube("funicle", [a, lerp(a, c, 0.5), c], [r * 0.8, r * 1.05, r * 0.85], part, FUNICLE, segs, cap=False)
        else:
            tube("funicle", [a, c], [r, r], part, FUNICLE, segs)

# ---------------------------------------------------------------- legs

LEGS = [[0.85, 0.75, 1.8], [0.2, 0.1, -0.1], [-0.4, -0.65, -2.2]]
for li, L in enumerate(LEGS):
    for side in (-1, 1):
        part = 4 + li * 2 + (0 if side < 0 else 1)
        hip = (L[0], 0.85, 0.42 * side)
        coxa = (L[0] + 0.1, 0.55, 0.85 * side)
        knee = (L[0] + L[1], 1.75, 2.05 * side)
        ankle = (L[0] + L[2] * 0.85, 0.35, 2.9 * side)
        foot = (L[0] + L[2], 0.0, 3.15 * side)
        CUR_SEG[1] = [hip, coxa, knee, ankle, foot]
        if HI:
            CUR_SEG[0] = 1
            tube("coxa", [hip, lerp(hip, coxa, 0.5), coxa], [0.2, 0.22, 0.17], part, LIMB, segs)
            CUR_SEG[0] = 2
            fem = [lerp(coxa, knee, t) for t in (0.0, 0.12, 0.4, 0.75, 1.0)]
            tube("femur", fem, [0.12, 0.15, 0.18, 0.15, 0.12], part, LIMB, segs)
            CUR_SEG[0] = 3
            tib = [lerp(knee, ankle, t) for t in (0.0, 0.1, 0.6, 1.0)]
            tube("tibia", tib, [0.1, 0.095, 0.11, 0.12], part, LIMB, segs)
            spur = lerp(ankle, foot, 0.25)
            tube("spur", [ankle, (spur[0], spur[1] + 0.05, spur[2] - 0.1 * side)], [0.035, 0.01], part, LIMB, 4)
            # tarsus: five segments, a little arched, the last with a pair of claws
            CUR_SEG[0] = 4
            prev = ankle
            for k in range(5):
                t = (k + 1) / 5.0
                p = lerp(ankle, foot, t)
                p = (p[0], p[1] + 0.08 * math.sin(t * math.pi), p[2])
                r = 0.075 - 0.004 * k
                tube("tarsomere", [prev, lerp(prev, p, 0.6), p], [r * 0.85, r * 1.08, r * 0.9], part, TARSUS, 4, cap=False)
                prev = p
            fwd = Vector(foot) - Vector(ankle)
            fwd.normalize()
            for cz in (-0.05, 0.05):
                tip = (foot[0] + fwd.x * 0.14, foot[1] - 0.06, foot[2] + fwd.z * 0.14 + cz)
                tube("claw", [foot, tip], [0.025, 0.006], part, SUTURE, 4)
        else:
            # far-away ants: no segments, so the shader swings the legs whole (cheap) instead of solving IK
            CUR_SEG[0] = 0
            tube("leg", [hip, coxa, knee], [0.18, 0.16, 0.13], part, LIMB, segs)
            tube("leg", [knee, ankle, foot], [0.11, 0.11, 0.07], part, LIMB, segs)
CUR_SEG[0] = 0
CUR_SEG[1] = None

# ---------------------------------------------------------------- erect setae (hi only)


def setae(o, count, length, keep):
    me = o.data
    me.calc_loop_triangles()
    tris = [t for t in me.loop_triangles]
    if not tris:
        return
    bm = bmesh.new()
    placed = 0
    tries = 0
    while placed < count and tries < count * 40:
        tries += 1
        t = random.choice(tris)
        a, b, c = (me.vertices[i].co for i in t.vertices)
        u, v = random.random(), random.random()
        if u + v > 1.0:
            u, v = 1.0 - u, 1.0 - v
        p = a + (b - a) * u + (c - a) * v
        n = t.normal.copy()
        g = Vector((p.x, p.z, -p.y))
        if not keep(g, Vector((n.x, n.z, -n.y))):
            continue
        d = (n + Vector((-0.6, 0, 0))).normalized()          # hairs slant backwards
        ln = length * random.uniform(0.7, 1.2)
        side = n.cross(Vector((0, 0, 1)))
        if side.length < 0.1:
            side = n.cross(Vector((1, 0, 0)))
        side.normalize()
        side2 = n.cross(side)
        r = 0.009
        base = [bm.verts.new(p - n * 0.01 + (side * math.cos(k * 2.094) + side2 * math.sin(k * 2.094)) * r) for k in range(3)]
        tip = bm.verts.new(p + d * ln)
        for k in range(3):
            bm.faces.new((base[k], base[(k + 1) % 3], tip))
        placed += 1
    me2 = bpy.data.meshes.new("setae")
    bm.to_mesh(me2)
    bm.free()
    h = _obj("setae", me2, o["part"], HAIR)
    for p in me2.polygons:
        p.use_smooth = False


if HI:
    setae(gaster, 60 if not QUEEN else 100, 0.2, lambda g, n: n.y > -0.2)
    setae(thorax, 14, 0.17, lambda g, n: n.y > 0.5)
    setae(head, 12, 0.15, lambda g, n: n.y > 0.3 or abs(g.x - 2.9) < 0.3)

# ---------------------------------------------------------------- colours, export, preview

for o in PARTS:
    me = o.data
    if "Col" not in me.color_attributes:
        me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    attr = me.color_attributes["Col"]
    rgb = o["rgb"]
    part = o["part"]
    for i, v in enumerate(me.vertices):
        g = Vector((v.co.x, v.co.z, -v.co.y))
        p = part
        if part in (2, 3) or 4 <= part <= 9:
            pass
        col = list(rgb)
        if part == 10 and rgb == BODY:
            # the hind margin of each tergite is thinner and paler than the plate
            band = 0.0
            for xb in plate_edges:
                band = max(band, math.exp(-((g.x - (xb + 0.06)) / 0.06) ** 2))
            col = [c + (0.8 - c) * band * 0.8 for c in col]
        attr.data[i].color = (col[0], col[1], col[2], p / 16.0)


def _nearest_seg(g, j):
    """Which leg segment a point is closest to: hip-coxa 1, coxa-knee 2, knee-ankle 3, ankle-foot 4."""
    best, bd = 1, 1e9
    for s in range(4):
        a = Vector(j[s * 3:s * 3 + 3])
        b = Vector(j[s * 3 + 3:s * 3 + 6])
        ab = b - a
        t = max(0.0, min(1.0, (g - a).dot(ab) / max(ab.length_squared, 1e-9)))
        d = (g - (a + ab * t)).length
        if d < bd:
            best, bd = s + 1, d
    return best


def export(path):
    verts = []
    idx = []
    for o in PARTS:
        seg = o.get("seg", 0)
        joints = list(o["joints"]) if "joints" in o else None
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        bm.normal_update()
        col_layer = bm.verts.layers.float_color.get("Col")
        flat = not o.data.polygons[0].use_smooth if len(o.data.polygons) else False
        rgb = o["rgb"]
        a = o["part"] / 16.0
        shared = {}
        for f in bm.faces:
            tri = []
            for v in f.verts:
                key = v.index if not flat else None
                if key is not None and key in shared:
                    tri.append(shared[key])
                    continue
                n = f.normal if flat else v.normal
                c = v[col_layer] if col_layer else (rgb[0], rgb[1], rgb[2], a)
                sg = seg if seg >= 0 else _nearest_seg(Vector((v.co.x, v.co.z, -v.co.y)), joints)
                verts.append((v.co.x * K, v.co.z * K, -v.co.y * K, n.x, n.z, -n.y, c[0], c[1], c[2], a, float(sg)))
                tri.append(len(verts) - 1)
                if key is not None:
                    shared[key] = tri[-1]
            idx += [tri[0], tri[2], tri[1]]                  # Godot's front faces wind clockwise
        bm.free()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(b"ANT2")              # ANTM + an 11th float per vertex: the leg segment
        fh.write(struct.pack("<II", len(verts), len(idx)))
        for v in verts:
            fh.write(struct.pack("<11f", *v))
        fh.write(struct.pack("<%dI" % len(idx), *idx))
    return len(verts), len(idx) // 3


nv, nt = export("%s/%s_%s.antmesh" % (OUT, VARIANT, LOD))

# preview material: vertex colour times the game's Lasius niger tint
mat = bpy.data.materials.get("ant_preview") or bpy.data.materials.new("ant_preview")
mat.use_nodes = True
nt_ = mat.node_tree
nt_.nodes.clear()
out = nt_.nodes.new("ShaderNodeOutputMaterial")
bsdf = nt_.nodes.new("ShaderNodeBsdfPrincipled")
attr = nt_.nodes.new("ShaderNodeAttribute")
attr.attribute_name = "Col"
mul = nt_.nodes.new("ShaderNodeVectorMath")
mul.operation = "MULTIPLY"
mul.inputs[1].default_value = (0.136, 0.091, 0.069)
nt_.links.new(attr.outputs["Color"], mul.inputs[0])
nt_.links.new(mul.outputs[0], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 0.38
nt_.links.new(bsdf.outputs[0], out.inputs[0])
for o in PARTS:
    o.data.materials.clear()
    o.data.materials.append(mat)

print("%s %s: %d vertices, %d triangles, %d parts" % (VARIANT, LOD, nv, nt, len(PARTS)))

if SHOT:
    # studio render: camera three-quarter from the front-left, key + rim light
    for n in ("cam", "key", "rim", "fill"):
        o = bpy.data.objects.get("pv_" + n)
        if o:
            bpy.data.objects.remove(o, do_unlink=True)
    cam = bpy.data.objects.new("pv_cam", bpy.data.cameras.new("pv_cam"))
    scn.collection.objects.link(cam)
    view = globals().get("VIEW", "3q")
    target = Vector((0.4 if not QUEEN else 0.0, 0, 1.0))
    dirs = {"3q": Vector((0.7, -1.0, 0.55)), "side": Vector((0.0, -1.0, 0.12)), "top": Vector((0.0, -0.05, 1.0)),
        "front": Vector((1.0, -0.35, 0.3))}
    d = dirs.get(view, dirs["3q"]).normalized()
    cam.location = target + d * (24.0 if not QUEEN else 30.0)
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 60
    scn.camera = cam
    for n, loc, e in (("key", (4, -5, 7), 900), ("rim", (-6, 4, 4), 600), ("fill", (2, 6, -1), 150)):
        L = bpy.data.objects.new("pv_" + n, bpy.data.lights.new("pv_" + n, "AREA"))
        L.data.energy = e
        L.data.size = 4
        L.location = loc
        L.rotation_euler = (target - L.location).to_track_quat("-Z", "Y").to_euler()
        scn.collection.objects.link(L)
    world = bpy.data.worlds.get("pv_world") or bpy.data.worlds.new("pv_world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.32, 0.27, 0.22, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.5
    scn.world = world
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scn.render.engine = eng
            break
        except TypeError:
            pass
    scn.render.resolution_x = 1200
    scn.render.resolution_y = 800
    scn.render.film_transparent = False
    scn.render.filepath = SHOT
    bpy.ops.render.render(write_still=True, scene=scn.name)
    print("rendered", SHOT)
