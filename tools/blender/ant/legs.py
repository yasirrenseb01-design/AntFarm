# Part of tools/blender/build_ant.py (split out in v0.8.5; run by it inside Blender in order body,
# antennae, legs, setae, sharing its globals: VARIANT/LOD/QUEEN/HI, colours, tube/ellipsoid/blob_group, PARTS).
# ---------------------------------------------------------------- legs

LEGS = [[0.85, 0.75, 1.8], [0.2, 0.1, -0.1], [-0.4, -0.65, -2.2]]
for li, L in enumerate(LEGS):
    for side in (-1, 1):
        part = 4 + li * 2 + (0 if side < 0 else 1)
        hip = (L[0], 0.85, 0.42 * side)
        coxa = (L[0] + 0.1, 0.55, 0.85 * side)
        knee = (L[0] + L[1], 1.75, 2.05 * side)
        ankle = (L[0] + L[2] * 0.85, 0.35, 2.9 * side)
        foot = (L[0] + L[2], 0.0, 3.15 * side)
        CUR_SEG[1] = [hip, coxa, knee, ankle, foot]
        if HI:
            CUR_SEG[0] = 1
            tube("coxa", [hip, lerp(hip, coxa, 0.5), coxa], [0.2, 0.22, 0.17], part, LIMB, segs)
            CUR_SEG[0] = 2
            fem = [lerp(coxa, knee, t) for t in (0.0, 0.12, 0.4, 0.75, 1.0)]
            tube("femur", fem, [0.12, 0.15, 0.18, 0.15, 0.12], part, LIMB, segs)
            CUR_SEG[0] = 3
            tib = [lerp(knee, ankle, t) for t in (0.0, 0.1, 0.6, 1.0)]
            tube("tibia", tib, [0.1, 0.095, 0.11, 0.12], part, LIMB, segs)
            spur = lerp(ankle, foot, 0.25)
            tube("spur", [ankle, (spur[0], spur[1] + 0.05, spur[2] - 0.1 * side)], [0.035, 0.01], part, LIMB, 4)
            # tarsus: five segments, a little arched, the last with a pair of claws
            CUR_SEG[0] = 4
            prev = ankle
            for k in range(5):
                t = (k + 1) / 5.0
                p = lerp(ankle, foot, t)
                p = (p[0], p[1] + 0.08 * math.sin(t * math.pi), p[2])
                r = 0.075 - 0.004 * k
                tube("tarsomere", [prev, lerp(prev, p, 0.6), p], [r * 0.85, r * 1.08, r * 0.9], part, TARSUS, 4, cap=False)
                prev = p
            fwd = Vector(foot) - Vector(ankle)
            fwd.normalize()
            for cz in (-0.05, 0.05):
                tip = (foot[0] + fwd.x * 0.14, foot[1] - 0.06, foot[2] + fwd.z * 0.14 + cz)
                tube("claw", [foot, tip], [0.025, 0.006], part, SUTURE, 4)
        else:
            # far-away ants: no segments, so the shader swings the legs whole (cheap) instead of solving IK
            CUR_SEG[0] = 0
            tube("leg", [hip, coxa, knee], [0.18, 0.16, 0.13], part, LIMB, segs)
            tube("leg", [knee, ankle, foot], [0.11, 0.11, 0.07], part, LIMB, segs)
CUR_SEG[0] = 0
CUR_SEG[1] = None
