"""Generates the Roku channel art from the brand files (run: python3 tools/make_assets.py, needs Pillow).

Outputs into roku-app/images/:
  channel-poster_hd.png  336x210   (manifest mm_icon_focus_hd)
  channel-poster_sd.png  246x140   (manifest mm_icon_focus_sd, older models)
  splash_hd.png 1280x720, splash_fhd.png 1920x1080, splash_sd.png 720x480

Source art: store/assets/firetv-app-icon-1280x720.png (the Church TV OS lockup on the brand's dark navy).
The manifest's splash_color is read from the source art and printed so the two stay in step."""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
SRC = os.path.join(ROOT, "store", "assets", "firetv-app-icon-1280x720.png")
OUT = os.path.join(HERE, "..", "images")

art = Image.open(SRC).convert("RGB")
bg = art.getpixel((4, 4))


def canvas(w, h):
    return Image.new("RGB", (w, h), bg)


def fit_into(w, h, scale_w_fraction, crop=None):
    """Place the lockup (optionally cropped) centred on a w x h canvas at a given fraction of the canvas width."""
    src = art.crop(crop) if crop else art
    target_w = int(w * scale_w_fraction)
    ratio = target_w / src.width
    target_h = int(src.height * ratio)
    if target_h > h * 0.92:
        ratio = (h * 0.92) / src.height
        target_w, target_h = int(src.width * ratio), int(src.height * ratio)
    im = canvas(w, h)
    im.paste(src.resize((target_w, target_h), Image.LANCZOS), ((w - target_w) // 2, (h - target_h) // 2))
    return im


# The lockup occupies roughly x 180..1190, y 185..535 of the 1280x720 source: crop to it so the poster is not mostly empty.
LOCKUP = (150, 150, 1230, 570)
fit_into(336, 210, 0.92, LOCKUP).save(os.path.join(OUT, "channel-poster_hd.png"))
fit_into(246, 140, 0.92, LOCKUP).save(os.path.join(OUT, "channel-poster_sd.png"))
fit_into(1280, 720, 1.0).save(os.path.join(OUT, "splash_hd.png"))
fit_into(1920, 1080, 1.0).save(os.path.join(OUT, "splash_fhd.png"))
fit_into(720, 480, 1.0).save(os.path.join(OUT, "splash_sd.png"))
print("splash_color=#%02X%02X%02X" % bg)


# ---- gradient ramps for Slides backgrounds -------------------------------------------------------------------------
# Roku has no gradient node. A gradient from colour A to colour B is drawn as a solid A rectangle with one of these white
# images on top, tinted B (Poster.blendColor): the image's alpha ramps 0 -> 255 along the CSS linear-gradient angle
# (0 = to top, 90 = to right, 180 = to bottom), with the same colour stops spacing as CSS and Android.
# L_<deg>.png is for landscape (16:9) and P_<deg>.png for portrait (9:16) screens; degrees step by 15.
import math

RAMPS = os.path.join(OUT, "ramps")
os.makedirs(RAMPS, exist_ok=True)


def ramp(deg, w, h):
    rad = math.radians(deg)
    dx, dy = math.sin(rad), -math.cos(rad)
    length = abs(w * math.sin(rad)) + abs(h * math.cos(rad))
    im = Image.new("RGBA", (w, h))
    px = im.load()
    for y in range(h):
        for x in range(w):
            t = ((x + 0.5 - w / 2) * dx + (y + 0.5 - h / 2) * dy) / length + 0.5
            t = min(1.0, max(0.0, t))
            px[x, y] = (255, 255, 255, int(round(t * 255)))
    return im


for deg in range(0, 360, 15):
    ramp(deg, 160, 90).save(os.path.join(RAMPS, "L_%d.png" % deg), optimize=True)
    ramp(deg, 90, 160).save(os.path.join(RAMPS, "P_%d.png" % deg), optimize=True)
print("ramps written:", len(os.listdir(RAMPS)))
