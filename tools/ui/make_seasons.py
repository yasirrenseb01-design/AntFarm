# Makes the time bar's four seasons (ui/time_bar.gd) from the keeper's pictures on a flat green (reference/seasons/*.png,
# 2064x512, the keeper, 2026-11-09): the green becomes see-through (the bar draws its own sky behind), the left and right
# edges are blended so the strip runs on without a seam, cropped from a common top to each picture's ground line, and
# written small (assets/ui/seasons/*.png, H px high - the bar draws them ~50-60 px high).
#   python -I tools/ui/make_seasons.py                 (all four)
#   python -I tools/ui/make_seasons.py spring --show   (and a check picture on dark and light: shots/seasons_check_<name>.png)
#
# The green: each picture's own (measured from its top rows: not 00FF00, and not the same in any two). How far a pixel is
# from it (RGB distance) gives its alpha, from 0 at T_HARD to 1 at T_SOFT - but only for pixels the open green reaches
# from the top without crossing the ink: a leaf of spring nearly the colour of the green, inside its inked outline, stays
# solid. Edge pixels have the green taken out of them (unblended: c = (p - (1-a) * green) / a), so no green rim on a
# night sky.
import sys
import numpy as np
from PIL import Image

SRC = 'reference/seasons/%s.png'
DST = 'assets/ui/seasons/%s.png'
TOP = 50          # the common top crop (the tallest stems start ~57 px down)
H = 128           # rows written: PAD clear rows, the picture, PAD clear rows
PAD = 4           # (the bar tiles the picture sideways with the texture repeating, which repeats it up and down too: the
                  # ground row bled into the top edge as a thin line - time_bar.gd SCENE_PAD)
SEAM = 24         # px of the original blended across the join (what is left of a mismatch there)
# name: (T_HARD, T_SOFT, flood) - spring's leaves are only 26-55 from its green: keyed only where the open green reaches
# (flood); the others' plants are 100+ away: keyed everywhere (green pockets shut in by grass would stay bright green)
KEYS = {'spring': (11.0, 30.0, True), 'summer': (22.0, 60.0, False), 'autumn': (22.0, 60.0, False),
	'winter': (16.0, 45.0, False)}


def flood_from_edges(passable: np.ndarray) -> np.ndarray:
	reach = np.zeros_like(passable)
	reach[0] = passable[0]
	reach[-1] = passable[-1]          # (and the green under the ground line, shut off from the top by the line)
	while True:
		grown = reach.copy()
		grown[1:] |= reach[:-1]
		grown[:-1] |= reach[1:]
		grown[:, 1:] |= reach[:, :-1]
		grown[:, :-1] |= reach[:, 1:]
		grown &= passable
		if (grown == reach).all():
			return reach
		reach = grown


def make(name: str, show: bool) -> None:
	a = np.asarray(Image.open(SRC % name).convert('RGB')).astype(np.float32)
	h, w, _ = a.shape
	green = np.median(a[0:40].reshape(-1, 3), axis=0)
	d = np.sqrt(((a - green) ** 2).sum(-1))
	t_hard, t_soft, flood = KEYS[name]
	# the open green: from the top and the bottom through anything within T_SOFT (the ink lines stop it)
	outside = flood_from_edges(d < t_soft) if flood else np.ones((h, w), bool)
	alpha = np.ones((h, w), np.float32)
	ramp = np.clip((d - t_hard) / (t_soft - t_hard), 0.0, 1.0)
	alpha[outside] = ramp[outside]
	# the outline's blurred rim (a pixel or two next to the open green, part green part ink): a longer ramp, so it is
	# unblended too rather than kept solid with the green in it
	rim = outside.copy()
	for _ in range(2):
		g = rim.copy()
		g[1:] |= rim[:-1]
		g[:-1] |= rim[1:]
		g[:, 1:] |= rim[:, :-1]
		g[:, :-1] |= rim[:, 1:]
		rim = g
	rim &= ~outside
	alpha[rim] = np.clip((d[rim] - t_hard) / (t_soft * 2.5 - t_hard), 0.0, 1.0)
	alpha[d < t_hard * 0.6] = 0.0          # (green pockets shut in by stems)
	safe = np.maximum(alpha, 1e-3)[..., None]
	rgb = np.clip((a - (1.0 - alpha[..., None]) * green) / safe, 0.0, 255.0)
	# the ground line: the last row more than half solid (the ink line in spring and winter, the soil in autumn)
	solid = (alpha > 0.5).mean(axis=1)
	bottom = max(y for y in range(h) if solid[y] > 0.5) + 2
	rgb, alpha = rgb[TOP:bottom], alpha[TOP:bottom]
	# the seam: each picture is two copies of one stretch of ground side by side, ~1,034 px apart (measured). One copy
	# is cut out where it meets the next best (column x0 against x0 + P), so its ends run on into each other; the
	# first SEAM columns fade in from the SEAM just past its end (premultiplied) for what is left of a mismatch
	pm = np.concatenate([rgb * alpha[..., None], alpha[..., None]], axis=-1)
	grey = pm[..., :3].mean(-1)
	period = min(range(980, 1090), key=lambda q: np.abs(grey[:, :w - q] - grey[:, q:]).mean())
	x0 = min(range(0, w - period - SEAM), key=lambda x: np.abs(grey[:, x:x + SEAM] - grey[:, x + period:x + period + SEAM]).mean())
	t = np.linspace(0.0, 1.0, SEAM, dtype=np.float32)[None, :, None]
	tile = pm[:, x0:x0 + period].copy()
	tile[:, :SEAM] = tile[:, :SEAM] * t + pm[:, x0 + period:x0 + period + SEAM] * (1.0 - t)
	pm = tile
	al = pm[..., 3:4]
	out = np.concatenate([np.clip(pm[..., :3] / np.maximum(al, 1e-3), 0, 255), al * 255.0], axis=-1)
	img = Image.fromarray(out.round().astype(np.uint8), 'RGBA')
	nw = round(img.width * (H - 2 * PAD) / img.height)
	img = img.resize((nw, H - 2 * PAD), Image.LANCZOS)
	padded = Image.new('RGBA', (nw, H), (0, 0, 0, 0))
	padded.paste(img, (0, PAD))
	img = padded
	img.save(DST % name, optimize=True)
	print('%s: green %s, ground line at row %d, repeats every %d px (cut at %d) -> %dx%d' % (
		name, green.round().astype(int).tolist(), bottom, period, x0, nw, H))
	if show:      # three copies side by side (two seams) on a night sky and a day sky
		pair = Image.new('RGBA', (nw * 3, H * 2))
		for i, col in enumerate([(23, 28, 54, 255), (150, 190, 230, 255)]):
			bgi = Image.new('RGBA', (nw * 3, H), col)
			for k in range(3):
				bgi.alpha_composite(img, (nw * k, 0))
			pair.paste(bgi, (0, H * i))
		pair.save('shots/seasons_check_%s.png' % name)


if __name__ == '__main__':
	names = [n for n in sys.argv[1:] if not n.startswith('--')] or list(KEYS)
	for n in names:
		make(n, '--show' in sys.argv)
