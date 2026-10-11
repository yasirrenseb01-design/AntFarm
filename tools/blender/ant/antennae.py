# Part of tools/blender/build_ant.py (split out in v0.8.5; run by it inside Blender in order body,
# antennae, legs, setae, sharing its globals: VARIANT/LOD/QUEEN/HI, colours, tube/ellipsoid/blob_group, PARTS).
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
