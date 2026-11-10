"""Compare two sets of frames (tools/dev/native_shots.sh) pixel by pixel: for each frame the box that differs, counted.
The version shown in the top-left panel (v0.12.x) differs between two versions - its box is told apart from the rest.
Usage: python tools/dev/shot_diff.py <dir a> <dir b> [set to leave out, e.g. ns2]   (v0.12.27)
"""
import os
import sys
from collections import Counter
from PIL import Image, ImageChops

VERSION_BOX = (140, 70, 175, 95)        # (the version label, at 1920x1057: "... v0.12.27")


def inside(b, box):
    return b[0] >= box[0] and b[1] >= box[1] and b[2] <= box[2] and b[3] <= box[3]


a, b = sys.argv[1], sys.argv[2]
skip = set(sys.argv[3:])
count = Counter()
other = []
for d in sorted(os.listdir(a)):
    if not d.startswith('ns') or d in skip or not os.path.isdir(os.path.join(a, d)):
        continue
    for f in sorted(os.listdir(os.path.join(a, d))):
        if not f.endswith('.png'):
            continue
        ia = Image.open(os.path.join(a, d, f)).convert('RGB')
        ib = Image.open(os.path.join(b, d, f)).convert('RGB')
        box = ImageChops.difference(ia, ib).getbbox()
        if box is None:
            count['same'] += 1
        elif inside(box, VERSION_BOX):
            count['only the version label'] += 1
        else:
            count['different'] += 1
            other.append('%s/%s %s' % (d, f, box))
print(dict(count))
for o in other:
    print('  differs:', o)
