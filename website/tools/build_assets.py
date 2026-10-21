"""Builds website/assets from the repo's brand + screenshot sources.
Run from anywhere:  PYTHONPATH=<dir with fonttools+brotli> python3 website/tools/build_assets.py
Needs Pillow (images) and fonttools + brotli (font subsetting to woff2)."""
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.join(HERE, "..", "static")
ROOT = os.path.join(HERE, "..", "..")
IMG = os.path.join(WEB, "assets", "img")
FONTS = os.path.join(WEB, "assets", "fonts")
os.makedirs(IMG, exist_ok=True); os.makedirs(FONTS, exist_ok=True)

def save(im, name, webp_q=80):
    im.convert("RGBA" if im.mode == "RGBA" else "RGB")
    png = os.path.join(IMG, name + ".png"); webp = os.path.join(IMG, name + ".webp")
    im.save(png, optimize=True); im.save(webp, quality=webp_q, method=6)
    print(name, im.size, os.path.getsize(png)//1024, "KB png", os.path.getsize(webp)//1024, "KB webp")

def shot(src, name, width, crop=None):
    im = Image.open(os.path.join(ROOT, src)).convert("RGBA")
    if crop: im = im.crop(crop)
    h = round(im.height * width / im.width)
    save(im.resize((width, h), Image.LANCZOS), name)

# Product screenshots (real app captures; the sample church is the demo data)
shot("apple/screenshots/iphone-3-remote.png", "iphone-remote", 520, crop=(0, 0, 1206, 2400))
shot("apple/screenshots/iphone-2-screens.png", "iphone-screens", 520, crop=(0, 0, 1206, 2400))
shot("apple/screenshots/ipad-2-split.png", "ipad-remote", 900, crop=(0, 0, 2064, 2200))
shot("apple/screenshots/mac-screens.png", "mac-screens", 1240)
shot("apple/screenshots/mac-calendar.png", "mac-calendar", 1240)
shot("apple/screenshots/mac-songs.png", "mac-songs", 1240)
shot("store/screenshots/03-pairing.png", "tv-pairing", 960)
shot("store/screenshots/07-kids-demo-lyrics.png", "tv-lyrics", 960)
shot("store/screenshots/09-signage-demo-1.png", "tv-signage", 960)
shot("store/screenshots/06-kids-demo-countdown.png", "tv-countdown", 960)

# Logo / icons
icon = Image.open(os.path.join(ROOT, "brand/app-logo/icon-512.png")).convert("RGBA")
for px, n in [(32, "favicon-32.png"), (180, "apple-touch-icon.png"), (192, "icon-192.png"), (512, "icon-512.png")]:
    icon.resize((px, px), Image.LANCZOS).save(os.path.join(WEB, n), optimize=True)
    print(n)
icon.resize((96, 96), Image.LANCZOS).save(os.path.join(IMG, "logo-mark.png"), optimize=True)
icon.resize((96, 96), Image.LANCZOS).save(os.path.join(IMG, "logo-mark.webp"), quality=90)
# favicon.ico (multi-size)
icon.resize((48, 48), Image.LANCZOS).save(os.path.join(WEB, "favicon.ico"), sizes=[(16, 16), (32, 32), (48, 48)])

# OG image 1200x630: navy background, brand tiles, headline, a framed TV screenshot
INK, NAVY, AMBER, WHITE = (20, 24, 36), (27, 42, 74), (242, 163, 58), (255, 255, 255)
LATO_BLACK = os.path.join(ROOT, "tv-app/app/src/main/res/font/lato_black.ttf")
LATO_BOLD = os.path.join(ROOT, "tv-app/app/src/main/res/font/lato_bold.ttf")
W, H = 1200, 630
og = Image.new("RGB", (W, H), INK)
d = ImageDraw.Draw(og)
for i in range(H):  # subtle vertical gradient to navy
    t = i / H
    d.line([(0, i), (W, i)], fill=tuple(round(INK[k] + (NAVY[k] - INK[k]) * t) for k in range(3)))
og = og.convert("RGBA")
og.alpha_composite(icon.resize((120, 120), Image.LANCZOS), (70, 66))
d = ImageDraw.Draw(og)
d.text((212, 80), "CHURCH TV OS", font=ImageFont.truetype(LATO_BLACK, 40), fill=WHITE)
d.text((212, 126), "churchtvos.com", font=ImageFont.truetype(LATO_BOLD, 26), fill=AMBER)
head = ImageFont.truetype(LATO_BLACK, 66)
y = 250
for line in ["The screens at", "your church,", "run from your phone."]:
    d.text((70, y), line, font=head, fill=WHITE); y += 82
tv = Image.open(os.path.join(ROOT, "store/screenshots/03-pairing.png")).convert("RGB").resize((500, 281), Image.LANCZOS)
frame = Image.new("RGBA", (tv.width + 24, tv.height + 24), (8, 10, 16, 255))
mask = Image.new("L", frame.size, 0); ImageDraw.Draw(mask).rounded_rectangle((0, 0, *frame.size), 18, fill=255)
frame.paste(tv, (12, 12))
sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
sh.paste((0, 0, 0, 150), (630, 120, 630 + frame.width, 120 + frame.height))
og.alpha_composite(sh.filter(ImageFilter.GaussianBlur(22)))
og.paste(frame, (630, 112), mask)
phone = Image.open(os.path.join(IMG, "iphone-remote.png")).convert("RGBA")
ph = phone.resize((230, round(phone.height * 230 / phone.width)), Image.LANCZOS)
pm = Image.new("L", ph.size, 0); ImageDraw.Draw(pm).rounded_rectangle((0, 0, *ph.size), 30, fill=255)
pf = Image.new("RGBA", (ph.width + 14, ph.height + 14), (8, 10, 16, 255))
pfm = Image.new("L", pf.size, 0); ImageDraw.Draw(pfm).rounded_rectangle((0, 0, *pf.size), 36, fill=255)
pf.paste(ph, (7, 7), pm)
pf = pf.crop((0, 0, pf.width, 330 + 14))
og.paste(pf, (920, 330), pfm.crop((0, 0, pf.width, pf.height)))
og.convert("RGB").save(os.path.join(WEB, "og-image.jpg"), quality=86, optimize=True)
print("og-image", os.path.getsize(os.path.join(WEB, "og-image.jpg"))//1024, "KB jpg")

# Fonts: subset Lato (Latin) to woff2
try:
    from fontTools import subset
    from fontTools.ttLib import TTFont
    uni = "U+0020-007E,U+00A0-00FF,U+2013,U+2014,U+2018,U+2019,U+201C,U+201D,U+2022,U+2026,U+2192,U+00B7"
    for src, out in [("lato_regular", "lato-400"), ("lato_bold", "lato-700"), ("lato_black", "lato-900")]:
        opts = subset.Options(); opts.flavor = "woff2"; opts.layout_features = ["kern", "liga"]
        f = TTFont(os.path.join(ROOT, f"tv-app/app/src/main/res/font/{src}.ttf"))
        s = subset.Subsetter(opts); s.populate(unicodes=subset.parse_unicodes(uni)); s.subset(f)
        p = os.path.join(FONTS, out + ".woff2"); f.flavor = "woff2"; f.save(p); print(out, os.path.getsize(p)//1024, "KB")
except ImportError:
    print("fonttools/brotli missing: fonts not rebuilt", file=sys.stderr)
