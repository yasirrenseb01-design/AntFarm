# Blender-side builder for the keeper's right hand in the Home (game/home.gd, view/home/home_hand.gd; the keeper,
# 2026-10-27: "the hand looks like a mannequin's - make it in Blender"). Run inside Blender:
#   python tools/blender/bl.py tools/blender/build_hand.py [SHOT=<png>]
# A grown-up's right hand, palm down, the fingers along -z (Godot axes, metres; y up = the back of the hand): the palm a
# rounded, slightly arched block, fingers swept as tapering tubes through their joints (a little wider at the knuckles),
# a thumb of three bones, knuckle bumps, nails; one surface (voxel remesh, smoothed). Posed twice from the same mesh by
# blending each point between the bones near it (linear blend skinning), so both files have the same points in the same
# order: hand_open (relaxed, a little open) and hand_point (the first finger out, the others curled, the thumb in) -
# Godot blends between them. A knit sleeve, its cuff at the wrist, is a mesh of its own. Vertex colour (sRGB): the skin -
# warmer at the knuckles and the finger ends, paler on the palm side - and the nails.
#   -> assets/models/hand/hand_open.antmesh, hand_point.antmesh, sleeve.antmesh  (format: ant_model3d.gd load_antmesh)
import bpy
import bmesh
import math
import os
import struct
from mathutils import Vector, Matrix, Quaternion

OUT = globals().get("OUT", "E:/AntFarm/assets/models/hand")
SHOT = globals().get("SHOT", "")


def B(v):                      # Godot (x, y, z) -> Blender (x, -z, y)
    return Vector((v.x, -v.z, v.y))


def GV(v):                     # Blender -> Godot
    return Vector((v.x, v.z, -v.y))


scn = bpy.data.scenes.get("AntFarm") or bpy.data.scenes.new("AntFarm")
if bpy.context.window:
    bpy.context.window.scene = scn
coll = bpy.data.collections.get("hand")
if coll is None:
    coll = bpy.data.collections.new("hand")
    scn.collection.children.link(coll)
for o in list(coll.objects):
    bpy.data.objects.remove(o, do_unlink=True)
for c in scn.collection.children:
    c.hide_render = c != coll
    c.hide_viewport = c != coll

# ---------------------------------------------------------------- the skeleton (rest = relaxed)
# per finger: the knuckle (MCP) in the palm, its sideways splay, bone lengths, radius at the base; bends (rad, toward
# the palm) at the three joints for each pose. [Proportions: an adult hand ~19 cm long, the palm ~10.5 cm, ~8.2 cm
# across the knuckles; the first finger ~7 cm, the middle ~7.8, the ring ~7.3, the little ~5.8; phalanges about
# 45 : 30 : 25 of the finger - anthropometric averages, rounded.]
FINGERS = [
    # name, knuckle (x, y, z), splay, lengths, radius
    ("index", Vector((-0.030, 0.000, -0.096)), -0.07, (0.032, 0.022, 0.018), 0.0092),
    ("middle", Vector((-0.010, 0.002, -0.100)), 0.0, (0.036, 0.024, 0.019), 0.0094),
    ("ring", Vector((0.010, 0.001, -0.097)), 0.06, (0.033, 0.023, 0.018), 0.0088),
    ("little", Vector((0.028, -0.002, -0.087)), 0.15, (0.026, 0.018, 0.016), 0.0076),
]
POSES = {
    "open": {"index": (0.22, 0.25, 0.12), "middle": (0.26, 0.3, 0.15), "ring": (0.3, 0.34, 0.17),
             "little": (0.36, 0.38, 0.2), "thumb": (0.1, 0.12, 0.1), "thumb_rot": (0.3, -0.35, 0.2)},
    "point": {"index": (0.05, 0.04, 0.02), "middle": (1.45, 1.6, 1.0), "ring": (1.5, 1.65, 1.0),
              "little": (1.55, 1.7, 1.05), "thumb": (0.3, 0.45, 0.35), "thumb_rot": None},
}
# (the keeper, 2026-10-27, with photos of their own hand: the thumb splayed too far and was too long; pointing, a
# closed fist's thumb lies on the curled middle finger - its pad on the middle bone. Open: closer in to the first
# finger. Pointing: its turn found by search below so that its tip lies there.)
THUMB_BASE = Vector((-0.030, -0.012, -0.022))
THUMB_LEN = (0.034, 0.027, 0.022)       # (the metacarpal mostly inside the palm's ball; v0.11.53 had 0.040, 0.031, 0.026)
THUMB_R = 0.0112


def bend_dir(splay, bends_so_far):
    """The bone's direction: forward (-z), turned sideways by the splay, bent down (toward -y) by the sum."""
    d = Vector((0, 0, -1))
    d = Matrix.Rotation(-bends_so_far, 3, Vector((1, 0, 0))) @ d      # (about +x, a negative turn takes -z to -y)
    return Matrix.Rotation(-splay, 3, Vector((0, 1, 0))) @ d


def chains(pose):
    """Each finger's joint points (base, 3 joints, tip) and the frames (rotation) of its bones, for a pose."""
    out = {}
    for name, k, splay, lens, r in FINGERS:
        bends = POSES[pose][name]
        pts = [k.copy()]
        rots = []
        acc = 0.0
        for i in range(3):
            acc += bends[i]
            d = bend_dir(splay, acc)
            rots.append(Matrix.Rotation(-splay, 4, Vector((0, 1, 0))) @ Matrix.Rotation(-acc, 4, Vector((1, 0, 0))))
            pts.append(pts[-1] + d * lens[i])
        out[name] = (pts, rots, r)
    # the thumb: out from the base of the palm, forward, to the side and down; tucked in across the palm to point
    bends = POSES[pose]["thumb"]
    yaw, roll, pitch = POSES[pose]["thumb_rot"]
    out["thumb"] = thumb(yaw, roll, pitch, bends)
    return out


def thumb(yaw, roll, pitch, bends):
    """The thumb's joints and bone frames for its turn at the base (about y: out to the side; z: rolled; x: up)."""
    base_rot = (Matrix.Rotation(yaw, 4, Vector((0, 1, 0))) @ Matrix.Rotation(roll, 4, Vector((0, 0, 1)))
                @ Matrix.Rotation(pitch, 4, Vector((1, 0, 0))))
    pts = [THUMB_BASE.copy()]
    rots = []
    acc = 0.0
    for i in range(3):
        acc += bends[i]
        m = base_rot @ Matrix.Rotation(-acc, 4, Vector((1, 0, 0)))
        rots.append(m)
        pts.append(pts[-1] + (m.to_3x3() @ Vector((0, 0, -1))) * THUMB_LEN[i])
    return (pts, rots, THUMB_R)


def _fit_thumb():
    """Pointing: the thumb's turn and curl that put its pad on the curled middle finger's middle bone, on the side
    toward the thumb and a little above, its own bones clear of the other fingers."""
    pose = POSES["point"]
    pose["thumb_rot"] = (0.0, 0.0, 0.0)
    ch = chains("point")
    mp, _, mr = ch["middle"]
    target = (mp[1] + mp[2]) * 0.5 + Vector((-mr * 0.9, mr * 0.5, 0.0))
    best = None
    for yi in range(-12, 9):
        for pi in range(-12, 6):
            for ri in (-0.7, -0.4, -0.1):
                for k in (0.6, 1.0, 1.4):
                    b = tuple(x * k for x in pose["thumb"])
                    pts, rots, r = thumb(yi * 0.1, ri, pi * 0.1, b)
                    tip = pts[2] + (pts[3] - pts[2]) * 0.6          # (the pad, short of the very tip)
                    cost = (tip - target).length
                    if best is None or cost < best[0]:
                        best = (cost, (yi * 0.1, ri, pi * 0.1), b)
    pose["thumb_rot"] = best[1]
    pose["thumb"] = best[2]
    print("thumb fit: %.1f mm off, turn %s, bends %s" % (best[0] * 1000, best[1], tuple(round(x, 2) for x in best[2])))


_fit_thumb()


# ---------------------------------------------------------------- shapes (Godot coordinates), joined, remeshed

bm = bmesh.new()


def ring(c, x_axis, y_axis, rx, ry, n=20):
    return [c + x_axis * (math.cos(a) * rx) + y_axis * (math.sin(a) * ry) for a in (i * 2 * math.pi / n for i in range(n))]


def tube(points, radii, flat=0.86, cap_tip=True):
    """A tube swept through points, its radius from radii (one per point, interpolated), its section a little flatter
    on the palm side, a rounded end at the last point and the first."""
    n = 20
    samples = []
    for i in range(len(points) - 1):
        a, b = points[i], points[i + 1]
        steps = max(2, int((b - a).length / 0.0018))
        for s in range(steps):
            t = s / steps
            samples.append((a.lerp(b, t), radii[i] + (radii[i + 1] - radii[i]) * t, (b - a).normalized()))
    samples.append((points[-1], radii[-1], (points[-1] - points[-2]).normalized()))
    rings = []
    up = Vector((0, 1, 0))
    for p, r, d in samples:
        x = d.cross(up)
        if x.length < 1e-4:
            x = Vector((1, 0, 0))
        x.normalize()
        y = x.cross(d).normalized()
        rings.append(ring(p, x, y, r, r * flat, n))
    # rounded ends: rings shrinking on a quarter circle
    def cap(p, r, d, sign):
        x = d.cross(up)
        x = x.normalized() if x.length > 1e-4 else Vector((1, 0, 0))
        y = x.cross(d).normalized()
        out = []
        for k in range(1, 6):
            a = k / 6 * math.pi / 2
            out.append(ring(p + d * (sign * math.sin(a) * r), x, y, r * math.cos(a), r * flat * math.cos(a), n))
        return out, p + d * (sign * r)
    end_rings, tip = cap(samples[-1][0], samples[-1][1], samples[-1][2], 1)
    start_rings, root = cap(samples[0][0], samples[0][1], samples[0][2], -1)
    allr = list(reversed(start_rings)) + rings + end_rings
    vs = [[bm.verts.new(B(p)) for p in rr] for rr in allr]
    for i in range(len(vs) - 1):
        for j in range(n):
            bm.faces.new((vs[i][j], vs[i][(j + 1) % n], vs[i + 1][(j + 1) % n], vs[i + 1][j]))
    vt = bm.verts.new(B(tip))
    vr = bm.verts.new(B(root))
    for j in range(n):
        bm.faces.new((vs[-1][j], vs[-1][(j + 1) % n], vt))
        bm.faces.new((vs[0][(j + 1) % n], vs[0][j], vr))


def blob(c, r):
    """An ellipsoid (centre, semi-axes), Godot axes."""
    m = bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=1.0)
    for v in m["verts"]:
        g = GV(v.co)
        v.co = B(Vector((c.x + g.x * r.x, c.y + g.y * r.y, c.z + g.z * r.z)))


rest = chains("open")
for name, (pts, rots, r) in rest.items():
    # from inside the palm to the tip; a little wider at the joints
    base = pts[0] + (rots[0].to_3x3() @ Vector((0, 0, 1))) * (0.02 if name != "thumb" else 0.006)
    radii = [r * 1.08, r * 1.04, r * 0.97, r * 0.9, r * 0.8]
    tube([base] + pts, radii)
    if name != "thumb":
        blob(pts[0] + Vector((0, r * 0.15, 0.004)), Vector((r * 0.95, r * 0.75, r * 1.2)))     # the knuckle
# the palm: rounded, a little arched across, thicker at the heel and at the thumb's ball (long ellipsoids, much overlapped:
# a stack of short ones left ridges)
blob(Vector((0.0, 0.0, -0.05)), Vector((0.039, 0.0135, 0.052)))
blob(Vector((0.0, 0.001, -0.086)), Vector((0.037, 0.011, 0.018)))
blob(Vector((0.0, -0.002, -0.014)), Vector((0.03, 0.014, 0.022)))
blob(Vector((0.0, -0.003, 0.006)), Vector((0.03, 0.0145, 0.02)))           # (the wrist into the heel: no step)
blob(Vector((-0.022, -0.009, -0.03)), Vector((0.018, 0.013, 0.026)))      # the thumb's ball
blob(Vector((0.024, -0.007, -0.03)), Vector((0.012, 0.011, 0.03)))        # the outer heel
# the wrist and the forearm, back into the sleeve
tube([Vector((0, -0.002, 0.004)), Vector((0, -0.003, 0.08)), Vector((0, -0.004, 0.2))], [0.0255, 0.028, 0.033], flat=0.72)
# the nails: thin plates on the backs of the last bones
for name, (pts, rots, r) in rest.items():
    m3 = rots[2].to_3x3()
    d = m3 @ Vector((0, 0, -1))
    upn = m3 @ Vector((0, 1, 0))
    c = pts[3] - d * 0.007 + upn * (r * 0.78)
    m = bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=8, radius=1.0)
    xa = d.cross(upn).normalized()
    for v in m["verts"]:
        g = GV(v.co)
        p = c + xa * (g.x * r * 0.72) + upn * (g.y * 0.0012) + d * (-g.z * 0.0068)
        v.co = B(p)

me = bpy.data.meshes.new("hand_raw")
bm.to_mesh(me)
bm.free()
hand = bpy.data.objects.new("hand", me)
coll.objects.link(hand)
rm = hand.modifiers.new("remesh", "REMESH")
rm.mode = "VOXEL"
rm.voxel_size = 0.0007
rm.adaptivity = 0.0
sm = hand.modifiers.new("smooth", "CORRECTIVE_SMOOTH")
sm.iterations = 25
sm.smooth_type = "SIMPLE"
dg = bpy.context.evaluated_depsgraph_get()
me2 = bpy.data.meshes.new_from_object(hand.evaluated_get(dg))
hand.modifiers.clear()
hand.data = me2
dec = hand.modifiers.new("dec", "DECIMATE")
dec.ratio = 0.07
dg = bpy.context.evaluated_depsgraph_get()
me3 = bpy.data.meshes.new_from_object(hand.evaluated_get(dg))
hand.modifiers.clear()
hand.data = me3
for p in me3.polygons:
    p.use_smooth = True
print("hand: %d vertices, %d faces" % (len(me3.vertices), len(me3.polygons)))

# ---------------------------------------------------------------- skinning: each point between the bones near it

def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-12)))
    return (p - (a + ab * t)).length, t


BONES = []          # (finger, index or -1 for the palm, a, b)
for name, (pts, rots, r) in rest.items():
    for i in range(3):
        BONES.append((name, i, pts[i], pts[i + 1], r))


def weights(p):
    """[(bone, weight)]: the palm unless near a finger; between a finger's bones near their joint."""
    best = []
    for bi, (name, i, a, b, r) in enumerate(BONES):
        d, t = seg_dist(p, a, b)
        best.append((d - r, bi, t))
    best.sort()
    d0, b0, t0 = best[0]
    name, i, a, b, r = BONES[b0]
    if d0 > 0.012:
        return [(-1, 1.0)]
    out = []
    # across a joint: share with the bone before (t near 0) - the first bone shares with the palm
    blend = 0.25
    if t0 < blend:
        k = 0.5 + 0.5 * (t0 / blend)
        prev = b0 - 1 if i > 0 else -1
        out = [(b0, k), (prev, 1.0 - k)]
    elif t0 > 1.0 - blend and i < 2:
        k = 0.5 + 0.5 * ((1.0 - t0) / blend)
        out = [(b0, k), (b0 + 1, 1.0 - k)]
    else:
        out = [(b0, 1.0)]
    # far from the finger's line (in the palm): toward the palm
    if d0 > 0.002:
        f = min(1.0, (d0 - 0.002) / 0.01)
        out = [(bb, w * (1.0 - f)) for bb, w in out] + [(-1, f)]
    return out


def posed(pose):
    ch = chains(pose)
    mats = []
    for name, i, a, b, r in BONES:
        rp, rr, _ = rest[name]
        pp, pr, _ = ch[name]
        # rest -> bone space -> posed: about the bone's own start
        m = Matrix.Translation(pp[i]) @ pr[i] @ rr[i].inverted() @ Matrix.Translation(-rp[i])
        mats.append(m)
    return mats


W = [weights(GV(v.co)) for v in me3.vertices]


def pose_points(pose):
    mats = posed(pose)
    out = []
    for v, ws in zip(me3.vertices, W):
        g = GV(v.co)
        acc = Vector((0, 0, 0))
        for bi, w in ws:
            acc += (g if bi < 0 else mats[bi] @ g) * w
        out.append(acc)
    return out


# ---------------------------------------------------------------- colour

SKIN = Vector((0.80, 0.60, 0.48))           # sRGB, a light-medium skin
WARM = Vector((0.80, 0.50, 0.42))
PALM = Vector((0.86, 0.68, 0.58))
NAIL = Vector((0.88, 0.72, 0.68))
NAIL_EDGE = Vector((0.95, 0.9, 0.84))


def colour(g, n):
    c = SKIN.copy()
    if n.y < -0.2:
        c = c.lerp(PALM, min(1.0, (-n.y - 0.2) * 1.5))
    # warmer at the knuckles and the ends of the fingers
    for name, (pts, rots, r) in rest.items():
        for j in (0, 1, 2, 3):
            d = (g - pts[j]).length
            if d < r * 1.6:
                c = c.lerp(WARM, 0.35 * (1.0 - d / (r * 1.6)))
        # the nail: on the back of the last bone, near the tip
        m3 = rots[2].to_3x3()
        upn = m3 @ Vector((0, 1, 0))
        dd = m3 @ Vector((0, 0, -1))
        rel = g - pts[3]
        along = rel.dot(dd)
        if n.dot(upn) > 0.55 and -0.013 < along < 0.0015 and abs(rel.dot(dd.cross(upn).normalized())) < r * 0.7:
            c = NAIL_EDGE if along > -0.0025 else NAIL
    return (c.x, c.y, c.z, 0.0)


def write(path, pts, normals_from, cols):
    me3.vertices.foreach_set("co", [x for p in pts for x in B(p)])
    me3.update()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tri = []
    for p in me3.polygons:
        vs = list(p.vertices)
        for k in range(1, len(vs) - 1):
            tri += [vs[0], vs[k + 1], vs[k]]          # (Godot's winding)
    with open(path, "wb") as fh:
        fh.write(b"ANTM")
        fh.write(struct.pack("<II", len(pts), len(tri)))
        for v, c in zip(me3.vertices, cols):
            g = GV(v.co)
            n = GV(v.normal)
            fh.write(struct.pack("<10f", g.x, g.y, g.z, n.x, n.y, n.z, *c))
        fh.write(struct.pack("<%dI" % len(tri), *tri))
    print("  %s: %d vertices, %d triangles" % (os.path.basename(path), len(pts), len(tri) // 3))


rest_pts = [GV(v.co) for v in me3.vertices]
cols = [colour(GV(v.co), GV(v.normal)) for v in me3.vertices]
open_pts = pose_points("open")
point_pts = pose_points("point")
write(OUT + "/hand_point.antmesh", point_pts, None, cols)
write(OUT + "/hand_open.antmesh", open_pts, None, cols)
if globals().get("POSE", "open") == "point":                  # (POSE=point: the object left pointing, to look at)
    me3.vertices.foreach_set("co", [x for p in point_pts for x in B(p)])
    me3.update()

# ---------------------------------------------------------------- the sleeve: knit, a ribbed cuff at the wrist

bm = bmesh.new()
n = 36
rings = []
for k in range(15):
    z = 0.028 + k * 0.016
    cuff = k < 3
    rx = 0.036 + k * 0.0012 + (0.0 if cuff else 0.004)
    ry = 0.031 + k * 0.001 + (0.0 if cuff else 0.003)
    rr = []
    for j in range(n):
        a = j * 2 * math.pi / n
        rib = 0.0012 * math.cos(a * 18) if cuff else 0.0
        fold = 0.0 if cuff else 0.0018 * math.sin(a * 5 + k * 1.3) * math.sin(k * 0.9)
        rr.append(bm.verts.new(B(Vector((math.cos(a) * (rx + rib + fold), -0.004 + math.sin(a) * (ry + rib + fold), z)))))
    rings.append(rr)
for k in range(len(rings) - 1):
    for j in range(n):
        bm.faces.new((rings[k][j], rings[k + 1][j], rings[k + 1][(j + 1) % n], rings[k][(j + 1) % n]))
# the cuff's edge turned in
inner = [bm.verts.new(B(Vector((v.co.x * 0.86, 0, 0)) + Vector((0, 0, 0)))) for v in rings[0]]
for j, v in enumerate(rings[0]):
    g = GV(v.co)
    inner[j].co = B(Vector((g.x * 0.88, -0.004 + (g.y + 0.004) * 0.88, g.z + 0.006)))
for j in range(n):
    bm.faces.new((inner[j], rings[0][j], rings[0][(j + 1) % n], inner[(j + 1) % n]))
sme = bpy.data.meshes.new("sleeve")
bm.to_mesh(sme)
bm.free()
sl = bpy.data.objects.new("sleeve", sme)
coll.objects.link(sl)
sub = sl.modifiers.new("sub", "SUBSURF")
sub.levels = 1
dg = bpy.context.evaluated_depsgraph_get()
sme2 = bpy.data.meshes.new_from_object(sl.evaluated_get(dg))
sl.modifiers.clear()
sl.data = sme2
for p in sme2.polygons:
    p.use_smooth = True
KNIT = Vector((0.86, 0.82, 0.72))
tri = []
for p in sme2.polygons:
    vs = list(p.vertices)
    for k in range(1, len(vs) - 1):
        tri += [vs[0], vs[k + 1], vs[k]]
with open(OUT + "/sleeve.antmesh", "wb") as fh:
    fh.write(b"ANTM")
    fh.write(struct.pack("<II", len(sme2.vertices), len(tri)))
    for v in sme2.vertices:
        g = GV(v.co)
        nn = GV(v.normal)
        shade = 0.92 + 0.08 * math.sin(math.atan2(g.y + 0.004, g.x) * 36) if g.z < 0.075 else 1.0
        c = KNIT * shade
        fh.write(struct.pack("<10f", g.x, g.y, g.z, nn.x, nn.y, nn.z, c.x, c.y, c.z, 0.0))
    fh.write(struct.pack("<%dI" % len(tri), *tri))
print("  sleeve.antmesh: %d vertices, %d triangles" % (len(sme2.vertices), len(tri) // 3))

# a preview material from the vertex colour
mat = bpy.data.materials.get("hand_preview") or bpy.data.materials.new("hand_preview")
mat.use_nodes = True
nt = mat.node_tree
bsdf = next(nd for nd in nt.nodes if nd.type == "BSDF_PRINCIPLED")
attr = next((nd for nd in nt.nodes if nd.type == "VERTEX_COLOR"), None) or nt.nodes.new("ShaderNodeVertexColor")
nt.links.new(attr.outputs[0], bsdf.inputs[0])
for o in (hand, sl):
    if not o.data.color_attributes:
        o.data.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    o.data.materials.clear()
    o.data.materials.append(mat)
ca = hand.data.color_attributes[0]
for i, c in enumerate(cols):
    ca.data[i].color = (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, 1.0)
sca = sl.data.color_attributes[0]
for i in range(len(sca.data)):
    sca.data[i].color = (0.86 ** 2.2, 0.82 ** 2.2, 0.72 ** 2.2, 1.0)
print("done")
