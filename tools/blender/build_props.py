# Blender-side builder for the outworld props: black bean aphids, the house cricket carcass and
# broad bean shoots.  Run inside Blender:  python tools/blender/bl.py tools/blender/build_props.py WHAT=aphid
# (WHAT = aphid | cricket | plant, optional SHOT=<png>).  Units are game units (1 = 1.5 mm), x forward,
# y up, z to the right (Godot axes); exported as .antmesh files (see ant_model3d.gd load_antmesh) whose
# vertex colour is sRGB and alpha is how far the wind may bend that point (plants) or 0.
import bpy
import bmesh
import json
import math
import os
import random
import struct
from mathutils import Vector, Matrix

WHAT = globals().get("WHAT", "aphid")
OUT = globals().get("OUT", "E:/AntFarm/assets/models")
SHOT = globals().get("SHOT", "")


def G(x, y, z):
    return Vector((x, -z, y))


def GV(v):
    return Vector((v.x, v.z, -v.y))


scn = bpy.data.scenes.get("AntFarm") or bpy.data.scenes.new("AntFarm")
if bpy.context.window:
    bpy.context.window.scene = scn
cname = "props_" + WHAT
coll = bpy.data.collections.get(cname)
if coll is None:
    coll = bpy.data.collections.new(cname)
    scn.collection.children.link(coll)
for o in list(coll.objects):
    bpy.data.objects.remove(o, do_unlink=True)
for c in scn.collection.children:
    c.hide_render = c != coll
    c.hide_viewport = c != coll

OBJS = []


def _obj(name, me, group, colfn, flat=False):
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)
    o["group"] = group
    o["flat"] = flat
    o["colfn"] = len(COLFNS)
    COLFNS.append(colfn)
    for p in me.polygons:
        p.use_smooth = not flat
    OBJS.append(o)
    return o


COLFNS = []


def const(c, a=0.0):
    return lambda g, n: (c[0], c[1], c[2], a)


def _bake(o):
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
    o.modifiers.clear()
    old = o.data
    o.data = me
    bpy.data.meshes.remove(old)


def blobs(name, items, group, colfn, voxel, smooth=6, faces=1500, carvefn=None):
    bm = bmesh.new()
    for c, r, rot in items:
        geom = bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=16, radius=1.0)
        m = Matrix.Translation(G(*c)) @ rot @ Matrix.Diagonal((r[0], r[2], r[1], 1.0))
        bmesh.ops.transform(bm, matrix=m, verts=geom["verts"])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = _obj(name, me, group, colfn)
    rm = o.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = voxel
    sm = o.modifiers.new("smooth", "SMOOTH")
    sm.factor = 0.6
    sm.iterations = smooth
    _bake(o)
    if carvefn:
        me = o.data
        for v in me.vertices:
            v.co += v.normal * carvefn(GV(v.co))
        me.update()
        sm = o.modifiers.new("smooth", "SMOOTH")
        sm.factor = 0.4
        sm.iterations = 2
        _bake(o)
    n = len(o.data.polygons)
    if n > faces:
        d = o.modifiers.new("dec", "DECIMATE")
        d.ratio = faces / n
        _bake(o)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def tube(name, pts, radii, group, colfn, segs=6, cap=True, square=False):
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
            ang = math.tau * k / segs + (math.pi / segs if square else 0.0)
            ca, sa = math.cos(ang), math.sin(ang)
            if square:
                # a rounded square section (the broad bean's four-angled stem)
                m = max(abs(ca), abs(sa))
                ca, sa = ca / m * 0.82 + ca * 0.18, sa / m * 0.82 + sa * 0.18
            ring.append(bm.verts.new(p + (n * ca + b * sa) * radii[i]))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(segs):
            k2 = (k + 1) % segs
            bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
    if cap:
        for ring, p, sgn, r in ((rings[0], pts[0], -1, radii[0]), (rings[-1], pts[-1], 1, radii[-1])):
            d = (pts[1] - pts[0]) if sgn < 0 else (pts[-1] - pts[-2])
            tip = bm.verts.new(p + d.normalized() * sgn * r * 0.6)
            for k in range(segs):
                k2 = (k + 1) % segs
                bm.faces.new((ring[k2], ring[k], tip) if sgn < 0 else (ring[k], ring[k2], tip))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return _obj(name, me, group, colfn)


def ell(name, c, r, group, colfn, segs=10, rot=Matrix.Identity(4)):
    bm = bmesh.new()
    geom = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=max(4, segs * 2 // 3), radius=1.0)
    m = Matrix.Translation(G(*c)) @ rot @ Matrix.Diagonal((r[0], r[2], r[1], 1.0))
    bmesh.ops.transform(bm, matrix=m, verts=geom["verts"])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return _obj(name, me, group, colfn)


def sheet(name, outline, xf, lift, group, colfn, thick=0.0, flat=False):
    """A leaf blade: outline (u, v) in its own plane, xf places it (Godot axes), lift(u, v) bends it."""
    bm = bmesh.new()
    tris = []
    # fan from the centroid gives an even triangulation for convex-ish leaf outlines
    cu = sum(p[0] for p in outline) / len(outline)
    cv = sum(p[1] for p in outline) / len(outline)
    pts = [(cu, cv)] + list(outline)
    for side, off in ((1, 0.0), (-1, -thick)):
        vs = []
        for u, v in pts:
            gp = xf @ Vector((u, lift(u, v) + off, v))
            vs.append(bm.verts.new(G(gp.x, gp.y, gp.z)))
        n = len(outline)
        for i in range(n):
            a, b = vs[1 + i], vs[1 + (i + 1) % n]
            bm.faces.new((vs[0], b, a) if side > 0 else (vs[0], a, b))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return _obj(name, me, group, colfn, flat)


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def export(path, groups=None, scale=1.0):
    verts = []
    idx = []
    for o in OBJS:
        if groups is not None and o["group"] not in groups:
            continue
        fn = COLFNS[o["colfn"]]
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        bm.normal_update()
        flat = o["flat"]
        shared = {}
        for f in bm.faces:
            tri = []
            for v in f.verts:
                if not flat and v.index in shared:
                    tri.append(shared[v.index])
                    continue
                n = f.normal if flat else v.normal
                g = GV(v.co)
                gn = GV(n)
                c = fn(g, gn)
                verts.append((g.x * scale, g.y * scale, g.z * scale, gn.x, gn.y, gn.z, c[0], c[1], c[2], c[3]))
                tri.append(len(verts) - 1)
                if not flat:
                    shared[v.index] = tri[-1]
            idx += [tri[0], tri[2], tri[1]]
        bm.free()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(b"ANTM")
        fh.write(struct.pack("<II", len(verts), len(idx)))
        for v in verts:
            fh.write(struct.pack("<10f", *v))
        fh.write(struct.pack("<%dI" % len(idx), *idx))
    print("  %s: %d vertices, %d triangles" % (os.path.basename(path), len(verts), len(idx) // 3))


def preview_material():
    mat = bpy.data.materials.get("prop_preview") or bpy.data.materials.new("prop_preview")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    attr = nt.nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.6
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    for o in OBJS:
        me = o.data
        if "Col" not in me.color_attributes:
            me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        attr_l = me.color_attributes["Col"]
        fn = COLFNS[o["colfn"]]
        for i, v in enumerate(me.vertices):
            c = fn(GV(v.co), GV(v.normal))
            # preview in linear light like the game does for sRGB vertex colours
            attr_l.data[i].color = (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, 1.0)
        me.materials.clear()
        me.materials.append(mat)


def render(path, target, dist, d=Vector((0.7, -1.0, 0.55)), lens=60):
    for n in ("cam", "key", "rim", "fill"):
        o = bpy.data.objects.get("pv_" + n)
        if o:
            bpy.data.objects.remove(o, do_unlink=True)
    cam = bpy.data.objects.new("pv_cam", bpy.data.cameras.new("pv_cam"))
    scn.collection.objects.link(cam)
    cam.location = target + d.normalized() * dist
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    scn.camera = cam
    for n, loc, e in (("key", (4, -5, 7), 900), ("rim", (-6, 4, 4), 600), ("fill", (2, 6, -1), 150)):
        L = bpy.data.objects.new("pv_" + n, bpy.data.lights.new("pv_" + n, "AREA"))
        L.data.energy = e * dist * dist / 400.0
        L.data.size = dist * 0.3
        L.location = target + Vector(loc) * dist / 8.0
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
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True, scene=scn.name)
    print("rendered", path)


# =============================================================== black bean aphid (Aphis fabae)
# Facing +x, back up (+y), legs down; about 1.35 units (2 mm) long for an adult.

def aphid(kind, ox):
    """kind 0 wingless adult, 1 nymph, 2 winged adult; built at x offset ox, group = kind."""
    s = 1.0 if kind != 1 else 0.6
    body = (0.17, 0.18, 0.2) if kind != 1 else (0.3, 0.31, 0.32)

    def body_col(g, n):
        # matt dark olive-black; transverse rows of white wax flecks on the back of the abdomen
        x = (g.x - ox) / s
        c = list(body)
        if n.y > 0.35 and -0.75 < x < 0.3:
            row = math.cos((x + 0.1) * math.pi / 0.22)
            if row > 0.55 and abs(math.sin(g.z / s * 14.0)) > 0.35:
                k = (row - 0.55) / 0.45 * (1.3 if kind == 1 else 1.0)
                c = [ci + (0.78 - ci) * min(1.0, k) for ci in c]
        return (c[0], c[1], c[2], 0.0)

    def X(x, y, z):
        return (ox + x * s, y * s, z * s)

    abd_items = [
        (X(-0.15, 0.42, 0), (0.62 * s, 0.42 * s, 0.46 * s), Matrix.Identity(4)),
        (X(0.42, 0.42, 0), (0.32 * s, 0.28 * s, 0.32 * s), Matrix.Identity(4)),       # thorax
        (X(0.72, 0.38, 0), (0.18 * s, 0.18 * s, 0.21 * s), Matrix.Identity(4)),       # head
    ]
    if kind == 2:
        abd_items[1] = (X(0.4, 0.5, 0), (0.36 * s, 0.34 * s, 0.33 * s), Matrix.Identity(4))
        abd_items[0] = (X(-0.2, 0.4, 0), (0.55 * s, 0.36 * s, 0.4 * s), Matrix.Identity(4))
    blobs("aphid_body", abd_items, kind, body_col, 0.018 * s, 5, 1400,
        carvefn=lambda g: -0.012 * s * max(0.0, math.cos(((g.x - ox) / s + 0.1) * math.pi / 0.2)) if g.y > 0.45 * s else 0.0)
    pale = (0.72, 0.72, 0.6)
    dark = (0.08, 0.08, 0.08)

    def leg_col(t):
        # pale legs with dark knees and feet
        return lambda g, n: (dark if False else pale) + (0.0,)

    for side in (-1, 1):
        ell("eye", X(0.8, 0.46, 0.15 * side), (0.06 * s, 0.065 * s, 0.05 * s), kind, const((0.3, 0.05, 0.03)), 8)
        # six-segmented antennae, about two thirds of the body, swept back over the back
        ant = [X(0.85, 0.5, 0.07 * side), X(0.98, 0.68, 0.18 * side), X(0.8, 0.88, 0.32 * side), X(0.35, 0.95, 0.42 * side),
            X(-0.15, 0.88, 0.48 * side), X(-0.45, 0.8, 0.5 * side)]
        tube("antenna", ant, [0.024 * s, 0.022 * s, 0.02 * s, 0.018 * s, 0.016 * s, 0.012 * s], kind,
            lambda g, n: ((0.18, 0.18, 0.16, 0.0) if (g.x - ox) / s < -0.2 else (0.68, 0.68, 0.56, 0.0)), 5)
        # siphunculi (cornicles): black tubes on the back of the abdomen, and the finger-like cauda
        tube("cornicle", [X(-0.5, 0.62, 0.17 * side), X(-0.6, 0.68, 0.2 * side), X(-0.7, 0.71, 0.22 * side)],
            [0.04 * s, 0.035 * s, 0.03 * s], kind, const(dark), 6)
        for li, x in enumerate((0.52, 0.38, 0.2)):
            hip = X(x, 0.24, 0.16 * side)
            knee = X(x + (0.1 if li < 2 else -0.15), 0.5, (0.62 + 0.1 * li) * side)
            foot = X(x + (0.18 if li < 2 else -0.35), 0.0, (0.82 + 0.12 * li) * side)
            tube("femur", [hip, knee], [0.035 * s, 0.03 * s], kind, const((0.3, 0.29, 0.24)), 5)
            tube("tibia", [knee, lerp(knee, foot, 0.85)], [0.028 * s, 0.024 * s], kind, const(pale), 5)
            tube("tarsus", [lerp(knee, foot, 0.85), foot], [0.024 * s, 0.015 * s], kind, const(dark), 4)
    tube("cauda", [X(-0.75, 0.38, 0), X(-0.88, 0.4, 0)], [0.05 * s, 0.03 * s], kind, const(dark), 6)
    # the beak: a jointed rostrum folded back under the body (in the plant while feeding)
    tube("rostrum", [X(0.8, 0.22, 0), X(0.55, 0.08, 0), X(0.2, 0.02, 0)], [0.03 * s, 0.025 * s, 0.015 * s], kind, const((0.25, 0.24, 0.2)), 5)
    if kind == 2:
        for side in (-1, 1):
            outline = []
            for j in range(16):
                a = math.tau * j / 16
                outline.append((math.cos(a) * 0.95 - 0.75, math.sin(a) * 0.3))
            xf = Matrix.Translation(Vector(X(0.45, 0.78, 0.1 * side))) @ Matrix.Rotation(-0.2 * side, 4, "Y") @ Matrix.Diagonal((s, s, s * side, 1))
            o = sheet("wing", outline, xf, lambda u, v: -0.04 * u, 3, const((0.9, 0.93, 1.0)), 0.0, True)
            # wing veins: the dark pterostigma near the front edge
            ell("stigma", X(0.05, 0.84, (0.12 + 0.22) * side), (0.18 * s, 0.01, 0.03 * s), 3, const((0.15, 0.15, 0.13)), 6)


# =============================================================== house cricket (Acheta domesticus)
# A dead female lying slightly on its side, facing +x, ~13 units (20 mm) long. Exported in pieces so
# the game can deflate the abdomen and let a hind leg fall off as the ants hollow it out:
# 0 head + pronotum + antennae, 1 abdomen + wings + cerci + ovipositor, 2/4 left/right hind leg, 3 fore/mid legs.

TAN = (0.5, 0.39, 0.25)
DARKB = (0.18, 0.12, 0.07)


def cricket_col(g, n):
    c = list(TAN)
    dark = 0.0
    x = g.x
    if x > 3.0:                                                    # head: dark band between the eyes, pale face
        dark = max(dark, math.exp(-((x - 4.15) / 0.35) ** 2) * (1.0 if g.y > 2.1 else 0.0))
        dark = max(dark, 0.6 * math.exp(-((g.y - 2.6) / 0.25) ** 2) * math.exp(-((x - 3.5) / 0.4) ** 2))
    elif x > 0.6:                                                  # pronotum: two dark blotches on the disc
        dark = max(dark, math.exp(-((x - 2.1) / 0.5) ** 2) * math.exp(-((abs(g.z) - 0.6) / 0.3) ** 2) * (1.0 if g.y > 2.6 else 0.0))
        dark = max(dark, 0.5 * math.exp(-((x - 0.85) / 0.15) ** 2))
    else:                                                          # abdomen: dark hind edge on each plate
        ph = ((x + 0.4) / 0.95) % 1.0
        dark = max(dark, 0.75 * math.exp(-((ph - 0.08) / 0.08) ** 2) * (1.0 if n.y > -0.2 else 0.3))
    k = min(1.0, dark)
    return (c[0] + (DARKB[0] - c[0]) * k, c[1] + (DARKB[1] - c[1]) * k, c[2] + (DARKB[2] - c[2]) * k, 0.0)


def cricket():
    flat = Matrix.Identity(4)
    blobs("abdomen", [
        (( -1.6, 1.6, 0), (3.6, 1.35, 1.55), flat),
        (( 0.5, 1.75, 0), (1.2, 1.3, 1.4), flat),
    ], 1, cricket_col, 0.09, 6, 2200,
        carvefn=lambda g: (-0.07 * math.exp(-((((g.x + 0.4) / 0.95) % 1.0 - 0.02) / 0.06) ** 2)) if g.x < 0.4 else 0.0)
    blobs("pronotum", [((2.0, 1.85, 0), (1.45, 1.25, 1.45), flat), ((2.0, 2.4, 0), (1.3, 0.7, 1.35), flat)], 0, cricket_col, 0.08, 6, 1200)
    blobs("head", [((3.75, 1.75, 0), (1.15, 1.2, 1.2), flat), ((4.6, 1.2, 0), (0.6, 0.65, 0.8), flat)], 0, cricket_col, 0.07, 6, 1200)
    for side in (-1, 1):
        ell("eye", (4.25, 2.2, 0.85 * side), (0.38, 0.42, 0.3), 0, const((0.05, 0.04, 0.03)), 12)
        # filiform antennae, longer than the body
        pts = [(4.7, 2.45, 0.35 * side)]
        for i in range(1, 9):
            t = i / 8.0
            pts.append((4.7 + 13.0 * t, 2.45 + 1.2 * math.sin(t * 2.2) - 2.2 * t * t, (0.35 + 4.6 * t) * side))
        tube("antenna", pts, [0.07 - 0.04 * i / 8.0 for i in range(9)], 0, const((0.42, 0.32, 0.2)), 4, cap=False)
        # mouthparts: palps
        tube("palp", [(4.8, 0.95, 0.35 * side), (5.2, 0.55, 0.55 * side), (5.3, 0.15, 0.5 * side)], [0.1, 0.08, 0.07], 0, const(TAN), 5)
        # cerci: long, pale, tapering
        tube("cercus", [(-4.9, 1.75, 0.3 * side), (-6.6, 1.65, 1.0 * side), (-8.2, 1.5, 1.5 * side)], [0.12, 0.08, 0.03], 1, const((0.56, 0.45, 0.3)), 5)
        # forewings: short, veined wing pads over the back of the abdomen
        outline = [(0.0, 0.0), (-1.5, 0.25), (-3.6, 0.35), (-4.4, 0.1), (-4.2, -0.6), (-2.0, -1.05), (0.0, -0.9)]
        xf = Matrix.Translation(Vector((0.7, 2.85, 0.0))) @ Matrix.Diagonal((1, 1, side, 1))
        sheet("forewing", outline, xf, lambda u, v: -0.18 * v * v, 1,
            lambda g, n: (0.42, 0.33, 0.21, 0.0) if abs(math.sin(g.x * 3.2 + g.z * 2.0)) > 0.9 else (0.52, 0.42, 0.28, 0.0), 0.05)
        # hind leg: a massive femur striped with dark chevrons, a spiny tibia, three tarsal segments
        fem = [(0.6, 1.9, 1.5 * side), (-0.6, 2.3, 1.85 * side), (-2.2, 2.0, 2.0 * side), (-3.4, 1.35, 2.05 * side)]
        hg = 2 if side < 0 else 4                                    # each hind leg its own piece: it can come off
        tube("hind_femur", fem, [0.42, 0.62, 0.48, 0.25], hg,
            lambda g, n: (DARKB + (0.0,)) if (math.sin((g.x + g.y * 0.8) * 4.2) > 0.75 and n.y > -0.3) else (0.58, 0.46, 0.3, 0.0), 8)
        knee = (-3.4, 1.35, 2.05 * side)
        heel = (-5.7, 0.28, 2.35 * side)
        tube("hind_tibia", [knee, lerp(knee, heel, 0.5), heel], [0.2, 0.17, 0.15], hg, const((0.56, 0.44, 0.29)), 6)
        for row in (-1, 1):
            for sp in range(5):
                at = lerp(knee, heel, 0.25 + sp * 0.15)
                tube("spine", [at, (at[0] - 0.12, at[1] + 0.5, at[2] + 0.18 * side * row)], [0.05, 0.01], hg, const((0.66, 0.55, 0.38)), 4, cap=False)
        tars = [heel, (-6.3, 0.12, 2.6 * side), (-6.9, 0.05, 2.75 * side), (-7.3, 0.0, 2.8 * side)]
        tube("hind_tarsus", tars, [0.14, 0.12, 0.1, 0.06], hg, const((0.52, 0.41, 0.27)), 5)
        for li, x in enumerate((3.0, 1.4)):
            hip = (x, 1.0, 0.9 * side)
            k_ = (x + 0.6, 0.75, 2.0 * side)
            f_ = (x + 1.1, 0.05, 2.7 * side)
            tube("leg", [hip, k_], [0.22, 0.17], 3, const((0.55, 0.43, 0.28)), 6)
            tube("leg", [k_, lerp(k_, f_, 0.8), f_], [0.14, 0.12, 0.08], 3, const((0.52, 0.41, 0.27)), 5)
    tube("ovipositor", [(-4.7, 1.45, 0), (-6.5, 1.45, 0), (-8.1, 1.6, 0)], [0.12, 0.1, 0.07], 1, const((0.15, 0.1, 0.06)), 6)


# =============================================================== broad bean shoot (Vicia faba)
# Square, slightly glaucous stem with nodes, alternate compound leaves (2-3 pairs of oval leaflets),
# a growing tip of folded young leaves, a few white flowers with the black blotch on the wings.
# Exported per variant with its stem line (assets/models/plant<k>.json) so aphids and ants sit on it.

def plant(variant):
    rng = random.Random(1000 + variant)
    h = rng.uniform(22.0, 28.0)
    lean = Vector((rng.uniform(-1.6, 1.6), 0, rng.uniform(-1.6, 1.6)))
    stem_pts = []
    for i in range(9):
        t = i / 8.0
        p = Vector((0, h * t, 0)) + lean * t * t
        stem_pts.append((p.x, p.y, p.z))
    R = 0.55
    tube("stem", stem_pts, [R * (1.0 - 0.3 * i / 8.0) for i in range(9)], 0,
        lambda g, n: (0.33, 0.45, 0.24, 0.0), 8, cap=True, square=True)

    def stem_at(y):
        for i in range(len(stem_pts) - 1):
            a, b = stem_pts[i], stem_pts[i + 1]
            if y <= b[1] or i == len(stem_pts) - 2:
                return lerp(a, b, max(0.0, min(1.0, (y - a[1]) / max(0.001, b[1] - a[1]))))
        return stem_pts[-1]

    def leaf_col(base, tip_len):
        def f(g, n):
            return (base[0], base[1], base[2], 0.0)
        return f

    nodes = 5
    for nd in range(nodes):
        y = h * (0.16 + 0.72 * nd / (nodes - 1))
        at = stem_at(y)
        ang = nd * 2.4 + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(ang), 0, math.sin(ang)))
        size = 1.0 - 0.45 * nd / nodes
        # stipules: small toothed ears at the node
        ell("node", at, (R * 1.3, R * 0.9, R * 1.3), 0, const((0.3, 0.42, 0.22)), 8)
        for sd in (-1, 1):
            sp = Vector(at) + d.cross(Vector((0, 1, 0))) * sd * 0.7 + Vector((0, 0.2, 0))
            ell("stipule", tuple(sp), (0.45, 0.12, 0.3), 0, const((0.36, 0.5, 0.26)), 8)
        tip = Vector(at) + d * 3.6 * size + Vector((0, 1.4 * size, 0))
        tube("petiole", [at, tuple(Vector(at).lerp(tip, 0.5) + Vector((0, 0.3, 0))), tuple(tip)], [0.22, 0.18, 0.12], 0, const((0.33, 0.46, 0.24)), 6, cap=False)
        base_col = (0.24 + rng.uniform(-0.02, 0.03), 0.38 + rng.uniform(-0.03, 0.03), 0.2)
        pairs = 3 if nd < 2 else 2
        for pr in range(pairs):
            base = Vector(at).lerp(tip, 0.4 + 0.6 * pr / max(1, pairs - 1)) + Vector((0, 0.08, 0))
            for sd in (-1, 1):
                la = ang + sd * 1.15 + rng.uniform(-0.15, 0.15)
                length = rng.uniform(4.2, 5.6) * size
                width = length * 0.36
                outline = []
                for j in range(20):
                    a = math.tau * j / 20
                    u = (math.cos(a) + 1.0) * 0.5 * length
                    v = math.sin(a) * width * (0.85 + 0.15 * math.cos(a))
                    outline.append((u, v))
                droop = rng.uniform(0.1, 0.4)
                xf = Matrix.Translation(base) @ Matrix.Rotation(-la, 4, "Y") @ Matrix.Rotation(droop, 4, "Z")
                L = length
                sheet("leaflet", outline, xf, lambda u, v, L=L, w=width: -u * u * 0.018 + abs(v) * 0.22 - (v / w) ** 2 * 0.05 * L, 0,
                    lambda g, n, c=base_col: (c[0] + 0.04 * n.y, c[1] + 0.05 * n.y, c[2], 0.0), 0.04)
        if nd >= 2 and rng.random() < 0.7:
            # a raceme of broad bean flowers in the leaf axil: white standard, black-blotched wings
            fb = Vector(at) + d * 1.0 + Vector((0, 0.8, 0))
            for fl in range(2):
                fp = fb + Vector((math.cos(ang + fl), 0.5 * fl, math.sin(ang + fl))) * 0.8
                ell("calyx", tuple(fp), (0.35, 0.25, 0.25), 0, const((0.36, 0.48, 0.28)), 8)
                ell("standard", tuple(fp + Vector((0, 0.35, 0)) + d * 0.3), (0.55, 0.5, 0.15), 0, const((0.93, 0.92, 0.88)), 10)
                for sd in (-1, 1):
                    wp = fp + d.cross(Vector((0, 1, 0))) * sd * 0.25 + d * 0.25
                    ell("wing_petal", tuple(wp), (0.35, 0.22, 0.12), 0, const((0.08, 0.07, 0.07)), 8)
    # the growing tip: young leaves still folded around the shoot
    top = Vector(stem_pts[-1])
    for i in range(4):
        a = i * 1.9
        ell("bud", tuple(top + Vector((math.cos(a) * 0.4, 0.5 + i * 0.35, math.sin(a) * 0.4))), (0.45, 1.3 - i * 0.2, 0.3),
            0, const((0.4, 0.55, 0.3)), 10, Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(0.3, 4, "X"))
    return stem_pts


def flex_export(path, stem):
    """Plants bend with the wind away from the stem: alpha = distance from the stem axis, capped."""
    def stem_axis(y):
        for i in range(len(stem) - 1):
            a, b = stem[i], stem[i + 1]
            if y <= b[1] or i == len(stem) - 2:
                return lerp(a, b, max(0.0, min(1.0, (y - a[1]) / max(0.001, b[1] - a[1]))))
        return stem[-1]
    for o in OBJS:
        fn = COLFNS[o["colfn"]]

        def wrap(g, n, fn=fn):
            c = fn(g, n)
            ax = stem_axis(g.y)
            d = math.hypot(g.x - ax[0], g.z - ax[2])
            return (c[0], c[1], c[2], max(0.0, min(0.4, (d - 0.8) * 0.08)))
        COLFNS[o["colfn"]] = wrap
    export(path)


# =============================================================== run

if WHAT == "aphid":
    aphid(0, 0.0)
    aphid(1, 0.0)
    aphid(2, 0.0)
    export(OUT + "/aphid_adult.antmesh", [0])
    export(OUT + "/aphid_nymph.antmesh", [1])
    export(OUT + "/aphid_winged.antmesh", [2])
    export(OUT + "/aphid_wings.antmesh", [3])
    if SHOT:
        # spread them out for the picture
        for o in OBJS:
            o.location.y += {0: 0.0, 1: -1.6, 2: 1.8, 3: 1.8}[o["group"]]
        preview_material()
        render(SHOT, Vector((0, 0, 0.4)), 7.0, Vector((0.6, -0.9, 0.9)))
elif WHAT == "cricket":
    cricket()
    for g, name in ((0, "head"), (1, "abdomen"), (2, "hindleg_l"), (4, "hindleg_r"), (3, "legs")):
        export("%s/cricket_%s.antmesh" % (OUT, name), [g])
    if SHOT:
        preview_material()
        view = {"top": Vector((0.0, -0.05, 1.0)), "side": Vector((0.0, -1.0, 0.1))}.get(globals().get("VIEW", ""), Vector((0.3, -1.0, 0.9)))
        render(SHOT, Vector((-1.0, 0, 1.5)), 30.0, view)
elif WHAT == "plant":
    k = int(globals().get("VARIANT", "0"))
    stem = plant(k)
    flex_export("%s/plant%d.antmesh" % (OUT, k), stem)
    with open("%s/plant%d.json" % (OUT, k), "w") as fh:
        json.dump({"stem": stem, "radius": 0.55}, fh)
    if SHOT:
        preview_material()
        render(SHOT, Vector((0, 0, 12.0)), 48.0, Vector((0.8, -1.0, 0.35)))
