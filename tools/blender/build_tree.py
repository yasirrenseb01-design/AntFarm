# Blender-side builder for the leafy garden trees out of the Home's window (view/home/home_yard.gd; the keeper,
# 2026-10-27: "make the tree model again - it does not look real"). Run inside Blender:
#   python tools/blender/bl.py tools/blender/build_tree.py
# A broadleaf tree (lime / maple-like, ~6-7 m): a trunk flaring at its foot, forking into limbs that fork again and
# again, thinning and spreading as they go (each child about 0.7 its parent's length), drooping a little under their
# weight; at every twig's end a spray of leaves - small, flat, pointed leaf shapes turned every way but mostly facing
# out and up, their greens varying, the inner ones darker (shaded in the crown). Metres, Godot axes (y up), foot at the
# origin; exported as .antmesh (format: ant_model3d.gd load_antmesh), vertex colour sRGB, alpha = how far the wind may
# move that point (0 at the trunk .. 1 at the leaves' tips). Two of them (seeds) so neighbouring trees differ.
#   -> assets/models/trees/tree_a.antmesh, tree_b.antmesh
import bpy
import math
import os
import random
import struct
from mathutils import Vector, Matrix, Quaternion

OUT = globals().get("OUT", "E:/AntFarm/assets/models/trees")


def B(v):                      # Godot -> Blender (for the preview object)
    return Vector((v.x, -v.z, v.y))


class Mesh:
    def __init__(self):
        self.v = []            # (pos, normal, colour rgba)
        self.i = []

    def tube(self, a, b, ra, rb, col, wa, wb, n=8):
        d = (b - a).normalized()
        x = d.cross(Vector((0, 1, 0)))
        if x.length < 1e-3:
            x = Vector((1, 0, 0))
        x.normalize()
        y = d.cross(x).normalized()
        base = len(self.v)
        for k, (p, r, w) in enumerate(((a, ra, wa), (b, rb, wb))):
            for j in range(n):
                t = j / n * math.tau
                nrm = x * math.cos(t) + y * math.sin(t)
                shade = 0.85 + 0.15 * math.sin(t * 3.0 + p.x * 7.0)
                self.v.append((p + nrm * r, nrm, (col[0] * shade, col[1] * shade, col[2] * shade, w)))
        for j in range(n):
            j2 = (j + 1) % n
            self.i += [base + j, base + n + j, base + j2, base + j2, base + n + j, base + n + j2]

    def leaf(self, at, normal, along, size, col, w):
        side = normal.cross(along).normalized()
        L, W = size, size * 0.62
        pts = [at, at + along * (L * 0.35) + side * (W * 0.5), at + along * L, at + along * (L * 0.35) - side * (W * 0.5)]
        # a little fold along the middle
        pts[1] += normal * (W * 0.12)
        pts[3] += normal * (W * 0.12)
        base = len(self.v)
        for k, p in enumerate(pts):
            self.v.append((p, normal, (col[0], col[1], col[2], w if k != 0 else w * 0.85)))
        self.i += [base, base + 2, base + 1, base, base + 3, base + 2]
        # (two-sided: the material draws both faces)


def grow(m, rng, a, d, length, radius, depth, wind, twigs):
    b = a + d * length
    bark = (0.27, 0.22, 0.17) if depth > 1 else (0.32, 0.27, 0.2)
    m.tube(a, b, radius, radius * 0.68, bark, wind, min(1.0, wind + 0.18), 9 if depth > 2 else 6)
    if depth == 0:
        twigs.append((b, d))
        return
    kids = 3 if depth >= 3 else rng.choice((2, 3))
    for k in range(kids):
        # spread round the parent, opening out more on the outer limbs, a slight droop and a pull toward the light
        turn = Quaternion(d, (k / kids) * math.tau + rng.uniform(-0.5, 0.5))
        side = d.cross(Vector((0.31, 0.95, 0.07))).normalized()
        tilt = Quaternion(side, rng.uniform(0.45, 0.85) if depth < 4 else rng.uniform(0.35, 0.6))
        nd = (turn @ tilt @ d)
        nd = (nd + Vector((0, 0.25 if depth > 1 else -0.08, 0))).normalized()
        start = a.lerp(b, 1.0 if k == 0 else rng.uniform(0.75, 1.0))
        grow(m, rng, start, nd, length * rng.uniform(0.62, 0.78), radius * 0.62, depth - 1, min(1.0, wind + 0.2), twigs)


def tree(seed):
    rng = random.Random(seed)
    m = Mesh()
    # the trunk: a flared foot, then up to where it forks
    trunk_h = rng.uniform(2.1, 2.5)
    m.tube(Vector((0, -0.05, 0)), Vector((0, 0.35, 0)), 0.32, 0.2, (0.25, 0.2, 0.16), 0.0, 0.0, 12)
    lean = Vector((rng.uniform(-0.06, 0.06), 1.0, rng.uniform(-0.06, 0.06))).normalized()
    m.tube(Vector((0, 0.3, 0)), lean * trunk_h, 0.2, 0.16, (0.25, 0.2, 0.16), 0.0, 0.05, 12)
    twigs = []
    top = lean * trunk_h
    for k in range(4):
        turn = Quaternion(Vector((0, 1, 0)), k / 4 * math.tau + rng.uniform(-0.3, 0.3))
        d = (turn @ Quaternion(Vector((1, 0, 0)), rng.uniform(0.45, 0.7)) @ Vector((0, 1, 0))).normalized()
        grow(m, rng, top - lean * rng.uniform(0.0, 0.3), d, rng.uniform(1.4, 1.8), 0.11, 4, 0.08, twigs)
    # leaves: a spray at each twig's end
    centre = sum((t[0] for t in twigs), Vector()) / len(twigs)
    reach = max((t[0] - centre).length for t in twigs)
    for p, d in twigs:
        for n in range(110):
            off = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized() * rng.uniform(0.05, 0.6)
            at = p + off + d * 0.1
            out = (at - centre).normalized()
            normal = (out * 0.6 + Vector((0, 0.6, 0)) + Vector((rng.gauss(0, 0.5), rng.gauss(0, 0.5), rng.gauss(0, 0.5)))).normalized()
            along = normal.cross(Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))).normalized()
            inner = 1.0 - min(1.0, (at - centre).length / reach)
            g = rng.random()
            col = (0.17 + 0.1 * g, 0.32 + 0.14 * g, 0.1 + 0.05 * g)
            dark = 1.0 - 0.45 * inner
            m.leaf(at, normal, along, rng.uniform(0.13, 0.19), (col[0] * dark, col[1] * dark, col[2] * dark), 1.0)
    return m


def export(m, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(b"ANTM")
        fh.write(struct.pack("<II", len(m.v), len(m.i)))
        for p, n, c in m.v:
            fh.write(struct.pack("<10f", p.x, p.y, p.z, n.x, n.y, n.z, *c))
        fh.write(struct.pack("<%dI" % len(m.i), *m.i))
    print("  %s: %d vertices, %d triangles" % (os.path.basename(path), len(m.v), len(m.i) // 3))


scn = bpy.data.scenes.get("AntFarm") or bpy.data.scenes.new("AntFarm")
if bpy.context.window:
    bpy.context.window.scene = scn
coll = bpy.data.collections.get("trees")
if coll is None:
    coll = bpy.data.collections.new("trees")
    scn.collection.children.link(coll)
for o in list(coll.objects):
    bpy.data.objects.remove(o, do_unlink=True)
for c in scn.collection.children:
    c.hide_viewport = c != coll
    c.hide_render = c != coll
mat = bpy.data.materials.get("tree_preview") or bpy.data.materials.new("tree_preview")
mat.use_nodes = True
nt = mat.node_tree
bsdf = next(nd for nd in nt.nodes if nd.type == "BSDF_PRINCIPLED")
attr = next((nd for nd in nt.nodes if nd.type == "VERTEX_COLOR"), None) or nt.nodes.new("ShaderNodeVertexColor")
nt.links.new(attr.outputs[0], bsdf.inputs[0])
for k, (name, seed) in enumerate((("tree_a", 11), ("tree_b", 23))):
    m = tree(seed)
    export(m, "%s/%s.antmesh" % (OUT, name))
    me = bpy.data.meshes.new(name)
    me.from_pydata([B(p) for p, n, c in m.v], [], [tuple(m.i[j:j + 3]) for j in range(0, len(m.i), 3)])
    me.update()
    ca = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    for j, (p, n, c) in enumerate(m.v):
        ca.data[j].color = (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, 1.0)
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    o.location = (k * 9.0, 0, 0)
    coll.objects.link(o)
print("done")
