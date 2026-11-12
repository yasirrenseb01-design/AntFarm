"""How much of each jointed creature's legs lies inside its body - standing, through the walk, striking, dead - with the
legs placed as shaders/creatures/leg_ik.gdshaderinc places them from the model's .json. Counts points on the legs'
surface farther than `far` from their hip that are inside one of the body's closed pieces (vertical ray, even-odd).
Reads assets/models/creatures/* only. Usage: python tools/dev/leg_clip.py <project root> [wolf_spider|ground_beetle]
(before v0.12.33 the legs were one stiff piece each: the beetle 2.9% standing, 3.8% walking; the spider 0.6%, 1.1%)"""
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


# ground beetle (v0.12.33): jointed legs, as shaders/creatures/leg_ik.gdshaderinc places them from ground_beetle.json
import json

DUTY, LIFT = 0.62, 0.55


def ik_report(name, body_parts, first_part, far, group_of, dead_ankle, strike_ankle=None, coded=False, sway=0.0):
    J = json.load(open("%s/assets/models/creatures/%s.json" % (root, name)))
    b = open("%s/assets/models/creatures/%s.antmesh" % (root, name), "rb").read()
    nv, ni = struct.unpack("<II", b[4:12])
    raw = np.frombuffer(b, dtype="<f4", count=nv * 11, offset=12).reshape(nv, 11)
    V = raw[:, :3].astype(np.float64)
    part = np.rint(raw[:, 9] * 16).astype(int)
    seg = np.rint(raw[:, 10]).astype(int)
    T = np.frombuffer(b, dtype="<u4", count=ni, offset=12 + nv * 44).reshape(-1, 3)
    bt = T[np.isin(part, body_parts)[T].all(axis=1)]
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
    S = J["stride"]
    lift = float(J.get("lift", LIFT))
    print("%s: %d vertices, %d triangles (body %d triangles), %d legs, stride %.2f" % (name, len(V), len(T), len(bt), len(J["hips"]), S))

    UP = float(J.get("knee_up", 0.0)) > 0.5

    def knee_for(i, a):
        h, k0, a0 = np.array(J["hips"][i]), np.array(J["knees"][i]), np.array(J["ankles"][i])
        if UP:
            l1, l2 = np.linalg.norm(k0 - h), np.linalg.norm(a0 - k0)
            d = a - h
            dist = max(np.linalg.norm(d), 0.001)
            d = d / dist
            reach = min(max(dist, abs(l1 - l2) + 0.01), l1 + l2 - 0.01)
            a = h + d * reach
            al = (l1 * l1 - l2 * l2 + reach * reach) / (2 * reach)
            up = math.sqrt(max(0.0, l1 * l1 - al * al))
            nn = np.array([0.0, 1.0, 0.0]) - d * d[1]
            nn /= np.linalg.norm(nn)
            return h + d * al + nn * up, a
        r1 = math.hypot(k0[0] - h[0], k0[2] - h[2])
        l2 = np.linalg.norm(a0 - k0)
        r2 = math.sqrt(max(0.01, l2 * l2 - (k0[1] - a[1]) ** 2))
        u = np.array([a[0] - h[0], a[2] - h[2]])
        rho = max(np.linalg.norm(u), 0.001)
        u = u / rho
        reach = min(max(rho, abs(r1 - r2) + 0.01), r1 + r2 - 0.01)
        a = np.array([h[0] + u[0] * reach, a[1], h[2] + u[1] * reach])
        along = (r1 * r1 - r2 * r2 + reach * reach) / (2 * reach)
        off = math.sqrt(max(0.0, r1 * r1 - along * along))
        n = np.array([u[1], -u[0]])
        if n @ np.array(J["bends"][i]) < 0:
            n = -n
        k = np.array([h[0] + u[0] * along + n[0] * off, k0[1], h[2] + u[1] * along + n[1] * off])
        return k, a

    def turn(v, a, b):
        a = a / np.linalg.norm(a)
        b = b / np.linalg.norm(b)
        c = np.cross(a, b)
        d = a @ b
        return v * d + np.cross(c, v) + np.outer(v @ c, c) / (1.0 + d)

    def place(i, a):
        h, k0, a0 = np.array(J["hips"][i]), np.array(J["knees"][i]), np.array(J["ankles"][i])
        k, a = knee_for(i, np.array(a, dtype=float))
        if coded:       # (the centipede: every leg is part `first_part`, the 11th number 4 x the leg + its piece)
            lt = T[((part[T] == first_part) & (seg[T] // 4 == i)).all(axis=1)]
            sg = seg[lt[:, 0]] % 4
        else:
            lt = T[(part[T] == first_part + i).all(axis=1)]
            sg = seg[lt[:, 0]]
        A, B, C = V[lt[:, 0]], V[lt[:, 1]], V[lt[:, 2]]
        out = []
        for P in ((A + B + C) / 3.0, (4 * A + B + C) / 6.0, (A + 4 * B + C) / 6.0, (A + B + 4 * C) / 6.0):
            Q = P.copy()
            m = sg == 1
            if UP:
                Q[m] = h + turn(P[m] - h, k0 - h, k - h)
            else:
                was = np.array([k0[0] - h[0], k0[2] - h[2]]); was /= np.linalg.norm(was)
                now = np.array([k[0] - h[0], k[2] - h[2]]); now /= np.linalg.norm(now)
                c, s_ = was @ now, was[0] * now[1] - was[1] * now[0]
                d = P[m] - h
                Q[m] = h + np.stack([d[:, 0] * c - d[:, 2] * s_, d[:, 1], d[:, 0] * s_ + d[:, 2] * c], axis=1)
            m = sg == 2
            Q[m] = k + turn(P[m] - k0, a0 - k0, a - k)
            m = sg == 3
            Q[m] = P[m] + (a - a0)
            out.append(Q[np.linalg.norm(Q - h, axis=1) > far])
        return np.concatenate(out), a

    def ankle_at(i, p):
        a = np.array(J["ankles"][i], dtype=float)
        p = p % 1.0
        if p < DUTY:
            a[0] += S * (0.5 - p / DUTY)
        else:
            u = (p - DUTY) / (1 - DUTY)
            a[0] += S * (-0.5 + u * u * (3 - 2 * u))
            a[1] += lift * math.sin(u * math.pi)
        return a

    labels = ("rest", "walking") + (("dead",) if dead_ankle else ()) + (("striking",) if strike_ankle else ()) + (("swayed out", "swayed in") if sway else ())
    for label in (("dead",) if len(sys.argv) > 3 else labels):
        tot_in = tot = 0
        per = {}
        slip = 0.0
        for ph in ([0.25 * DUTY] if label == "rest" else ([0.0] if label in ("dead", "striking") else [k / 16.0 for k in range(16)])):
            for i in range(len(J["hips"])):
                if label == "dead":
                    a = dead_ankle(J, i)
                elif label == "striking":
                    a = strike_ankle(J, i)
                elif label == "rest":
                    a = np.array(J["ankles"][i], dtype=float)
                else:
                    a = ankle_at(i, ph + group_of(i))
                    if label.startswith("swayed"):
                        # (the body to one side of its feet by `sway`: the same as the foot that far the other way)
                        a[2] += sway * (1 if label.endswith("out") else -1) * (1 if J["ankles"][i][2] > 0 else -1)
                Q, a2 = place(i, a)
                slip = max(slip, float(np.linalg.norm(np.array(a, dtype=float) - a2)))
                hit = np.zeros(len(Q), dtype=bool)
                for q in pieces:
                    hit |= inside(Q, V, q)
                per.setdefault(i, []).append(100.0 * hit.sum() / max(1, len(Q)))
                tot_in += int(hit.sum())
                tot += len(Q)
        worst = max(per, key=lambda k: max(per[k]))
        print("  %-10s legs inside the body: %5.2f%% of the legs' surface; worst leg %d: %.2f%% at its worst moment; ankle pulled off its place by at most %.3f"
              % (label, 100.0 * tot_in / max(1, tot), worst, max(per[worst]), slip))


# the dead pose's ankle (beetle.gdshader): hip.x * a + b, hip.y - c, d * side
DEAD = [0.9, 0.3, 3.0, 3.0]
ONLY = sys.argv[2] if len(sys.argv) > 2 else ""

SP_NEAR = float(sys.argv[3]) if len(sys.argv) > 3 else 2.5      # (spider.gdshader; another number to try: word 3)


def sp_dead(J, i):
    h, k, a = np.array(J["hips"][i]), np.array(J["knees"][i]), np.array(J["ankles"][i])
    o = np.array([a[0] - h[0], a[2] - h[2]])
    o /= np.linalg.norm(o)
    near = abs(np.linalg.norm(k - h) - np.linalg.norm(a - k)) + SP_NEAR
    return np.array([h[0] + o[0] * near, 0.3, h[2] + o[1] * near])


def sp_strike(J, i):
    a = np.array(J["ankles"][i], dtype=float)
    side = -1 if i < 4 else 1
    return a + np.array([0.6, 3.3, -0.8 * side]) if i % 4 < 2 else a


if ONLY in ("", "wolf_spider"):
    ik_report("wolf_spider", [0], 1, 1.2, lambda i: ((i % 4 + (0 if i < 4 else 1)) % 2) * 0.5, sp_dead, sp_strike)
if ONLY in ("", "centipede"):
    ik_report("centipede", [0], 1, 0.45, lambda i: -(i // 2) * 0.14 + (0.5 if i % 2 else 0.0), None, None, coded=True, sway=0.57)
if ONLY in ("", "ground_beetle"):
    ik_report("ground_beetle", [0, 1], 4, 1.0, lambda i: 0.0 if ((i // 2) % 2 == 0) == (i % 2 == 0) else 0.5,
        lambda J, i: np.array([J["hips"][i][0] * DEAD[0] + DEAD[1], J["hips"][i][1] - DEAD[2], DEAD[3] * (1 if i % 2 else -1)]))
