# Makes the Colony Harmony points' icon from the keeper's drop of honey on white (reference/harmony_icon_source.png,
# the keeper, 2026-10-27): the white round it, found by flooding in from the edges, becomes see-through, the edge pixels
# keep their colour with the white taken out (no white rim on the dark bar); cropped to the drop and written square at
# 128 px (assets/ui/harmony.png; the game draws it at 16-28 px).
#   python -I tools/ui/make_harmony_icon.py reference/harmony_icon_source.png assets/ui/harmony.png
import sys
from collections import deque
import numpy as np
from PIL import Image

im = Image.open(sys.argv[1]).convert('RGB')
a = np.asarray(im).astype(np.float32)
h, w, _ = a.shape
dist = (255 - a).max(axis=2)              # 0 = pure white
T = 22
bg = np.zeros((h, w), bool)
q = deque([(y, x) for x in range(w) for y in (0, h - 1)] + [(y, x) for y in range(h) for x in (0, w - 1)])
while q:
	y, x = q.popleft()
	if bg[y, x] or dist[y, x] > T:
		continue
	bg[y, x] = True
	if y > 0: q.append((y - 1, x))
	if y < h - 1: q.append((y + 1, x))
	if x > 0: q.append((y, x - 1))
	if x < w - 1: q.append((y, x + 1))
# alpha: 0 in the background, rising over the few pixels of the edge (how far from white they are)
alpha = np.where(bg, 0.0, 1.0)
edge = ~bg & (dist < 90)
near_bg = np.zeros_like(bg)
near_bg[1:, :] |= bg[:-1, :]; near_bg[:-1, :] |= bg[1:, :]; near_bg[:, 1:] |= bg[:, :-1]; near_bg[:, :-1] |= bg[:, 1:]
soft = edge & near_bg
alpha[soft] = np.clip(dist[soft] / 90.0, 0.0, 1.0)
rgb = a.copy()
k = np.clip(alpha, 1e-3, 1.0)[..., None]
rgb = np.where(soft[..., None], np.clip((a - 255.0 * (1.0 - k)) / k, 0, 255), a)       # the white taken out of the edge
out = np.dstack([rgb, alpha * 255.0]).astype(np.uint8)
img = Image.fromarray(out, 'RGBA')
box = img.getbbox()
img = img.crop(box)
side = max(img.size)
sq = Image.new('RGBA', (side, side), (0, 0, 0, 0))
sq.paste(img, ((side - img.size[0]) // 2, (side - img.size[1]) // 2))
sq.resize((128, 128), Image.LANCZOS).save(sys.argv[2])
print('written', sys.argv[2])
