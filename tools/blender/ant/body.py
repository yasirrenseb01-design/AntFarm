# Part of tools/blender/build_ant.py (split out in v0.8.5; run by it inside Blender in order body,
# antennae, legs, setae, sharing its globals: VARIANT/LOD/QUEEN/HI, colours, tube/ellipsoid/blob_group, PARTS).
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
