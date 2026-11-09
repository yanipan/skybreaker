#!/usr/bin/env python3
"""Cut a generated sprite out of its white background -> transparent 1024x1024 PNG.

    python3 scripts/tools/cutout_sprite.py in.png assets/sprites/enemy_shade.png [--size 1024] [--thresh 236] [--pad 12] [--hole-min 500]

In-play objects (ships, bosses) must have NO background. Only white that is
connected to the image border is removed, so white highlights inside the hull
stay. Edge pixels get a soft alpha and are un-mixed from white so there is no
pale fringe on dark backgrounds. Needs Pillow + numpy.
"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

args = [a for a in sys.argv[1:] if not a.startswith('--')]
def opt(name, default):
    return int(sys.argv[sys.argv.index(name) + 1]) if name in sys.argv else default
src, dst = args[0], args[1]
SIZE, THRESH, PAD = opt('--size', 1024), opt('--thresh', 236), opt('--pad', 12)

im = Image.open(src).convert('RGB')
a = np.asarray(im).astype(np.float32)
mn = a.min(axis=2)
# 1. border-connected near-white = background
near = Image.fromarray(((mn >= THRESH) * 255).astype(np.uint8))
flood = near.copy()
w, h = flood.size
for xy in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]:
    if flood.getpixel(xy) == 255:
        ImageDraw.floodfill(flood, xy, 128)
bg = np.asarray(flood) == 128
# 1b. enclosed pockets of pure white (gaps between a boss's arms, behind exhaust
# plumes) are background too. Small or off-white areas are hull highlights and stay.
HOLE_MIN = opt('--hole-min', 500)
HOLE_DARK = opt('--hole-dark', 25)   # min % of dark outline pixels around a pocket for it to count as a gap
pure = Image.fromarray((((mn >= 246) & ~bg) * 255).astype(np.uint8))
filled = 0
tag = 1
arr = np.asarray(pure)
for y in range(0, h, 6):
    xs = np.nonzero(arr[y] == 255)[0]
    for x in xs[::6]:
        if pure.getpixel((int(x), y)) != 255:
            continue
        tag = 2 if tag == 1 else 1   # alternate marker values 1 / 2
        ImageDraw.floodfill(pure, (int(x), y), 100 + tag)
        comp = np.asarray(pure) == 100 + tag
        if comp.sum() >= HOLE_MIN:
            # A pocket ringed by bright glow is a hot core / lens, not a gap:
            # real gaps are bounded by the dark outline of the hull.
            ring = np.asarray(Image.fromarray((comp * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(13))) > 0
            ring &= ~comp
            ys, xs2 = np.nonzero(comp)
            dark_share = float((mn[ring] < 110).mean()) if ring.any() else 0.0
            keep = dark_share < HOLE_DARK / 100.0
            print(f'  pocket {int(comp.sum())} px at ({int(xs2.mean())},{int(ys.mean())}) dark ring {dark_share:.0%} -> {"kept (glow)" if keep else "removed"}')
            if not keep:
                bg |= comp; filled += 1
        pure.paste(0, mask=Image.fromarray((comp * 255).astype(np.uint8)))
        arr = np.asarray(pure)
# 2. soft edge: within 3 px of the background, alpha follows the distance from white
edge = np.asarray(Image.fromarray((bg * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7))) > 0
alpha = np.ones_like(mn)
soft = np.clip((255.0 - mn) / 70.0, 0.0, 1.0)
alpha[edge] = soft[edge]
alpha[bg] = 0.0
# 3. un-mix white from semi-transparent pixels
al = np.clip(alpha, 1e-3, 1.0)[..., None]
rgb = np.clip((a - (1.0 - al) * 255.0) / al, 0, 255)
out = np.dstack([rgb, alpha * 255.0]).astype(np.uint8)
res = Image.fromarray(out, 'RGBA')
# 4. square canvas, centred, resized
bbox = res.getbbox()
res = res.crop(bbox)
side = int(max(res.size) * (1.0 + PAD / 100.0))   # ships ~88% of the canvas (pad 12), bosses edge to edge (pad 2)
canvas = Image.new('RGBA', (side, side), (0, 0, 0, 0))
canvas.paste(res, ((side - res.width) // 2, (side - res.height) // 2))
canvas = canvas.resize((SIZE, SIZE), Image.LANCZOS)
canvas.save(dst, optimize=True)
cov = (np.asarray(canvas)[..., 3] > 0).mean()
print(f'{dst}: {canvas.size}, {filled} enclosed pocket(s) removed, opaque coverage {cov:.0%}, corners alpha', [canvas.getpixel(p)[3] for p in [(0, 0), (SIZE - 1, 0), (0, SIZE - 1), (SIZE - 1, SIZE - 1)]])
