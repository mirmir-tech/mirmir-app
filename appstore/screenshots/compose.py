#!/usr/bin/env python3
"""Mac App Store screenshots for Mirmir: 2880x1800 PNG, one set per locale.

    python3 compose.py            # every locale in captions.json
    python3 compose.py pl         # one locale

Reads raw window captures from raw/<name>.(png|webp) and captions from
captions.json, writes out/<locale>/<NN-name>.png. Needs Pillow.
Raw captures: the main window at its default 1280x800 points (2x), or the
menu bar panel, taken with Cmd-Shift-4, Space, Option-click (no shadow).
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent
W, H = 2880, 1800

# Website dark palette (web/public/assets/theme.css).
CANVAS = (17, 21, 28)
INK = (237, 241, 247)
MUTED = (172, 184, 200)
SIGNAL = (133, 173, 255)
BORDER = (52, 65, 81)


def font(name, size):
    return ImageFont.truetype(str(ROOT / "fonts" / f"{name}.ttf"), size)


def raw(name):
    for ext in ("png", "webp", "jpg"):
        path = ROOT / "raw" / f"{name}.{ext}"
        if path.exists():
            return Image.open(path).convert("RGB")
    sys.exit(f"missing raw/{name}.png")


def background():
    img = Image.new("RGB", (W, H), CANVAS)
    # A soft glacier glow behind the headline; nothing busy.
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse((W * 0.18, -H * 0.55, W * 0.82, H * 0.45), fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(260))
    tint = Image.new("RGB", (W, H), (36, 52, 84))
    return Image.composite(tint, img, glow.point(lambda v: int(v * 0.55)))


def rounded(shot, radius):
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *shot.size), radius, fill=255)
    return mask


def place(canvas, shot, x, y, radius):
    """Pastes a capture with rounded corners, a hairline border and a shadow."""
    w, h = shot.size
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((x, y + 28, x + w, y + h + 28), radius, fill=170)
    shadow = shadow.filter(ImageFilter.GaussianBlur(60))
    canvas.paste((0, 0, 0), (0, 0), shadow)
    canvas.paste(shot, (x, y), rounded(shot, radius))
    ImageDraw.Draw(canvas).rounded_rectangle((x, y, x + w - 1, y + h - 1), radius, outline=BORDER, width=2)


def wrap(draw, text, fnt, width):
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=fnt) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    return lines + [line]


def window_slide(cap, shot):
    img = background()
    draw = ImageDraw.Draw(img)
    head = font("SpaceGrotesk-Bold", 112)
    sub = font("Inter-Regular", 46)
    lead, accent = cap["lead"] + " ", cap["accent"]
    total = draw.textlength(lead, font=head) + draw.textlength(accent, font=head)
    x = (W - total) / 2
    draw.text((x, 110), lead, font=head, fill=INK)
    draw.text((x + draw.textlength(lead, font=head), 110), accent, font=head, fill=SIGNAL)
    y = 268
    for line in wrap(draw, cap["sub"], sub, 2200):
        draw.text(((W - draw.textlength(line, font=sub)) / 2, y), line, font=sub, fill=MUTED)
        y += 62
    target_w = 2000
    shot = shot.resize((target_w, round(shot.height * target_w / shot.width)), Image.LANCZOS)
    top = max(y + 40, 410)
    if top + shot.height > H - 40:
        shot = shot.resize((round(shot.width * (H - 40 - top) / shot.height), H - 40 - top), Image.LANCZOS)
    place(img, shot, (W - shot.width) // 2, top, 22)
    return img


def panel_slide(cap, shot):
    img = background()
    draw = ImageDraw.Draw(img)
    target_h = 1480
    shot = shot.resize((round(shot.width * target_h / shot.height), target_h), Image.LANCZOS)
    px = W - 300 - shot.width
    place(img, shot, px, (H - target_h) // 2, 34)
    head = font("SpaceGrotesk-Bold", 132)
    sub = font("Inter-Regular", 52)
    column = px - 260 - 220
    lines = [(l, INK) for l in wrap(draw, cap["lead"], head, column)]
    lines += [(l, SIGNAL) for l in wrap(draw, cap["accent"], head, column)]
    subs = wrap(draw, cap["sub"], sub, column)
    block = len(lines) * 150 + 50 + len(subs) * 72
    y = (H - block) / 2
    for text, color in lines:
        draw.text((260, y), text, font=head, fill=color)
        y += 150
    y += 50
    for text in subs:
        draw.text((260, y), text, font=sub, fill=MUTED)
        y += 72
    return img


def main():
    config = json.loads((ROOT / "captions.json").read_text())
    locales = sys.argv[1:] or [k for k in config["slides"][0] if "-" in k or len(k) == 2]
    for locale in locales:
        out = ROOT / "out" / locale
        out.mkdir(parents=True, exist_ok=True)
        for slide in config["slides"]:
            shot = raw(slide["raw"])
            build = panel_slide if slide["layout"] == "panel" else window_slide
            img = build(slide[locale], shot)
            assert img.size == (W, H)
            path = out / f"{slide['file']}.png"
            img.save(path, optimize=True)
            print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
