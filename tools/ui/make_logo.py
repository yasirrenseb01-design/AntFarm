# Makes assets/ui/logo.png from the keeper's logo picture on white (reference/logo_antfarm_source.jpg): the paper,
# found by flooding in from the edges (the eggs in the letters are white too), becomes a soft shadow.
#   python -I tools/ui/make_logo.py reference/logo_antfarm_source.jpg assets/ui/logo.png <preview on dark.png>
import sys
from PIL import Image, ImageFilter, ImageChops
import numpy as np
from collections import deque
im=Image.open(sys.argv[1]).convert('RGB'); a=np.asarray(im).astype(np.int16)
h,w,_=a.shape
# background = connected to the border, near white (paper white, light grey shadow kept as partial alpha)
dist=(255-a).max(axis=2)            # 0 = pure white
bg=np.zeros((h,w),bool); q=deque()
for x in range(w):
    for y in (0,h-1): q.append((y,x))
for y in range(h):
    for x in (0,w-1): q.append((y,x))
T=90
while q:
    y,x=q.popleft()
    if bg[y,x] or dist[y,x]>T: continue
    bg[y,x]=True
    if y>0:q.append((y-1,x))
    if y<h-1:q.append((y+1,x))
    if x>0:q.append((y,x-1))
    if x<w-1:q.append((y,x+1))
sub=np.zeros((h,w),bool); sub[int(h*0.78):,:]=True; bg=bg | (sub & (dist<=60))   # the counters of the subtitle (o, e) are paper too
alpha=np.where(bg, np.clip((dist-14)*2.2,0,150), 255).astype(np.uint8)   # what is left of the paper: a soft shadow
rgb=a.copy(); rgb[bg]=0
im=Image.fromarray(rgb.astype(np.uint8))
al=Image.fromarray(alpha).filter(ImageFilter.GaussianBlur(0.8))
out=im.copy(); out.putalpha(al)
bb=al.point(lambda v:255 if v>40 else 0).getbbox()
out=out.crop((max(0,bb[0]-8),max(0,bb[1]-8),min(w,bb[2]+8),min(h,bb[3]+8)))
out.save(sys.argv[2])
dark=Image.new('RGBA',out.size,(40,30,22,255)); dark.alpha_composite(out); dark.save(sys.argv[3])
print(out.size)
