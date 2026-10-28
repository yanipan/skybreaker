#!/usr/bin/env python3
"""Compose the 32 store screenshots from real gameplay masters.

Masters come from scripts/tools/ShotDirector.gd and live in
assets/store/screenshots/master_gameplay/<phone|tablet|tablet_android>/.
Each device gets 8 PNGs written over the existing slugs 01..08 so the
upload scripts keep working:

  ios_phone       1290x2796  <- phone master, 1:1
  android_phone   1080x2340  <- phone master, Lanczos downscale (0.837x)
  ios_tablet      2048x2732  <- tablet master, 1:1
  android_tablet  1600x2560  <- tablet_android master, 1:1 (captured natively,
                                so the HUD edges are not cropped away)

Layout: the gameplay frame fills the canvas edge to edge (never scaled up,
never letterboxed); a dark gradient band over the top ~20% carries the
headline (Orbitron, cyan #8CF2FF, black outline) and subline; a small gold
SKYBREAKER brand line sits at the bottom. A per-beat `shift` moves the frame
down (cropping the bottom) when the top of the frame holds something that
must stay visible, e.g. the shop's funds line; the band then sits on solid
dark space.

Usage:
  python3 scripts/tools/compose_store_shots.py [--sheet DIR]
  Pick a different alternate by editing PICKS below (e.g. "03_chaos_a").
"""
import argparse
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SHOTS = os.path.join(ROOT, "assets", "store", "screenshots")
MASTERS = os.path.join(SHOTS, "master_gameplay")
FONT_HEAD = os.path.join(ROOT, "assets", "fonts", "Orbitron.ttf")
FONT_BODY = os.path.join(ROOT, "assets", "fonts", "Rajdhani-Medium.ttf")

CYAN = (140, 242, 255)
GOLD = (255, 217, 102)
WHITE = (240, 246, 255)
BG = (5, 10, 26)
BAND = 0.20  # headline band, fraction of canvas height

DEVICES = [
    {"folder": "ios_phone", "w": 1290, "h": 2796, "master": "phone"},
    {"folder": "ios_tablet", "w": 2048, "h": 2732, "master": "tablet"},
    {"folder": "android_phone", "w": 1080, "h": 2340, "master": "phone"},
    {"folder": "android_tablet", "w": 1600, "h": 2560, "master": "tablet_android"},
]

# slug (existing file name) -> chosen master + copy. `shift` is a fraction
# of canvas height the frame moves down.
BEATS = [
    {"slug": "01_hand_painted_shmup", "pick": "01_title", "shift": 0.05, "brand": False,
     "head": "A HAND-PAINTED SHMUP", "sub": "20 sectors. 5 bosses. One ending."},
    {"slug": "02_one_pilot", "pick": "02_combat_c", "shift": 0.0,
     "head": "DRAG TO FLY. TAP TO FIRE.", "sub": "Built for one hand."},
    {"slug": "03_story_that_matters", "pick": "03_chaos_c", "shift": 0.0,
     "head": "20 SECTORS OF ESCALATING FIRE", "sub": ""},
    {"slug": "04_twenty_sectors", "pick": "04_beam_c", "shift": 0.0,
     "head": "THREE WEAPON SYSTEMS", "sub": "Phaser. Plasma Beam. Homing Missiles."},
    {"slug": "05_answer_the_signal", "pick": "05_torpedo_b", "shift": 0.0,
     "head": "TORPEDOES CLEAR THE SKY", "sub": "When the screen fills up, fire one."},
    {"slug": "06_built_for_one_hand", "pick": "06_boss_c", "shift": 0.0,
     "head": "FIVE BOSSES THAT FIGHT BACK", "sub": ""},
    {"slug": "07_no_ads_no_iap", "pick": "07_shop", "shift": 0.16, "brand": False,
     "head": "UPGRADE BETWEEN SECTORS", "sub": "Hull. Shields. Engines. Energy cells."},
    {"slug": "08_deeper_out", "pick": "08_story_b", "shift": 0.0,
     "head": "A STORY THAT MATTERS", "sub": "Six painted cutscenes. Free. No ads. No IAP."},
]

# Per-master-set overrides when a different alternate reads better there.
PICK_OVERRIDES = {
    "tablet": {"04_twenty_sectors": "04_beam_b"},
    "tablet_android": {},
}


def head_font(size):
    f = ImageFont.truetype(FONT_HEAD, size)
    try:
        f.set_variation_by_name("Black")
    except Exception:
        try:
            f.set_variation_by_name("Bold")
        except Exception:
            pass
    return f


def body_font(size):
    return ImageFont.truetype(FONT_BODY, size)


def wrap(draw, text, font, max_w, stroke):
    """Greedy word wrap; returns list of lines."""
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if draw.textlength(t, font=font) + 2 * stroke <= max_w or not cur:
            cur = t
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def fit_headline(draw, text, W, U, max_lines=2):
    """Largest Orbitron size whose wrapped text fits 90% width in <= 2 lines."""
    size = int(U * 0.088)
    while size > 20:
        f = head_font(size)
        stroke = max(3, size // 9)
        lines = wrap(draw, text, f, W * 0.90, stroke)
        if len(lines) <= max_lines and all(
                draw.textlength(l, font=f) + 2 * stroke <= W * 0.90 for l in lines):
            # Balance two-line headlines so the lines are similar in width.
            if len(lines) == 2:
                words = text.split()
                best = None
                for i in range(1, len(words)):
                    a, b = " ".join(words[:i]), " ".join(words[i:])
                    wa, wb = draw.textlength(a, font=f), draw.textlength(b, font=f)
                    if max(wa, wb) + 2 * stroke <= W * 0.90:
                        score = abs(wa - wb)
                        if best is None or score < best[0]:
                            best = (score, [a, b])
                if best:
                    lines = best[1]
            return f, stroke, lines
        size -= 2
    raise RuntimeError("headline does not fit: " + text)


def gradient(W, H, top, a_top, a_full_until, a_zero_at):
    """Black overlay: alpha a_top from `top` to a_full_until, fading to 0 at a_zero_at."""
    ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for y in range(top, min(H, a_zero_at)):
        if y <= a_full_until:
            a = a_top
        else:
            k = (y - a_full_until) / max(1, (a_zero_at - a_full_until))
            a = int(a_top * (1.0 - k) ** 1.6)
        d.line([(0, y), (W, y)], fill=(0, 0, 0, a))
    return ov


def bottom_gradient(W, H, height, a_max):
    ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    y0 = H - height
    for y in range(y0, H):
        k = (y - y0) / height
        d.line([(0, y), (W, y)], fill=(0, 0, 0, int(a_max * k ** 1.3)))
    return ov


def load_master(master_set, pick, W, H):
    path = os.path.join(MASTERS, master_set, pick + ".png")
    im = Image.open(path).convert("RGB")
    if im.size == (W, H):
        return im
    # Only downscale (android_phone from the phone master). Cover-fit then
    # centre-crop the sub-pixel remainder.
    s = max(W / im.width, H / im.height)
    if s > 1.0:
        raise RuntimeError("refusing to upscale %s by %.3f" % (path, s))
    nw, nh = round(im.width * s), round(im.height * s)
    im = im.resize((max(nw, W), max(nh, H)), Image.LANCZOS)
    x0, y0 = (im.width - W) // 2, (im.height - H) // 2
    return im.crop((x0, y0, x0 + W, y0 + H))


def compose(dev, beat):
    W, H = dev["w"], dev["h"]
    pick = PICK_OVERRIDES.get(dev["master"], {}).get(beat["slug"], beat["pick"])
    frame = load_master(dev["master"], pick, W, H)
    canvas = Image.new("RGB", (W, H), BG)
    shift = int(H * beat["shift"])
    canvas.paste(frame.crop((0, 0, W, H - shift)), (0, shift))
    canvas = canvas.convert("RGBA")

    band_h = int(H * BAND)
    canvas.alpha_composite(gradient(W, H, 0, 246, int(band_h * 0.80), band_h + int(H * 0.05)))
    if beat.get("brand", True):
        canvas.alpha_composite(bottom_gradient(W, H, int(H * 0.08), beat.get("fade", 170)))

    d = ImageDraw.Draw(canvas)
    # Type scales with a phone-shaped unit so tablets do not get giant text.
    U = min(W, int(H * 0.4615))
    f, stroke, lines = fit_headline(d, beat["head"], W, U)
    asc, desc = f.getmetrics()
    line_h = int((asc + desc) * 1.02)
    sub_f = body_font(int(U * 0.046))
    sub_lines = wrap(d, beat["sub"], sub_f, W * 0.90, 2) if beat["sub"] else []
    if len(sub_lines) > 2:
        raise RuntimeError("subline too long: " + beat["sub"])
    sasc, sdesc = sub_f.getmetrics()
    sub_h = int((sasc + sdesc) * 1.05)
    gap = int(H * 0.012) if sub_lines else 0
    block = line_h * len(lines) + gap + sub_h * len(sub_lines)
    y = max(int(H * 0.03), (band_h - block) // 2)
    for l in lines:
        d.text((W / 2, y), l, font=f, fill=CYAN, anchor="ma",
               stroke_width=stroke, stroke_fill=(0, 0, 0))
        y += line_h
    y += gap
    for l in sub_lines:
        d.text((W / 2, y), l, font=sub_f, fill=WHITE, anchor="ma",
               stroke_width=max(2, U // 400), stroke_fill=(0, 0, 0))
        y += sub_h
    if y > band_h + H * 0.02:
        raise RuntimeError("text overflows band on %s/%s" % (dev["folder"], beat["slug"]))

    if not beat.get("brand", True):
        # Title shows the full logo; on the shop the line would sit on BUY buttons.
        return canvas.convert("RGB")
    bf = head_font(int(U * 0.036))
    d.text((W / 2, H - int(H * 0.022)), "SKYBREAKER", font=bf, fill=GOLD, anchor="md",
           stroke_width=max(2, U // 320), stroke_fill=(0, 0, 0))
    return canvas.convert("RGB")


def contact_sheet(paths, out, thumb_w=300, cols=8, label=True):
    """One row per `cols` images; each row is as tall as its tallest thumb."""
    ims = [Image.open(p).convert("RGB") for p in paths]
    pad = 22 if label else 6
    rows = [ims[i:i + cols] for i in range(0, len(ims), cols)]
    heights = [max(int(thumb_w * im.height / im.width) for im in r) + pad for r in rows]
    sheet = Image.new("RGB", (cols * (thumb_w + 6) + 6, sum(heights) + 6), (235, 235, 235))
    d = ImageDraw.Draw(sheet)
    y = 6
    for ri, r in enumerate(rows):
        for ci, im in enumerate(r):
            p = paths[ri * cols + ci]
            t = im.resize((thumb_w, int(thumb_w * im.height / im.width)), Image.LANCZOS)
            x = 6 + ci * (thumb_w + 6)
            if label:
                d.text((x, y), os.path.relpath(p, SHOTS), fill=(0, 0, 0))
            sheet.paste(t, (x, y + pad - 6))
        y += heights[ri]
    sheet.save(out)
    print("sheet", out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", help="directory for contact sheets")
    args = ap.parse_args()
    outs = []
    for dev in DEVICES:
        for beat in BEATS:
            img = compose(dev, beat)
            assert img.size == (dev["w"], dev["h"])
            p = os.path.join(SHOTS, dev["folder"], beat["slug"] + ".png")
            img.save(p, optimize=True)
            outs.append(p)
            print("wrote", os.path.relpath(p, ROOT), img.size)
    if args.sheet:
        os.makedirs(args.sheet, exist_ok=True)
        contact_sheet(outs, os.path.join(args.sheet, "store_shots_all.png"))
        chosen = []
        for m in ("phone", "tablet", "tablet_android"):
            for b in BEATS:
                pick = PICK_OVERRIDES.get(m, {}).get(b["slug"], b["pick"])
                chosen.append(os.path.join(MASTERS, m, pick + ".png"))
        contact_sheet(chosen, os.path.join(args.sheet, "masters_chosen.png"))


if __name__ == "__main__":
    main()
