# Makes assets/ui/logo.png from the keeper's logo picture on white (reference/logo_antfarm_source.png): the paper,
# found by flooding in from the edges (the eggs in the letters are white too) and in the counters of the subtitle,
# becomes see-through; the soft edge keeps its colour with the white taken out of it (no white rim on a dark screen).
#   python -I tools/ui/make_logo.py reference/logo_antfarm_source.png assets/ui/logo.png <preview on dark.png>
import sys
from collections import deque
import numpy as np
from PIL import Image

im = Image.open(sys.argv[1]).convert('RGB')
a = np.asarray(im).astype(np.float32)
h, w, _ = a.shape
dist = (255 - a).max(axis=2)              # 0 = pure white
T = 60                                    # how far from white the paper reaches (its edge into the letters)
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
sub = np.zeros((h, w), bool)
sub[int(h * 0.74):, :] = True
bg |= sub & (dist <= T)                   # the counters of the subtitle (o, e) are paper too
# so are big white patches shut in by a letter (the hole of the R): far bigger than any egg in the letters
seen = bg.copy()
white = dist <= 14
for y0 in range(h):
	for x0 in range(w):
		if seen[y0, x0] or not white[y0, x0]:
			continue
		blob = []
		q = deque([(y0, x0)])
		seen[y0, x0] = True
		while q:
			y, x = q.popleft()
			blob.append((y, x))
			for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
				if 0 <= yy < h and 0 <= xx < w and not seen[yy, xx] and white[yy, xx]:
					seen[yy, xx] = True
					q.append((yy, xx))
		if len(blob) > 200:
			ys, xs = zip(*blob)
			bg[list(ys), list(xs)] = True
alpha = np.where(bg, np.clip((dist - 8.0) / (T - 8.0), 0.0, 1.0), 1.0)
# take the white out of the soft edge: colour = (seen - (1 - alpha) * white) / alpha
al = np.maximum(alpha, 1e-3)[..., None]
rgb = np.clip((a - (1.0 - al) * 255.0) / al, 0, 255)
out = Image.fromarray(np.dstack([rgb, alpha * 255.0]).astype(np.uint8), 'RGBA')
bb = out.getchannel('A').point(lambda v: 255 if v > 30 else 0).getbbox()
out = out.crop((max(0, bb[0] - 6), max(0, bb[1] - 6), min(w, bb[2] + 6), min(h, bb[3] + 6)))
out.save(sys.argv[2])
if len(sys.argv) > 3:
	dark = Image.new('RGBA', out.size, (40, 30, 22, 255))
	dark.alpha_composite(out)
	dark.save(sys.argv[3])
print(out.size)
