# Part of tools/blender/build_ant.py (split out in v0.8.5; run by it inside Blender in order body,
# antennae, legs, setae, sharing its globals: VARIANT/LOD/QUEEN/HI, colours, tube/ellipsoid/blob_group, PARTS).
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
