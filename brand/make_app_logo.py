"""Builds the Church TV OS app banner + launcher icons (PLACEHOLDER artwork: TV with a cross-shaped play glyph).
Run: python3 make_app_logo.py   (needs Pillow). Writes brand/app-logo/ and the Android res folders."""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "..", "tv-app", "app", "src", "main", "res")
FONT = os.path.join(RES, "font", "lato_black.ttf")
NAVY, AMBER, WHITE = (27, 42, 74, 255), (242, 163, 58, 255), (255, 255, 255, 255)
S = 4  # supersample, then scale down for crisp edges


def tv(width):
    """White TV with a navy screen and an amber cross."""
    sh, stand = round(width * 0.66), round(width * 0.12)
    im = Image.new("RGBA", (width, sh + stand), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, width - 1, sh - 1), radius=round(width * 0.1), fill=WHITE)
    d.rectangle((round(width * 0.44), sh - 2, round(width * 0.56), sh + round(stand * 0.55)), fill=WHITE)
    d.rounded_rectangle((round(width * 0.3), sh + round(stand * 0.5), round(width * 0.7), sh + stand - 1),
                        radius=round(stand * 0.25), fill=WHITE)
    inset = round(width * 0.05)
    d.rounded_rectangle((inset, inset, width - 1 - inset, sh - 1 - inset), radius=round(width * 0.06), fill=NAVY)
    cx, cy, t = width // 2, sh // 2, round(sh * 0.065)
    arm_v, arm_h = round(sh * 0.29), round(sh * 0.19)
    d.rounded_rectangle((cx - t, cy - arm_v, cx + t, cy + arm_v), radius=t // 2, fill=AMBER)
    d.rounded_rectangle((cx - arm_h, cy - round(sh * 0.12) - t, cx + arm_h, cy - round(sh * 0.12) + t), radius=t // 2, fill=AMBER)
    return im


def banner():
    w, h = 320 * S, 180 * S
    im = Image.new("RGBA", (w, h), NAVY)
    t = tv(round(w * 0.30))
    im.alpha_composite(t, (round(w * 0.07), (h - t.height) // 2))
    d = ImageDraw.Draw(im)
    big = ImageFont.truetype(FONT, round(h * 0.20))
    small = ImageFont.truetype(FONT, round(h * 0.34))
    x, top = round(w * 0.45), round(h * 0.2)
    d.text((x, top), "CHURCH", font=big, fill=WHITE)
    d.text((x, top + round(h * 0.23)), "TV OS", font=small, fill=AMBER)
    return im.resize((320, 180), Image.LANCZOS)


def icon(size=512):
    w = size * S
    im = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    ImageDraw.Draw(im).rounded_rectangle((0, 0, w - 1, w - 1), radius=round(w * 0.22), fill=NAVY)
    t = tv(round(w * 0.66))
    im.alpha_composite(t, ((w - t.width) // 2, (w - t.height) // 2))
    return im.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    out = os.path.join(HERE, "app-logo")
    os.makedirs(out, exist_ok=True)
    b, i = banner().convert("RGB"), icon()
    b.save(os.path.join(out, "banner-320x180.png"))
    i.save(os.path.join(out, "icon-512.png"))
    b.save(os.path.join(RES, "drawable-xhdpi", "banner.png"))
    for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        i.resize((px, px), Image.LANCZOS).save(os.path.join(RES, f"mipmap-{folder}", "ic_launcher.png"))
    print("saved")
