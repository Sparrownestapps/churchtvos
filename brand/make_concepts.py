"""Icon concept sheet for Church TV OS. Run: python3 make_concepts.py"""
import math, os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, "..", "tv-app", "app", "src", "main", "res", "font", "lato_black.ttf")
S, N = 4, 512
W = N * S
NAVY, AMBER, WHITE, TEAL, CORAL, SKY, INK, CREAM = (27,42,74), (242,163,58), (255,255,255), (20,150,140), (232,93,76), (86,156,230), (20,24,36), (250,244,232)


def tile(bg, radius=0.22):
    im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(im).rounded_rectangle((0, 0, W - 1, W - 1), radius=round(W * radius), fill=bg)
    return im


def rr(d, box, r, **kw):
    d.rounded_rectangle([round(v * W) for v in box], radius=round(r * W), **kw)


def c1():  # TV + cross
    im = tile(NAVY); d = ImageDraw.Draw(im)
    rr(d, (.17, .22, .83, .66), .06, outline=WHITE, width=round(W * .035))
    rr(d, (.45, .66, .55, .73), .01, fill=WHITE); rr(d, (.33, .72, .67, .77), .02, fill=WHITE)
    rr(d, (.47, .30, .53, .58), .015, fill=AMBER); rr(d, (.40, .37, .60, .43), .015, fill=AMBER)
    return im


def c2():  # amber tile, play triangle inside a screen
    im = tile(AMBER); d = ImageDraw.Draw(im)
    rr(d, (.14, .22, .86, .72), .09, fill=NAVY)
    d.polygon([(.43 * W, .34 * W), (.43 * W, .60 * W), (.65 * W, .47 * W)], fill=WHITE)
    rr(d, (.30, .78, .70, .83), .025, fill=NAVY)
    return im


def c3():  # broadcast rings
    im = tile(TEAL); d = ImageDraw.Draw(im)
    cx, cy = .5 * W, .62 * W
    for r, w in ((.40, .045), (.28, .045), (.16, .045)):
        d.arc((cx - r * W, cy - r * W, cx + r * W, cy + r * W), 215, 325, fill=WHITE, width=round(w * W))
    d.ellipse((cx - .06 * W, cy - .06 * W, cx + .06 * W, cy + .06 * W), fill=WHITE)
    return im


def c4():  # four panes = screens/modules
    im = tile(INK); d = ImageDraw.Draw(im)
    cols = [AMBER, SKY, CORAL, TEAL]
    for i, (x, y) in enumerate(((.18, .18), (.52, .18), (.18, .52), (.52, .52))):
        rr(d, (x, y, x + .30, y + .30), .05, fill=cols[i])
    return im


def c5():  # church window arch with play
    im = tile(CREAM); d = ImageDraw.Draw(im)
    x0, x1, top, bot = .27, .73, .16, .84
    d.pieslice((x0 * W, top * W, x1 * W, (top + (x1 - x0)) * W), 180, 360, fill=NAVY)
    d.rectangle((x0 * W, (top + (x1 - x0) / 2) * W, x1 * W, bot * W), fill=NAVY)
    d.polygon([(.43 * W, .43 * W), (.43 * W, .67 * W), (.64 * W, .55 * W)], fill=AMBER)
    return im


def c6():  # monogram C that is a screen
    im = tile(NAVY); d = ImageDraw.Draw(im)
    d.arc((.16 * W, .16 * W, .84 * W, .84 * W), 40, 320, fill=WHITE, width=round(W * .11))
    d.ellipse((.44 * W, .44 * W, .56 * W, .56 * W), fill=AMBER)
    d.polygon([(.48 * W, .45 * W), (.48 * W, .55 * W), (.57 * W, .50 * W)], fill=NAVY)
    return im


CONCEPTS = [("1 · TV + cross (current)", c1), ("2 · Play screen", c2), ("3 · Broadcast", c3),
            ("4 · Four screens", c4), ("5 · Window + play", c5), ("6 · Monogram C", c6)]

if __name__ == "__main__":
    cell, pad, label = 300, 40, 44
    sheet = Image.new("RGB", (3 * cell + 4 * pad, 2 * (cell + label) + 3 * pad), (240, 241, 244))
    d = ImageDraw.Draw(sheet); f = ImageFont.truetype(FONT, 22)
    for i, (name, fn) in enumerate(CONCEPTS):
        im = fn().resize((N, N), Image.LANCZOS)
        im.save(os.path.join(HERE, "concepts", f"icon-{i + 1}.png"))
        x, y = pad + (i % 3) * (cell + pad), pad + (i // 3) * (cell + label + pad)
        sheet.paste(im.resize((cell, cell), Image.LANCZOS), (x, y), im.resize((cell, cell), Image.LANCZOS))
        d.text((x, y + cell + 10), name, font=f, fill=(40, 44, 58))
    sheet.save(os.path.join(HERE, "concepts", "icon-concepts.png"))
    print("ok")
