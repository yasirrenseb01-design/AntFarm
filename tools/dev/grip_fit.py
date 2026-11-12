"""Do the ants' grip spots (scripts/sim/enemies/<kind>.gd "spots", scripts/sim/enemies/grip_spots.gd) sit on the creature's
model as it is drawn now (assets/models/creatures/<model>.antmesh + .json, legs at rest)?

Each spot [x px, y px, h mm, pitch] is where an ant's feet stand; it faces the body's midline as grip_spots.spots() turns it
and its jaws are JAW mm ahead of it, raised by its pitch. A spot is one of:
  ground  h = 0, biting a leg or an antenna: its jaws within 1 mm of the part, and no body hanging lower than its back
  on      standing on the body: its feet within 0.6 mm of the body's top there
  side    climbing the body's side (no body under its feet): its jaws within 1 mm of the side at its height
and no two ants (both sides, the bottom layer) closer than CROWD mm centre to centre.

Usage: python tools/dev/grip_fit.py <project root> [kind] [--fit]
  --fit also prints spot lists that put each spot back on the model (legs: one ant at the foot, pulling it out, and one
  reared up at the lower leg; parts as listed in FIT below), to paste into the enemy's script."""
import json, math, re, struct, sys
import numpy as np

root = sys.argv[1]
args = sys.argv[2:]
FIT = "--fit" in args
ONLY = next((a for a in args if not a.startswith("--")), "")

# kind: model, view scale (outworld_view.gd "scale"; a model unit = 1.5 mm x scale), body parts, appendage parts an ant
# on the ground can bite (antennae, the centipede's last legs), the first leg part (spider/beetle; the centipede: all
# its legs are part 1)
KINDS = {
    "wolf_spider": ("wolf_spider", 0.85, [0], [], 1),
    "ground_beetle": ("ground_beetle", 1.0, [0, 1], [], 4),
    "centipede": ("centipede", 1.0, [0, 4], [2, 3], 1),
}
JAW = 1.7          # mm from where an ant stands to its mandibles [the outworld worker ~4 mm long: its middle to its jaws]
LIFT = 0.4         # mm its jaws are above its feet standing level
ANT_H = 1.3        # mm: an ant's back above its feet (grip_spots.LAYER_MM)
CROWD = 1.6        # mm: two ants' middles closer than this are in one another [a worker ~1.3 mm wide]


def spots_of(kind):
    src = open("%s/scripts/sim/enemies/%s.gd" % (root, kind), encoding="utf-8").read()
    m = re.search(r'"spots":\s*(\[\[.*?\]\]),', src, re.S)
    return json.loads(m.group(1))


def load(name):
    b = open("%s/assets/models/creatures/%s.antmesh" % (root, name), "rb").read()
    nv, ni = struct.unpack("<II", b[4:12])
    raw = np.frombuffer(b, dtype="<f4", count=nv * 11, offset=12).reshape(nv, 11)
    V = raw[:, :3].astype(np.float64)
    part = np.rint(raw[:, 9] * 16).astype(int)
    T = np.frombuffer(b, dtype="<u4", count=ni, offset=12 + nv * 44).reshape(-1, 3)
    return V, part, T


def column(p, V, T):
    """(top, bottom) of mesh V,T straight above/below the xz point p (nan, nan where none)."""
    a, b, c = V[T[:, 0]], V[T[:, 1]], V[T[:, 2]]
    d = (b[:, 2] - c[:, 2]) * (a[:, 0] - c[:, 0]) + (c[:, 0] - b[:, 0]) * (a[:, 2] - c[:, 2])
    d = np.where(np.abs(d) < 1e-12, 1e-12, d)
    w0 = ((b[:, 2] - c[:, 2]) * (p[0] - c[:, 0]) + (c[:, 0] - b[:, 0]) * (p[2] - c[:, 2])) / d
    w1 = ((c[:, 2] - a[:, 2]) * (p[0] - c[:, 0]) + (a[:, 0] - c[:, 0]) * (p[2] - c[:, 2])) / d
    w2 = 1.0 - w0 - w1
    hit = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
    y = (w0 * a[:, 1] + w1 * b[:, 1] + w2 * c[:, 1])[hit]
    return (float(y.max()), float(y.min())) if len(y) else (math.nan, math.nan)


def face_of(x, z):
    """the way an ant at (x, z) mm faces (grip_spots.spots: at the midline 0.7 x ahead of it, or along it)."""
    if abs(z) <= 0.005:
        return np.array([-1.0 if x > 0 else 1.0, 0.0])
    f = np.array([x * 0.7 - x, -z])
    return f / np.linalg.norm(f)


def jaw_of(x, z, h, pitch):
    f = face_of(x, z)
    return np.array([x + f[0] * JAW * math.cos(pitch), h + LIFT + JAW * math.sin(pitch), z + f[1] * JAW * math.cos(pitch)])


def stand_for(target, pitch, h=0.0):
    """where (x, z mm) an ant stands so its jaws are at target (x, y, z mm)."""
    x, z = target[0], target[2]
    for _ in range(60):
        f = face_of(x, z)
        x, z = target[0] - f[0] * JAW * math.cos(pitch), target[2] - f[1] * JAW * math.cos(pitch)
    return x, z


class Model:
    def __init__(self, kind):
        self.kind = kind
        name, sc, body, extra, leg0 = KINDS[kind]
        self.mm = 1.5 * sc
        V, part, T = load(name)
        self.Vmm = V * self.mm
        self.Vmm[:, 2] = np.abs(self.Vmm[:, 2])          # (one side: the spots are mirrored)
        self.part = part
        self.body = T[np.isin(part[T], body).all(axis=1)]
        self.bodyv = self.Vmm[np.isin(part, body)]
        self.J = json.load(open("%s/assets/models/creatures/%s.json" % (root, name)))
        n = len(self.J["hips"])
        # the legs on the +z side (the json lists both)
        side = [i for i in range(n) if self.J["ankles"][i][2] > 0]
        if kind == "centipede":
            lv = self.Vmm[part == 1]
            self.legs = [lv]                             # (its 30 legs are one part: biting any of them)
        else:
            self.legs = [self.Vmm[part == leg0 + i] for i in side]
        self.hips = [np.array(self.J["hips"][i]) * self.mm for i in side]
        self.extra = [self.Vmm[part == p] for p in extra]

    def low(self, pts, reach):
        return pts[pts[:, 1] <= reach]

    def check(self, s):
        x, y, h, pitch = s
        p = np.array([x * 0.5, h, abs(y) * 0.5])
        jaw = jaw_of(p[0], p[2], h, pitch)
        top, bottom = column(p + [0, 0, 0.02], self.Vmm, self.body)
        if h <= 0.6:
            reach = jaw[1] + 0.6
            best, what = 1e9, ""
            for i, lv in enumerate(self.legs + self.extra):
                q = self.low(lv, reach)
                if len(q):
                    d = float(np.min(np.linalg.norm(q - jaw, axis=1)))
                    if d < best:
                        best, what = d, ("leg %d" % i if i < len(self.legs) else "part %d" % (i - len(self.legs)))
            under = (not math.isnan(bottom)) and bottom < h + ANT_H
            ok = best <= 1.0 and not under
            return "ground", ok, "%s: jaws %.1f mm from it%s" % (what, best, "; UNDER the body (%.1f mm up)" % bottom if under else "")
        if not math.isnan(top) and top > h - 1.0:
            gap = h - top
            return "on", abs(gap) <= 0.6, "body top %.1f mm: feet %+.1f mm" % (top, gap)
        ring = self.bodyv[np.abs(self.bodyv[:, 1] - jaw[1]) < 0.5]
        ring = ring if len(ring) else self.bodyv
        d = float(np.min(np.linalg.norm(ring[:, [0, 2]] - jaw[[0, 2]], axis=1)))
        return "side", d <= 1.0, "jaws %.1f mm from its side at %.1f mm up" % (d, jaw[1])

    def crowd(self, spots):
        pts = []
        for s in spots:
            for sd in ([1, -1] if abs(s[1]) > 0.01 else [1]):
                pts.append((s[0] * 0.5, s[1] * 0.5 * sd, s[2]))
        P = np.array(pts)
        bad = []
        for i in range(len(P)):
            for j in range(i + 1, len(P)):
                if abs(P[i, 2] - P[j, 2]) < ANT_H and np.linalg.norm(P[i, :2] - P[j, :2]) < CROWD:
                    bad.append((i, j, float(np.linalg.norm(P[i, :2] - P[j, :2]))))
        return bad

    # ---- --fit: spots put back on the model
    def foot(self, i):
        """an ant at leg i's foot, outside it, pulling: its jaws on the tarsus' end."""
        lv = self.legs[i]
        d = np.linalg.norm(lv[:, [0, 2]] - self.hips[i][[0, 2]], axis=1)
        tip = lv[np.argsort(d)[-8:]].mean(axis=0)
        x, z = stand_for(tip, 0.3)
        return [x, z, 0.0, 0.3]

    def shin(self, i, pitch=0.6):
        """an ant reared up at leg i's lower leg (the side towards the body): its jaws where the leg is that high."""
        lv = self.legs[i]
        jh = LIFT + JAW * math.sin(pitch)
        d = np.linalg.norm(lv[:, [0, 2]] - self.hips[i][[0, 2]], axis=1)
        outer = lv[d > 0.5 * d.max()]
        q = outer[np.argsort(np.abs(outer[:, 1] - jh))[:6]]       # (its rings nearest that height)
        t = q.mean(axis=0)
        x, z = stand_for(t, pitch)
        return [x, z, 0.0, pitch]

    def at_part(self, k, near, pitch):
        """an ant on the ground biting appendage k (self.extra) at its low point nearest `near` (x, z mm)."""
        jh = LIFT + JAW * math.sin(pitch)
        q = self.low(self.extra[k], jh + 0.5)
        t = q[np.argmin(np.linalg.norm(q[:, [0, 2]] - np.array(near), axis=1))]
        x, z = stand_for(t, pitch)
        return [x, z, 0.0, pitch]

    def on_top(self, x, z, pitch):
        top, _ = column(np.array([x, 0, max(z, 0.02)]), self.Vmm, self.body)     # (off the midline's seam)
        return [x, z, round(top, 1), pitch]

    def on_side(self, x, h, pitch):
        """an ant up the body's side at x (mm), feet at h mm: jaws at the side where they are that high."""
        jh = h + LIFT + JAW * math.sin(pitch)
        ring = self.bodyv[(np.abs(self.bodyv[:, 1] - jh) < 0.3) & (np.abs(self.bodyv[:, 0] - x) < 0.8)]
        s = ring[np.argmax(ring[:, 2])]
        xx, z = stand_for(s, pitch)
        return [xx, z, h, pitch]


def px(s):
    return [round(s[0] * 2.0, 1), round(s[1] * 2.0, 1), s[2], s[3]]


def fitted(m, old):
    """the spots of m.kind put back on the model, in the order (and number) of the old list."""
    if m.kind == "wolf_spider":
        # 0-3 reared at each leg front to back, 4-7 at each foot; 8-10 up its sides; 11-13 on its back; 14 the spinnerets
        new = [m.shin(i) for i in range(4)] + [m.foot(i) for i in range(4)]
        new += [m.on_side(s[0] * 0.5, s[2], s[3]) for s in old[8:11]]
        new += [m.on_top(s[0] * 0.5, abs(s[1]) * 0.5, s[3]) for s in old[11:14]] + [[old[14][0] * 0.5, 0.0, old[14][2], old[14][3]]]
    elif m.kind == "ground_beetle":
        # a pair at each leg (reared at the lower leg, at the foot), 6 the side of its head; 7-10 up its sides;
        # 11-15 on its back; 16 the tip of the abdomen
        new = []
        for i in range(3):
            new += [m.shin(i), m.foot(i)]
        new += [m.on_side(10.5, 3.0, 0.9)]
        new += [m.on_side(s[0] * 0.5, s[2], s[3]) for s in old[7:11]]
        new += [m.on_top(s[0] * 0.5, abs(s[1]) * 0.5, s[3]) for s in old[11:16]]
        new += [[old[16][0] * 0.5, 0.0, old[16][2], old[16][3]]]
    else:
        new = [[s[0] * 0.5, abs(s[1]) * 0.5, s[2], s[3]] for s in old]
        new[11] = m.at_part(0, (new[11][0], new[11][1]), old[11][3])       # an antenna
        new[12] = m.at_part(1, (new[12][0], new[12][1]), old[12][3])       # a last leg
    return [px(s) for s in new]


def report(kind, spots, label):
    m = Model(kind)
    print("%s %s (a model unit %.2f mm): body %.1f long, %.1f wide, %.1f high mm" % (kind, label, m.mm,
        np.ptp(m.bodyv[:, 0]), 2 * m.bodyv[:, 2].max(), m.bodyv[:, 1].max()))
    bad = 0
    for n, s in enumerate(spots):
        kd, ok, what = m.check(s)
        bad += 0 if ok else 1
        print("  %2d %6.1f %5.1f %4.1f %4.2f | %-6s | %s %s" % (n, s[0], s[1], s[2], s[3], kd, "ok " if ok else "BAD", what))
    cr = m.crowd(spots)
    print("  %d of %d spots off the model; %d pairs of ants in one another%s" % (bad, len(spots), len(cr),
        (" (closest %.1f mm)" % min(c[2] for c in cr)) if cr else ""))
    return m


for k in KINDS:
    if ONLY in ("", k):
        old = spots_of(k)
        m = report(k, old, "now")
        if FIT:
            new = fitted(m, old)
            report(k, new, "fitted")
            print('  "spots": ' + json.dumps(new).replace("], [", "],\n\t\t[") + "\n")
        print()
