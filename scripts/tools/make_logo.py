#!/usr/bin/env python3
"""Regenerate the SKYBREAKER logo + app icons (pure Pillow, no numpy).

Outputs (relative to project root):
  assets/sprites/ui/gamelogo.png      1024x1024 RGBA, transparent emblem
  assets/sprites/ui/app_icon_1024.png 1024x1024 RGB, full-bleed icon
  assets/sprites/ui/icon_fg_432.png   432x432 RGBA Android adaptive foreground
  assets/sprites/ui/icon_bg_432.png   432x432 RGB  Android adaptive background

Usage:  python3 scripts/tools/make_logo.py [--out DIR]
Everything is drawn at SS x resolution and downsampled with LANCZOS.
"""
import argparse
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FONT = os.path.join(ROOT, "assets", "fonts", "Orbitron.ttf")
SS = 4  # supersample factor

# Palette (matches scripts/Boot.gd)
NAVY = (5, 10, 26)
CYAN = (140, 242, 255)
CYAN_DEEP = (30, 150, 230)
GOLD = (255, 217, 102)
WHITE = (255, 255, 255)
INK = (6, 8, 16)  # outline colour


# ---------------------------------------------------------------- helpers
def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def gradient_column(h, stops):
    """stops: list of (pos 0..1, (r,g,b)). Returns RGB image 1 x h."""
    col = Image.new("RGB", (1, h))
    px = []
    for y in range(h):
        t = y / max(1, h - 1)
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if t <= p1 or i == len(stops) - 2:
                u = 0 if p1 == p0 else min(1, max(0, (t - p0) / (p1 - p0)))
                px.append(lerp(c0, c1, u))
                break
    col.putdata(px)
    return col


def vgrad(size, box, stops):
    """Full-size RGB image with a vertical gradient spanning box (y0..y1)."""
    w, h = size
    y0, y1 = int(box[1]), int(box[3])
    col = gradient_column(max(2, y1 - y0), stops)
    img = Image.new("RGB", size, stops[0][1])
    img.paste(col.resize((w, y1 - y0), Image.NEAREST), (0, y0))
    if y1 < h:
        img.paste(stops[-1][1], (0, y1, w, h))
    return img


def shift(mask, dx, dy):
    out = Image.new(mask.mode, mask.size, 0)
    out.paste(mask, (int(dx), int(dy)))
    return out


def grow(mask, r):
    """Smooth dilation via blur + threshold ramp (fast on big images)."""
    if r <= 0:
        return mask
    b = mask.filter(ImageFilter.GaussianBlur(r))
    return b.point(lambda v: 0 if v < 4 else min(255, (v - 4) * 12))


def shrink(mask, r):
    b = mask.filter(ImageFilter.GaussianBlur(r))
    return b.point(lambda v: 0 if v < 235 else min(255, (v - 235) * 13))


def mul_alpha(mask, k):
    return mask.point(lambda v: int(v * k))


def fill(base, color, mask):
    """Composite a flat colour (RGB or RGBA) through mask onto base RGBA."""
    layer = Image.new("RGBA", base.size, color[:3] + (255,))
    if len(color) == 4:
        mask = mul_alpha(mask, color[3] / 255)
    a = Image.new("L", base.size, 0)
    a.paste(mask)
    layer.putalpha(a)
    base.alpha_composite(layer)


def fill_img(base, rgb_img, mask):
    layer = rgb_img.convert("RGBA")
    layer.putalpha(mask)
    base.alpha_composite(layer)


def glow(base, mask, color, radius, strength=1.0):
    g = mask.filter(ImageFilter.GaussianBlur(radius))
    if strength != 1.0:
        g = g.point(lambda v: min(255, int(v * strength)))
    fill(base, color, g)


def poly_mask(size, pts):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon([(int(x), int(y)) for x, y in pts], fill=255)
    return m


def star_points(cx, cy, r_out, r_in, rot=-90):
    pts = []
    for i in range(10):
        a = math.radians(rot + i * 36)
        r = r_out if i % 2 == 0 else r_in
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


# ---------------------------------------------------------------- wordmark
def text_mask(size, text, center, target_w, weight="Black", tracking=0.06,
              max_h=None):
    """Return (mask, bbox). Letters laid out one by one so tracking is exact."""
    def layout(fs):
        f = ImageFont.truetype(FONT, fs)
        f.set_variation_by_name(weight)
        widths = [f.getbbox(ch)[2] - f.getbbox(ch)[0] for ch in text]
        gap = fs * tracking
        total = sum(widths) + gap * (len(text) - 1)
        return f, widths, gap, total

    fs = 200
    f, widths, gap, total = layout(fs)
    fs = int(fs * target_w / total)
    f, widths, gap, total = layout(fs)
    if max_h:
        cap = f.getbbox("H")[3] - f.getbbox("H")[1]
        if cap > max_h:
            fs = int(fs * max_h / cap)
            f, widths, gap, total = layout(fs)
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    hb = f.getbbox("H")
    cap_h = hb[3] - hb[1]
    x = center[0] - total / 2
    y = center[1] - cap_h / 2 - hb[1]
    for ch, w in zip(text, widths):
        bb = f.getbbox(ch)
        d.text((x - bb[0], y), ch, font=f, fill=255)
        x += w + gap
    return m, (center[0] - total / 2, center[1] - cap_h / 2,
               center[0] + total / 2, center[1] + cap_h / 2)


def draw_wordmark(base, text, center, target_w, s, outline=7, max_h=None,
                  glow_strength=1.0, tracking=0.06, rim=CYAN, return_mask=False,
                  stops=None):
    """Chrome-gold beveled letters, dark outline, cyan rim glow, drop shadow."""
    size = base.size
    m, bb = text_mask(size, text, center, target_w, tracking=tracking, max_h=max_h)
    cap_h = bb[3] - bb[1]
    o = outline * s
    outer = grow(m, o)
    # drop shadow
    fill(base, (0, 0, 0, 200),
         shift(grow(m, o * 1.4), 0, cap_h * 0.08).filter(
             ImageFilter.GaussianBlur(cap_h * 0.06)))
    # cyan energy rim behind the outline
    glow(base, grow(m, o * 1.6), rim, cap_h * 0.10, 0.9 * glow_strength)
    # dark outline + thin amber outer pinline for a minted-coin edge
    fill(base, (120, 70, 10), grow(m, o * 1.25))
    fill(base, INK, outer)
    # gold body: chrome gradient with a dark "horizon" band
    stops = stops or [
        (0.00, (255, 226, 130)),
        (0.40, (255, 250, 222)),
        (0.47, (214, 140, 30)),
        (0.53, (104, 50, 6)),
        (0.60, (232, 158, 40)),
        (0.85, (255, 210, 96)),
        (1.00, (196, 116, 20)),
    ]
    fill_img(base, vgrad(size, bb, stops), m)
    # bevel: top-left edges light, bottom-right edges dark
    d = max(2, int(cap_h * 0.06))
    hi = ImageChops.subtract(m, shift(m, d, d)).filter(
        ImageFilter.GaussianBlur(d * 0.35))
    lo = ImageChops.subtract(m, shift(m, -d, -d)).filter(
        ImageFilter.GaussianBlur(d * 0.35))
    fill(base, (255, 255, 240, 235), hi)
    fill(base, (70, 30, 2, 220), lo)
    # crisp specular line across the upper third
    line = Image.new("L", size, 0)
    ly = bb[1] + cap_h * 0.16
    ImageDraw.Draw(line).rectangle(
        (0, int(ly), size[0], int(ly + max(s, cap_h * 0.035))), fill=255)
    line = ImageChops.multiply(line, shrink(m, d * 0.6)).filter(
        ImageFilter.GaussianBlur(s * 0.6))
    fill(base, (255, 255, 255, 230), line)
    return (bb, m) if return_mask else bb


# ---------------------------------------------------------------- star
def draw_star(base, cx, cy, R, s, core=True, ring=True):
    size = base.size
    ri = R * 0.44
    pts = star_points(cx, cy, R, ri)
    smask = poly_mask(size, pts)
    # shadow + glows
    fill(base, (0, 0, 0, 170),
         shift(grow(smask, 6 * s), 0, R * 0.05).filter(
             ImageFilter.GaussianBlur(R * 0.06)))
    glow(base, smask, CYAN_DEEP, R * 0.35, 0.75)
    glow(base, smask, GOLD, R * 0.12, 0.5)
    # dark outline
    fill(base, INK, grow(smask, 5 * s))
    # faceted bevel: each arm is two triangles lit from upper-left
    light = math.radians(-125)
    facets = Image.new("RGBA", size, (0, 0, 0, 0))
    fd = ImageDraw.Draw(facets)
    dark, bright = (138, 66, 4), (255, 234, 140)
    for i in range(5):
        tip = pts[2 * i]
        for j in (-1, 1):
            inner = pts[(2 * i + j) % 10]
            mx = (tip[0] + inner[0] + cx) / 3
            my = (tip[1] + inner[1] + cy) / 3
            ang = math.atan2(my - cy, mx - cx)
            t = 0.5 + 0.5 * math.cos(ang - light)
            # left/right halves of an arm get contrasting light
            t = t * 0.7 + (0.3 if j < 0 else 0.0)
            fd.polygon([(cx, cy), tip, inner], fill=lerp(dark, bright, t) + (255,))
    base.alpha_composite(facets)
    # vertical sheen over the facets
    sheen = vgrad(size, (0, cy - R, 0, cy + R),
                  [(0, (255, 236, 150)), (0.5, (240, 170, 40)), (1, (110, 50, 0))])
    fill_img(base, sheen, mul_alpha(smask, 0.18))
    # ridge lines (centre -> tips) for crispness
    rl = Image.new("L", size, 0)
    rd = ImageDraw.Draw(rl)
    for i in range(5):
        rd.line([(cx, cy), pts[2 * i]], fill=255, width=max(1, int(1.2 * s)))
    fill(base, (255, 250, 210, 150), ImageChops.multiply(rl, shrink(smask, 2 * s)))
    if core:
        # glowing cyan core: inner star + white-hot centre
        cpts = star_points(cx, cy, R * 0.40, R * 0.17)
        cmask = poly_mask(size, cpts)
        fill(base, INK, grow(cmask, 4 * s))
        glow(base, cmask, CYAN, R * 0.10, 1.4)
        cg = Image.new("RGB", size, CYAN_DEEP)
        disc = Image.new("L", size, 0)
        ImageDraw.Draw(disc).ellipse(
            (cx - R * 0.22, cy - R * 0.22, cx + R * 0.22, cy + R * 0.22), fill=255)
        fill_img(base, cg, cmask)
        fill(base, CYAN, ImageChops.multiply(
            cmask, disc.filter(ImageFilter.GaussianBlur(R * 0.08))))
        hot = Image.new("L", size, 0)
        ImageDraw.Draw(hot).ellipse(
            (cx - R * 0.07, cy - R * 0.07, cx + R * 0.07, cy + R * 0.07), fill=255)
        glow(base, hot, CYAN, R * 0.18, 2.0)
        fill(base, WHITE, hot.filter(ImageFilter.GaussianBlur(R * 0.03)))
        flare(base, cx, cy, R * 0.75, s * 1.6, WHITE, 0.9)
    return pts


def flare(base, x, y, length, thick, color, alpha=1.0):
    """4-point lens flare: two tapered spikes + soft core."""
    size = base.size
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    w = thick
    d.polygon([(x - length, y), (x, y - w), (x + length, y), (x, y + w)], fill=255)
    d.polygon([(x, y - length), (x + w, y), (x, y + length), (x - w, y)], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(max(1, thick * 0.4)))
    glow(base, m, color, thick * 2.5, 0.8 * alpha)
    fill(base, color + (int(255 * alpha),), m)


def sparks(base, rng, region, n, s, avoid=None):
    x0, y0, x1, y1 = region
    for _ in range(n):
        for _try in range(30):
            x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
            if avoid is None or not avoid(x, y):
                break
        r = rng.uniform(1.2, 3.2) * s
        col = lerp(GOLD, (255, 250, 220), rng.random())
        if rng.random() < 0.35:
            flare(base, x, y, r * rng.uniform(3.5, 6), r * 0.45, col, 0.95)
        else:
            m = Image.new("L", base.size, 0)
            ImageDraw.Draw(m).ellipse((x - r, y - r, x + r, y + r), fill=255)
            glow(base, m, (255, 170, 40), r * 2.2, 1.2)
            fill(base, col, m.filter(ImageFilter.GaussianBlur(r * 0.3)))


# ---------------------------------------------------------------- badge
def draw_badge(base, s, cy=505):
    size = base.size
    S = lambda pts: [(x * s, y * s) for x, y in pts]
    cx = 512
    plate = S([
        (60, cy), (118, cy - 78), (372, cy - 78), (408, cy - 112),
        (616, cy - 112), (652, cy - 78), (906, cy - 78), (964, cy),
        (906, cy + 78), (650, cy + 78), (cx, cy + 172), (374, cy + 78),
        (118, cy + 78),
    ])
    pm = poly_mask(size, plate)
    # wing fins left/right
    finL = S([(60, cy), (24, cy - 34), (90, cy - 40)])
    finR = S([(964, cy), (1000, cy - 34), (934, cy - 40)])
    fins = ImageChops.lighter(poly_mask(size, finL), poly_mask(size, finR))
    # outer glow + shadow
    glow(base, pm, CYAN_DEEP, 30 * s, 0.32)
    fill(base, (0, 0, 0, 180), shift(pm, 0, 10 * s).filter(ImageFilter.GaussianBlur(14 * s)))
    # fins
    fill(base, INK, grow(fins, 3 * s))
    fill_img(base, vgrad(size, (0, (cy - 40) * s, 0, cy * s),
                         [(0, (240, 196, 90)), (1, (120, 66, 12))]), fins)
    # rim: gold trim around a dark outline
    fill(base, INK, grow(pm, 6 * s))
    fill(base, (176, 120, 34), grow(pm, 3 * s))
    body = vgrad(size, ((cy - 112) * s, (cy - 112) * s, 0, (cy + 172) * s),
                 [(0, (52, 64, 88)), (0.35, (24, 32, 52)), (0.7, (12, 18, 34)),
                  (1, (30, 38, 58))])
    fill_img(base, body, mul_alpha(pm, 0.95))
    # gunmetal panel facets: top bevel lighter
    inner = shrink(pm, 9 * s)
    rim = ImageChops.subtract(pm, inner)
    topband = Image.new("L", size, 0)
    ImageDraw.Draw(topband).rectangle((0, 0, size[0], int((cy - 10) * s)), fill=255)
    fill(base, (110, 128, 160, 80), ImageChops.multiply(rim, topband))
    # cyan edge line just inside the rim
    edge = ImageChops.subtract(shrink(pm, 7 * s), shrink(pm, 10 * s))
    glow(base, edge, CYAN, 3 * s, 0.7)
    fill(base, CYAN + (200,), edge)
    # shoulder beacons: gold-rimmed pods with glowing cores
    for side in (-1, 1):
        px, py, pr = cx + side * 246, cy - 86, 30
        pod = Image.new("L", size, 0)
        ImageDraw.Draw(pod).ellipse(((px - pr) * s, (py - pr) * s,
                                     (px + pr) * s, (py + pr) * s), fill=255)
        fill(base, INK, grow(pod, 4 * s))
        fill_img(base, vgrad(size, ((py - pr) * s, (py - pr) * s, 0, (py + pr) * s),
                             [(0, (255, 236, 150)), (0.5, (214, 140, 30)),
                              (1, (110, 56, 8))]), pod)
        core_ = shrink(pod, 9 * s)
        fill(base, (10, 16, 30), core_)
        lamp = shrink(pod, 15 * s)
        glow(base, lamp, CYAN, 8 * s, 1.6)
        fill(base, (200, 250, 255), lamp)
    # inset dark channel where the word sits
    chan = S([(104, cy), (146, cy - 54), (878, cy - 54), (920, cy),
              (878, cy + 54), (146, cy + 54)])
    cm = poly_mask(size, chan)
    fill(base, (4, 7, 16, 225), cm)
    ce = ImageChops.subtract(cm, shrink(cm, 3 * s))
    fill(base, (60, 150, 200, 140), ce)
    # running light strips + rivets
    d = ImageDraw.Draw(base)
    for side in (-1, 1):
        for k in range(3):
            x = cx + side * (180 + k * 40)
            y0 = cy + 62
            strip = Image.new("L", size, 0)
            ImageDraw.Draw(strip).rectangle(
                ((x - 12) * s, (y0) * s, (x + 12) * s, (y0 + 6) * s), fill=255)
            glow(base, strip, CYAN, 5 * s, 1.3)
            fill(base, (210, 250, 255), strip)
        for x in (150, 300):
            rx = cx + side * (cx - x)
            rv = Image.new("L", size, 0)
            ImageDraw.Draw(rv).ellipse(((rx - 5) * s, (cy - 68) * s,
                                        (rx + 5) * s, (cy - 58) * s), fill=255)
            fill(base, (200, 160, 80), rv)
    # chevron cyan gem at the bottom point
    gem = S([(cx, cy + 92), (cx + 34, cy + 112), (cx, cy + 150), (cx - 34, cy + 112)])
    gm = poly_mask(size, gem)
    fill(base, INK, grow(gm, 3 * s))
    glow(base, gm, CYAN, 12 * s, 1.2)
    fill_img(base, vgrad(size, ((cy + 92) * s, (cy + 92) * s, 0, (cy + 150) * s),
                         [(0, (220, 255, 255)), (0.5, CYAN), (1, CYAN_DEEP)]), gm)
    return pm


# ---------------------------------------------------------------- outputs
def make_logo(out_path, seed=7):
    s = SS
    W = 1024 * s
    base = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    cy = 560
    draw_badge(base, s, cy=cy)
    # star above the word, overlapping the plate's crown
    draw_star(base, 512 * s, (cy - 190) * s, 178 * s, s)
    # flare spike on top tip
    flare(base, 512 * s, (cy - 368) * s, 70 * s, 2.2 * s, (255, 245, 210), 0.9)
    draw_wordmark(base, "SKYBREAKER", (512 * s, cy * s), 790 * s, s,
                  outline=7, max_h=86 * s)
    rng = random.Random(seed)
    sparks(base, rng, (150 * s, (cy - 330) * s, 874 * s, (cy - 100) * s), 14, s,
           avoid=lambda x, y: abs(x - 512 * s) < 210 * s)
    sparks(base, rng, (300 * s, (cy + 90) * s, 724 * s, (cy + 200) * s), 6, s,
           avoid=lambda x, y: abs(x - 512 * s) < 60 * s)
    # Fit the emblem to ~98% of the canvas width (vertically centred) so the
    # HUD, which scales the whole square, shows as much emblem as possible.
    bbox = base.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    crop = base.crop(bbox)
    tw = int(1024 * 0.98)
    th = max(1, round(crop.height * tw / crop.width))
    emb = crop.resize((tw, th), Image.LANCZOS)
    img = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    img.alpha_composite(emb, ((1024 - tw) // 2, (1024 - th) // 2))
    img.save(out_path, optimize=True)
    return img


def space_bg(size, seed=3, s=1):
    W, H = size
    bg = Image.new("RGB", size, NAVY)
    # radial lift toward the centre
    lift = Image.new("L", size, 0)
    ImageDraw.Draw(lift).ellipse((W * 0.1, H * 0.05, W * 0.9, H * 0.85), fill=255)
    lift = lift.filter(ImageFilter.GaussianBlur(W * 0.18))
    bg = Image.composite(Image.new("RGB", size, (18, 34, 74)), bg, lift)
    rng = random.Random(seed)
    # faint nebula wisps
    neb = Image.new("RGBA", size, (0, 0, 0, 0))
    for col, n in (((40, 120, 200), 5), ((90, 60, 160), 3)):
        for _ in range(n):
            m = Image.new("L", size, 0)
            x, y = rng.uniform(0, W), rng.uniform(0, H)
            r = rng.uniform(0.12, 0.25) * W
            ImageDraw.Draw(m).ellipse((x - r, y - r * 0.6, x + r, y + r * 0.6), fill=60)
            fill(neb, col, m.filter(ImageFilter.GaussianBlur(r * 0.6)))
    bg = Image.alpha_composite(bg.convert("RGBA"), neb)
    d = ImageDraw.Draw(bg)
    for _ in range(int(W * H / (2600 * s * s))):
        x, y = rng.uniform(0, W), rng.uniform(0, H)
        r = rng.choice([0.5, 0.6, 0.8, 1.0, 1.4]) * s
        b = rng.randint(90, 255)
        tint = rng.random()
        c = lerp((b, b, b), (int(b * 0.7), b, b), tint)
        d.ellipse((x - r, y - r, x + r, y + r), fill=c + (255,))
    return bg


def make_icon(out_path):
    s = SS
    W = 1024 * s
    base = space_bg((W, W), seed=11, s=s)
    base = base.filter(ImageFilter.GaussianBlur(s * 0.4))
    cx, cy = 512 * s, 430 * s
    # big cyan aura + subtle gold halo ring
    aura = Image.new("L", (W, W), 0)
    ImageDraw.Draw(aura).ellipse((cx - 300 * s, cy - 300 * s, cx + 300 * s, cy + 300 * s), fill=150)
    fill(base, CYAN_DEEP, aura.filter(ImageFilter.GaussianBlur(120 * s)))
    ring = Image.new("L", (W, W), 0)
    rd = ImageDraw.Draw(ring)
    rd.ellipse((cx - 360 * s, cy - 360 * s, cx + 360 * s, cy + 360 * s), outline=255, width=6 * s)
    glow(base, ring, CYAN, 10 * s, 1.0)
    fill(base, (160, 240, 255, 150), ring)
    draw_star(base, cx, cy, 330 * s, s)
    flare(base, cx, cy - 345 * s, 110 * s, 3.5 * s, (255, 245, 210), 0.9)
    # dark band behind the word for contrast at small sizes
    band = Image.new("L", (W, W), 0)
    ImageDraw.Draw(band).rectangle((0, 760 * s, W, 940 * s), fill=255)
    fill(base, (2, 4, 12, 170), band.filter(ImageFilter.GaussianBlur(30 * s)))
    draw_wordmark(base, "SKYBREAKER", (512 * s, 850 * s), 930 * s, s,
                  outline=9, max_h=120 * s)
    rng = random.Random(5)
    sparks(base, rng, (80 * s, 80 * s, 944 * s, 720 * s), 12, s,
           avoid=lambda x, y: math.hypot(x - cx, y - cy) < 360 * s)
    img = base.convert("RGB").resize((1024, 1024), Image.LANCZOS)
    img.save(out_path, optimize=True)
    return img


def make_adaptive(fg_path, bg_path):
    s = SS
    W = 432 * s
    fg = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    c = W / 2
    # safe zone = central 66% (285 px); star outer radius kept at ~128 px
    draw_star(fg, c, c + 6 * s, 128 * s, s)
    fg.resize((432, 432), Image.LANCZOS).save(fg_path, optimize=True)
    bg = space_bg((W, W), seed=11, s=s)
    aura = Image.new("L", (W, W), 0)
    ImageDraw.Draw(aura).ellipse((c - 150 * s, c - 150 * s, c + 150 * s, c + 150 * s), fill=140)
    fill(bg, CYAN_DEEP, aura.filter(ImageFilter.GaussianBlur(60 * s)))
    bg.convert("RGB").resize((432, 432), Image.LANCZOS).save(bg_path, optimize=True)


# ---------------------------------------------------------------- hero patch
HERO_SRC = os.path.join(os.path.dirname(ROOT), "Skybreaker-png-backup",
                        "mainmenuphotoskybreaker_starbreaker.png")
# saturated painted-gold chrome (the hero art is more yellow than the logo)
HERO_STOPS = [
    (0.00, (255, 232, 110)),
    (0.38, (255, 226, 70)),
    (0.47, (220, 146, 18)),
    (0.53, (140, 74, 4)),
    (0.60, (236, 166, 26)),
    (0.85, (255, 206, 56)),
    (1.00, (186, 106, 8)),
]
# Old STARBREAKER lettering on the painted badge (1x pixel coords)
HERO_BAND = (96, 304, 930, 420)       # area that may be repainted
HERO_TEXT_BOX = (110, 321, 912, 412)  # where the old letters sat


def _gold_mask(img, box):
    """Old painted gold letters inside box (L mask, full size)."""
    m = Image.new("L", img.size, 0)
    src, mp = img.load(), m.load()
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = src[x, y]
            if r > 120 and g > 90 and r - b > 60:
                mp[x, y] = 255
    return m


def _inpaint(img, hole, iters=60):
    """Diffusion fill: repeatedly blur and restore the known pixels."""
    known = hole.point(lambda v: 255 - v)
    cur = img.copy()
    for i in range(iters):
        r = max(1, 12 - i // 5)
        cur = Image.composite(img, cur.filter(ImageFilter.GaussianBlur(r)), known)
    return cur


def make_hero(out_path, src_path=HERO_SRC):
    src = Image.open(src_path).convert("RGB")
    W, H = src.size
    # 1) hole = the whole lettering channel (feathered) + any gold that
    #    pokes out of it (tall R/B tops)
    hole = Image.new("L", src.size, 0)
    ImageDraw.Draw(hole).rectangle(HERO_TEXT_BOX, fill=255)
    gm = _gold_mask(src, HERO_BAND)
    hole = ImageChops.lighter(hole, grow(gm, 4).point(lambda v: 255 if v > 20 else 0))
    band = Image.new("L", src.size, 0)
    ImageDraw.Draw(band).rectangle(HERO_BAND, fill=255)
    hole = ImageChops.multiply(hole, band)
    # 2) plate fill: the channel's own dark tone (sampled from the dark
    #    pixels of the plate strip above the letters) + its sparkle/paint
    #    texture cloned from that strip, mirrored and staggered
    strip = (140, 306, 470, 320)
    tex_src = src.crop(strip)
    darks = [p for p in tex_src.get_flattened_data() if sum(p) < 150]
    base_col = tuple(sorted(c[i] for c in darks)[len(darks) // 2] for i in range(3))
    tx0, ty0, tx1, ty1 = HERO_TEXT_BOX
    fill_img_ = vgrad(src.size, (0, ty0 - 4, 0, ty1 + 4),
                      [(0, lerp(base_col, (0, 0, 0), 0.25)), (0.5, base_col),
                       (1, lerp(base_col, (20, 60, 110), 0.35))])
    tex = Image.new("RGB", (W, H))
    th = tex_src.height
    flip = tex_src.transpose(Image.FLIP_TOP_BOTTOM)
    for yi, y in enumerate(range(0, H, th)):
        for x in range(-113, W, tex_src.width):
            tex.paste(flip if yi % 2 else tex_src, (x + (yi * 97) % 113, y))
    hp = ImageChops.subtract(tex, tex.filter(ImageFilter.GaussianBlur(3)), 1, 128)
    grained = ImageChops.add(fill_img_, hp, 1, -128)
    soft = hole.filter(ImageFilter.GaussianBlur(2.5))
    patched = Image.composite(grained, src, soft)

    # 3) new SKYBREAKER wordmark rendered at 4x on a band canvas
    s = SS
    bx0, by0, bx1, by1 = HERO_BAND
    bx0, by0, bx1, by1 = bx0 - 20, by0 - 20, bx1 + 20, by1 + 20
    bw, bh = bx1 - bx0, by1 - by0
    canvas = Image.new("RGBA", (bw * s, bh * s), (0, 0, 0, 0))
    tx0, ty0, tx1, ty1 = HERO_TEXT_BOX
    cx = ((tx0 + tx1) / 2 - bx0) * s
    cy = ((ty0 + ty1) / 2 - by0) * s
    (bb, tm) = draw_wordmark(canvas, "SKYBREAKER", (cx, cy), (tx1 - tx0) * s, s,
                             outline=4, max_h=(ty1 - ty0) * s * 0.92,
                             tracking=0.035, rim=(255, 170, 50),
                             glow_strength=0.18, return_mask=True,
                             stops=HERO_STOPS)
    word = canvas.resize((bw, bh), Image.LANCZOS)
    tmask = tm.resize((bw, bh), Image.LANCZOS)
    # 4) borrow the painting's own gold grain so the letters look painted
    #    (seeded noise, not the old pixels, so no STARBREAKER ghost shows)
    rng = random.Random(21)
    noise = Image.new("L", (bw, bh))
    noise.putdata([max(0, min(255, int(rng.gauss(128, 14)))) for _ in range(bw * bh)])
    grain = noise.filter(ImageFilter.GaussianBlur(0.6))
    gr = Image.merge("RGB", (grain, grain, grain))
    wr = word.convert("RGB")
    wr = ImageChops.add(wr, gr, 1, -128)
    word = Image.merge("RGBA", (*Image.composite(wr, word.convert("RGB"), tmask).split(),
                                 word.getchannel("A")))
    out = patched.convert("RGBA")
    out.alpha_composite(word, (bx0, by0))
    out.convert("RGB").save(out_path, optimize=True)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "assets", "sprites", "ui"))
    ap.add_argument("--only", choices=["logo", "icon", "adaptive", "hero"], default=None)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    if a.only in (None, "logo"):
        make_logo(os.path.join(a.out, "gamelogo.png"))
    if a.only in (None, "icon"):
        make_icon(os.path.join(a.out, "app_icon_1024.png"))
    if a.only == "hero":  # explicit only: it rewrites a painted asset
        make_hero(os.path.join(a.out, "mainmenuphotoskybreaker.png"))
    if a.only in (None, "adaptive"):
        make_adaptive(os.path.join(a.out, "icon_fg_432.png"),
                      os.path.join(a.out, "icon_bg_432.png"))
    print("wrote to", a.out)


if __name__ == "__main__":
    main()
