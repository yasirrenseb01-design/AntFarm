# Blender-side builder for the outworld props: black bean aphids, the house cricket carcass and
# broad bean shoots.  Run inside Blender:  python tools/blender/bl.py tools/blender/build_props.py WHAT=aphid
# (WHAT = aphid | cricket | plant [VARIANT=k STAGE=g] | spider | centipede | beetle | fly, optional SHOT=<png>).  Units are game units (1 = 1.5 mm), x forward,
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
OUT = globals().get("OUT", "E:/AntFarm/assets/models")      # files go to OUT/prey or OUT/plants
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

# =============================================================== the props, one file each (tools/blender/props/)
PROPS_DIR = os.path.join(os.path.dirname(globals().get("__file__", "")) or "E:/AntFarm/tools/blender", "props")
if not os.path.isdir(PROPS_DIR):
    PROPS_DIR = "E:/AntFarm/tools/blender/props"
for _name in ("aphid", "cricket", "plant", "spider", "centipede", "beetle", "fly"):
    with open(os.path.join(PROPS_DIR, _name + ".py"), encoding="utf-8") as _fh:
        exec(compile(_fh.read(), _name + ".py", "exec"), globals())


# =============================================================== run
if WHAT == "aphid":
    aphid(0, 0.0)
    aphid(1, 0.0)
    aphid(2, 0.0)
    export(OUT + "/prey/aphid_adult.antmesh", [0])
    export(OUT + "/prey/aphid_nymph.antmesh", [1])
    export(OUT + "/prey/aphid_winged.antmesh", [2])
    export(OUT + "/prey/aphid_wings.antmesh", [3])
    if SHOT:
        # spread them out for the picture
        for o in OBJS:
            o.location.y += {0: 0.0, 1: -1.6, 2: 1.8, 3: 1.8}[o["group"]]
        preview_material()
        render(SHOT, Vector((0, 0, 0.4)), 7.0, Vector((0.6, -0.9, 0.9)))
elif WHAT == "cricket":
    cricket()
    for g, name in ((0, "head"), (1, "abdomen"), (2, "hindleg_l"), (4, "hindleg_r"), (3, "legs")):
        export("%s/prey/cricket_%s.antmesh" % (OUT, name), [g])
    if SHOT:
        preview_material()
        view = {"top": Vector((0.0, -0.05, 1.0)), "side": Vector((0.0, -1.0, 0.1))}.get(globals().get("VIEW", ""), Vector((0.3, -1.0, 0.9)))
        render(SHOT, Vector((-1.0, 0, 1.5)), 30.0, view)
elif WHAT == "plant":
    k = int(globals().get("VARIANT", "0"))
    g = int(globals().get("STAGE", "3"))            # growth stage 0-3 (props/plant.py)
    stem = plant(k, g)
    flex_export("%s/plants/plant%d_%d.antmesh" % (OUT, k, g), stem)
    with open("%s/plants/plant%d_%d.json" % (OUT, k, g), "w") as fh:
        json.dump({"stem": stem, "radius": 0.55 * PL_STAGE_R[g]}, fh)
    if SHOT:
        preview_material()
        render(SHOT, Vector((0, 0, 13.0)), 75.0, Vector((0.8, -1.0, 0.35)))
elif WHAT == "spider":
    wolf_spider()
    export(OUT + "/creatures/wolf_spider.antmesh")
    if SHOT:
        preview_material()
        view = {"top": Vector((0.0, -0.05, 1.0)), "side": Vector((0.0, -1.0, 0.1))}.get(globals().get("VIEW", ""), Vector((0.6, -1.0, 0.8)))
        render(SHOT, Vector((-0.5, 0, 1.8)), 34.0, view)
elif WHAT == "centipede":
    centipede()
    export(OUT + "/creatures/centipede.antmesh")
    if SHOT:
        preview_material()
        view = {"top": Vector((0.0, -0.05, 1.0)), "side": Vector((0.0, -1.0, 0.1))}.get(globals().get("VIEW", ""), Vector((0.5, -1.0, 0.9)))
        render(SHOT, Vector((0.0, 0, 0.6)), 36.0, view)
elif WHAT == "beetle":
    ground_beetle()
    export(OUT + "/creatures/ground_beetle.antmesh")
    if SHOT:
        preview_material()
        view = {"top": Vector((0.0, -0.05, 1.0)), "side": Vector((0.0, -1.0, 0.1))}.get(globals().get("VIEW", ""), Vector((0.8, -1.0, 0.7)))
        render(SHOT, Vector((0.5, 0, 1.5)), 40.0, view)
elif WHAT == "fly":
    fly()
    export(OUT + "/prey/fly.antmesh", [0])
    export(OUT + "/prey/fly_wings.antmesh", [1])
    if SHOT:
        preview_material()
        view = {"top": Vector((0.0, -0.05, 1.0)), "side": Vector((0.0, -1.0, 0.1))}.get(globals().get("VIEW", ""), Vector((0.6, -1.0, 1.0)))
        render(SHOT, Vector((0.0, 0, 1.3)), 14.0, view)
