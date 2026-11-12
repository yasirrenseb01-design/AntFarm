"""The ant album's pictures and the colony bar's sketch, from the keeper's plate (reference/album/<species>_plate_II.webp,
the keeper's picture, 2026-11-12): the plate cut in its two halves (assets/ui/album/<species>_a.webp: the queen and
the brood, b: the workers), and the queen alone as ink on nothing (assets/ui/album/<species>_queen.png: the paper
made see-through by how dark each pixel is, the stains - small blots apart from the drawing - taken out).
Usage: python tools/ui/make_album.py <project root>"""
import sys
from collections import deque
import numpy as np
from PIL import Image

root = sys.argv[1]
SP = "lasius_niger"
im = Image.open("%s/reference/album/%s_plate_II.webp" % (root, SP)).convert("RGB")
w, h = im.size
im.crop((0, 0, w // 2, h)).save("%s/assets/ui/album/%s_a.webp" % (root, SP), quality=92)
im.crop((w // 2, 0, w, h)).save("%s/assets/ui/album/%s_b.webp" % (root, SP), quality=92)

q = np.asarray(im.crop((52, 90, 705, 300))).astype(np.float64)
lum = q @ np.array([0.299, 0.587, 0.114])
alpha = np.clip((205.0 - lum) / 140.0, 0.0, 1.0)
# blots apart from the drawing: groups of inked pixels (alpha > 0.25) smaller than MIN_BLOB, and the label's letters
MIN_BLOB = 400
ink = alpha > 0.25
seen = np.zeros_like(ink)
H, W = ink.shape
for y in range(H):
    for x in range(W):
        if ink[y, x] and not seen[y, x]:
            group = []
            dq = deque([(y, x)])
            seen[y, x] = True
            while dq:
                cy, cx = dq.popleft()
                group.append((cy, cx))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < H and 0 <= nx < W and ink[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            dq.append((ny, nx))
            if len(group) < MIN_BLOB:
                for cy, cx in group:
                    alpha[cy, cx] = 0.0
# faint paper left between: below 0.12 nothing
alpha[alpha < 0.12] = 0.0
# the ink: the drawing's own colours, darkened a little (sepia on the cream sheet)
rgb = np.clip(q * 0.8, 0, 255)
out = np.dstack([rgb, alpha * 255.0]).astype(np.uint8)
Image.fromarray(out, "RGBA").save("%s/assets/ui/album/%s_queen.png" % (root, SP))
print("album pictures made:", w // 2, "x", h, "each; queen", W, "x", H)
