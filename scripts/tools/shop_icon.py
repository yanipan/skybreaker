#!/usr/bin/env python3
"""Shop icon post-process: the black area OUTSIDE the card frame becomes
transparent (flood fill from the image border over near-black pixels, so dark
space inside the frame is untouched), soft 1 px edge, resized to 1024.

    python3 scripts/tools/shop_icon.py in.png out.png [--thresh 34]
Needs Pillow (on the Mac: ~/.claude/tools/pyart/bin/python).
"""
import sys
from collections import deque
from PIL import Image, ImageFilter

src, dst = sys.argv[1], sys.argv[2]
thresh = int(sys.argv[sys.argv.index("--thresh") + 1]) if "--thresh" in sys.argv else 34
im = Image.open(src).convert("RGBA")
w, h = im.size
px = im.load()
outside = bytearray(w * h)
q = deque()
for x in range(w):
    q.append((x, 0)); q.append((x, h - 1))
for y in range(h):
    q.append((0, y)); q.append((w - 1, y))
while q:
    x, y = q.popleft()
    i = y * w + x
    if outside[i]:
        continue
    r, g, b, a = px[x, y]
    if max(r, g, b) > thresh:
        continue
    outside[i] = 1
    if x > 0: q.append((x - 1, y))
    if x < w - 1: q.append((x + 1, y))
    if y > 0: q.append((x, y - 1))
    if y < h - 1: q.append((x, y + 1))
mask = Image.frombytes("L", (w, h), bytes(0 if o else 255 for o in outside))
mask = mask.filter(ImageFilter.GaussianBlur(0.8))
im.putalpha(mask)
# Crop to the card and re-pad so every icon's frame has the same size (the
# renders place the frame at 60-95% of the canvas).
im = im.crop(im.getchannel("A").getbbox())
fit = int(1024 * 0.96)
k = fit / max(im.size)
im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
canvas.paste(im, ((1024 - im.width) // 2, (1024 - im.height) // 2), im)
im = canvas
im.save(dst, optimize=True)
kept = sum(1 for o in outside if not o) / (w * h)
print(f"{dst}: {kept:.0%} of the canvas kept")
