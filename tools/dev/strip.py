"""Join a frame strip from --seq (shots/<name>_0.png ...) into one contact sheet, cropped to the view.
Usage: python tools/dev/strip.py shots/seq/w [x0 y0 x1 y1] -> shots/seq/w_strip.png"""
import sys
from PIL import Image

base = sys.argv[1]
box = tuple(int(v) for v in sys.argv[2:6]) if len(sys.argv) >= 6 else (0, 90, 1240, 800)
frames = []
k = 0
while True:
    try:
        frames.append(Image.open("%s_%d.png" % (base, k)).crop(box))
    except FileNotFoundError:
        break
    k += 1
w, h = frames[0].size
cols = 3
rows = (len(frames) + cols - 1) // cols
sheet = Image.new("RGB", (w * cols, h * rows))
for i, f in enumerate(frames):
    sheet.paste(f, ((i % cols) * w, (i // cols) * h))
sheet.thumbnail((1800, 1800))
sheet.save(base + "_strip.png")
print(base + "_strip.png", len(frames), "frames")
