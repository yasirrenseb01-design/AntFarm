# Makes the game's icon from the keeper's winged queen on white (reference/icon_queen_source.png): the white, found by
# flooding in from the edges, becomes see-through; the pixels along the edge keep their colour with the white taken out
# of them (no white rim on a dark taskbar). Writes a square PNG (Godot's window and app icon) and a Windows .ico with
# the sizes Explorer and the taskbar ask for.
#   python -I tools/ui/make_icon.py reference/icon_queen_source.png assets/ui/icon.png assets/ui/icon.ico <preview.png>
import sys
from collections import deque
import numpy as np
from PIL import Image

im = Image.open(sys.argv[1]).convert('RGB')
a = np.asarray(im).astype(np.float32)
h, w, _ = a.shape
dist = (255 - a).max(axis=2)              # 0 = pure white
T = 18                                    # how far from white the paper reaches
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
# white shut in by the body (between the wings and the gaster): bigger than the shine in the eye, which stays
seen = bg.copy()
white = dist <= T
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
		if len(blob) > 150:
			for y, x in blob:
				bg[y, x] = True

alpha = np.where(bg, 0.0, 1.0)
# the edge: the first few pixels in from the white are part white - take the white out of them
edge = np.zeros((h, w), bool)
near = bg.copy()
for _ in range(3):
	grow = near.copy()
	grow[1:] |= near[:-1]; grow[:-1] |= near[1:]; grow[:, 1:] |= near[:, :-1]; grow[:, :-1] |= near[:, 1:]
	edge |= grow & ~near & ~bg
	near = grow
soft = np.clip(dist / 90.0, 0.0, 1.0)
alpha[edge] = np.minimum(alpha[edge], soft[edge])
rgb = a.copy()
k = edge & (alpha > 0.02)
for c in range(3):
	ch = rgb[..., c]
	ch[k] = np.clip((ch[k] - (1.0 - alpha[k]) * 255.0) / alpha[k], 0, 255)
out = np.dstack([rgb, alpha * 255.0]).astype(np.uint8)
img = Image.fromarray(out, 'RGBA')

# square, the ant filling it with a little room around
box = img.getchannel('A').point(lambda v: 255 if v > 8 else 0).getbbox()
img = img.crop(box)
side = int(max(img.size) * 1.04)
sq = Image.new('RGBA', (side, side), (0, 0, 0, 0))
sq.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
big = sq.resize((512, 512), Image.LANCZOS)
big.save(sys.argv[2])
big.resize((256, 256), Image.LANCZOS).save(sys.argv[3], sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
if len(sys.argv) > 4:
	prev = Image.new('RGBA', (1200, 560), (24, 20, 18, 255))
	prev.alpha_composite(big, (20, 24))
	x = 560
	for s in (256, 128, 64, 48, 32, 16):
		prev.alpha_composite(big.resize((s, s), Image.LANCZOS), (x, 40))
		x += s + 16
	light = Image.new('RGBA', (300, 300), (235, 235, 235, 255))
	light.alpha_composite(big.resize((256, 256), Image.LANCZOS), (22, 22))
	prev.paste(light, (560, 250))
	prev.save(sys.argv[4])
