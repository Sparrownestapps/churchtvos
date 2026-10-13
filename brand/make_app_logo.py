"""Builds the Church TV OS launcher icons + TV banner from concept A (arched play pane + three screens).
Run: python3 make_app_logo.py   (needs Pillow). Writes brand/app-logo/ and the Android res folders."""
import os
from PIL import Image, ImageDraw, ImageFont
from make_concepts import FONT, INK, WHITE, AMBER, N, S
from make_concepts2 import a as icon_art

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "..", "tv-app", "app", "src", "main", "res")


def icon(size=512):
    return icon_art().resize((size, size), Image.LANCZOS)


def banner():
    w, h = 320 * S, 180 * S
    im = Image.new("RGBA", (w, h), INK + (255,))
    mark = icon_art().resize((round(h * .72), round(h * .72)), Image.LANCZOS)
    im.alpha_composite(mark, (round(w * .08), (h - mark.height) // 2))
    d = ImageDraw.Draw(im)
    big = ImageFont.truetype(FONT, round(h * .20))
    small = ImageFont.truetype(FONT, round(h * .29))
    x, top = round(w * .46), round(h * .2)
    d.text((x, top), "CHURCH", font=big, fill=WHITE)
    d.text((x, top + round(h * .23)), "TV OS", font=small, fill=AMBER)
    return im.resize((320, 180), Image.LANCZOS)


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
