# Makes the keeper's hand, the pointer in the Home (game/home.gd): an open hand, and a hand pointing with its first
# finger when it is on something that can be clicked. Drawn 8x larger from rounded shapes (an ink outline under skin,
# a shirt cuff at the wrist) and scaled down to 48 x 48.
#   python -I tools/ui/make_hand.py assets/ui
import sys
from PIL import Image, ImageDraw

S = 8
N = 48
SKIN = (238, 196, 160, 255)
SHADE = (214, 166, 128, 255)
INK = (52, 34, 22, 255)
CUFF = (232, 228, 214, 255)


def hand(shapes, cuff, path):
	im = Image.new('RGBA', (N * S, N * S), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	o = 1.4 * S
	allb = shapes + [cuff]
	for (x0, y0, x1, y1, r) in allb:
		d.rounded_rectangle([x0 * S - o, y0 * S - o, x1 * S + o, y1 * S + o], radius=r * S + o, fill=INK)
	for i, (x0, y0, x1, y1, r) in enumerate(shapes):
		d.rounded_rectangle([x0 * S, y0 * S, x1 * S, y1 * S], radius=r * S, fill=SKIN)
		# a little shade down one side of each
		d.rounded_rectangle([x1 * S - 1.6 * S, y0 * S + r * S, x1 * S - 0.4 * S, y1 * S - r * S], radius=0.6 * S, fill=SHADE)
	x0, y0, x1, y1, r = cuff
	d.rounded_rectangle([x0 * S, y0 * S, x1 * S, y1 * S], radius=r * S, fill=CUFF)
	d.line([x0 * S, (y0 + 1.6) * S, x1 * S, (y0 + 1.6) * S], fill=(190, 184, 166, 255), width=int(0.8 * S))
	im.resize((N, N), Image.LANCZOS).save(path)


out = sys.argv[1]
# pointing: the first finger up, the others folded on the palm (hot spot at its tip, 16, 2)
hand([
	(12, 20, 34, 41, 6),        # palm
	(5, 23, 15, 31, 4),         # thumb
	(13.5, 1, 19.5, 26, 3),     # first finger
	(19.5, 17, 25, 26, 2.6),    # the folded ones
	(25, 18, 30, 27, 2.4),
	(30, 20, 34.5, 28, 2.2),
], (13, 39, 34, 47, 2), out + '/hand_point.png')
# open: the fingers up, a little apart (hot spot at the middle finger's tip, 19, 3)
hand([
	(11, 18, 34, 40, 6),
	(3, 19, 12, 27, 4),
	(11, 7, 16.5, 26, 2.7),
	(16.8, 3, 22.3, 26, 2.7),
	(22.6, 5, 28, 26, 2.7),
	(28.3, 10, 33.5, 27, 2.5),
], (12, 38, 34, 47, 2), out + '/hand_open.png')
