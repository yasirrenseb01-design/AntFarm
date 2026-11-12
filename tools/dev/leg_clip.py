"""How much of each creature's legs lies inside its body, at rest and through the walk (the shaders' own leg
rotations, shaders/creatures/*.gdshader). Counts leg vertices farther than FAR from their hip that are inside
the body mesh (vertical ray, even-odd). Reads assets/models/creatures/*.antmesh only.
Usage: python leg_clip.py <project root>"""
import struct, sys, math
import numpy as np

root = sys.argv[1]


def load(name):
    b = open("%s/assets/models/creatures/%s.antmesh" % (root, name), "rb").read()
    nv, ni = struct.unpack("<II", b[4:12])
    stride = 10 if b[:4] == b"ANTM" else 11
    v = np.frombuffer(b, dtype="<f4", count=nv * stride, offset=12).reshape(nv, stride)
    idx = np.frombuffer(b, dtype="<u4", count=ni, offset=12 + nv * stride * 4).reshape(-1, 3)
    return v[:, :3].astype(np.float64), np.rint(v[:, 9] * 16).astype(int), idx


def inside(P, V, T):
    """P (n,3) inside the closed mesh V,T? vertical ray up, even-odd, in chunks."""
    a, b, c = V[T[:, 0]], V[T[:, 1]], V[T[:, 2]]
    out = np.zeros(len(P), dtype=bool)
    for s in range(0, len(P), 400):
        p = P[s:s + 400]
        px, pz = p[:, 0:1], p[:, 2:3]
        d = (b[:, 2] - c[:, 2]) * (a[:, 0] - c[:, 0]) + (c[:, 0] - b[:, 0]) * (a[:, 2] - c[:, 2])
        d = np.where(np.abs(d) < 1e-12, 1e-12, d)
        w0 = ((b[:, 2] - c[:, 2]) * (px - c[:, 0]) + (c[:, 0] - b[:, 0]) * (pz - c[:, 2])) / d
        w1 = ((c[:, 2] - a[:, 2]) * (px - c[:, 0]) + (a[:, 0] - c[:, 0]) * (pz - c[:, 2])) / d
        w2 = 1.0 - w0 - w1
        hit = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        y = w0 * a[:, 1] + w1 * b[:, 1] + w2 * c[:, 1]
        out[s:s + 400] = (np.sum(hit & (y > p[:, 1:2]), axis=1) % 2) == 1
    return out


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])       # (GLSL mat3 columns (c,0,-s),(0,1,0),(s,0,c))


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def report(name, body_parts, legs, far, poses):
    V, part, T = load(name)
    body_v = np.isin(part, body_parts)
    bt = T[body_v[T].all(axis=1)]
    comp = np.arange(len(V))
    def find(i):
        while comp[i] != i:
            comp[i] = comp[comp[i]]
            i = comp[i]
        return i
    for t in bt:
        r = find(t[0])
        comp[find(t[1])] = r
        comp[find(t[2])] = r
    roots = np.array([find(t[0]) for t in bt])
    pieces = [bt[roots == r] for r in np.unique(roots)]
    pieces = [q for q in pieces if len(q) >= 20]
    print("%s: %d vertices, %d triangles (body %d triangles)" % (name, len(V), len(T), len(bt)))
    for label, fn in poses:
        worst = (0.0, None)
        tot_in = 0
        tot = 0
        per_leg = {}
        for ph in ([0.0] if label == "rest" else [k * math.tau / 12 for k in range(12)]):
            for pid, (piv, li, side) in legs.items():
                lt = T[(part[T] == pid).all(axis=1)]
                A, B, C = V[lt[:, 0]], V[lt[:, 1]], V[lt[:, 2]]
                P = np.concatenate([(A + B + C) / 3.0, (4 * A + B + C) / 6.0, (A + 4 * B + C) / 6.0, (A + B + 4 * C) / 6.0])
                piv = np.array(piv)
                keep = np.linalg.norm(P - piv, axis=1) > far
                sw, lift = fn(ph, li, side)
                R = rot_y(sw * side) @ rot_x(-lift * side)
                Q = piv + (P[keep] - piv) @ R.T
                hit = np.zeros(len(Q), dtype=bool)
                for q in pieces:
                    hit |= inside(Q, V, q)
                n_in = int(hit.sum())
                per_leg.setdefault(pid, []).append(100.0 * n_in / max(1, len(Q)))
                tot_in += n_in
                tot += len(Q)
        worst_leg = max(per_leg, key=lambda k: max(per_leg[k]))
        print("  %-22s legs inside the body: %5.1f%% of the legs' surface (mean over the cycle); worst leg part %d: %.1f%% at its worst moment"
              % (label, 100.0 * tot_in / max(1, tot), worst_leg, max(per_leg[worst_leg])))


# wolf spider: parts 1-4 left legs, 5-8 right; pivots (2.4 - 0.75 li, 1.9, 0.9 side)
sp_legs = {}
for li in range(4):
    for side in (-1, 1):
        sp_legs[1 + li + (0 if side < 0 else 4)] = ((2.4 - 0.75 * li, 1.9, 0.9 * side), li, side)


def sp_walk(ph, li, side):
    p = ph + ((li + (0 if side < 0 else 1)) % 2) * math.pi
    return math.sin(p) * 0.3, max(0.0, math.cos(p)) * 0.35


def sp_strike(ph, li, side):
    sw, lift = sp_walk(ph, li, side)
    return (sw, 0.6 + 0.2 * math.sin(ph * 4)) if li < 2 else (sw, lift)


report("wolf_spider", [0], sp_legs, 1.2, [("rest", lambda ph, li, s: (0.0, 0.0)), ("walking", sp_walk),
    ("striking (front legs up)", sp_strike), ("dead (legs curled)", lambda ph, li, s: (0.25 * (1.5 - li), -1.3))])

be_legs = {}
for li in range(3):
    for side in (-1, 1):
        be_legs[4 + li * 2 + (0 if side < 0 else 1)] = (([3.6, 1.2, -0.6][li], 2.0, 1.3 * side), li, side)


def be_walk(ph, li, side):
    p = ph + (0.0 if ((li % 2 == 0) == (side < 0)) else math.pi)
    return math.sin(p) * 0.35, max(0.0, math.cos(p)) * 0.3


report("ground_beetle", [0, 1], be_legs, 1.0, [("rest", lambda ph, li, s: (0.0, 0.0)), ("walking", be_walk),
    ("dead (legs drawn up)", lambda ph, li, s: (0.2 * (1.0 - li), -1.2))])
