"""Round 2: combos of play screen, window arch and multiple screens. Run: python3 make_concepts2.py"""
import os
from PIL import Image, ImageDraw, ImageFont
from make_concepts import *  # tile, rr, colours, W, N, FONT, HERE


def arch(d, x0, y0, x1, y1, fill):
    """Church-window pane: semicircle top, flat bottom."""
    r = (x1 - x0) / 2
    d.pieslice((x0 * W, y0 * W, x1 * W, (y0 + 2 * r) * W), 180, 360, fill=fill)
    d.rectangle((x0 * W, (y0 + r) * W, x1 * W, y1 * W), fill=fill)


def tri(d, cx, cy, h, fill):
    w = h * .85
    d.polygon([((cx - w * .38) * W, (cy - h / 2) * W), ((cx - w * .38) * W, (cy + h / 2) * W), ((cx + w * .62) * W, cy * W)], fill=fill)


def a():  # 2x2, top-left is the arched play pane
    im = tile(INK); d = ImageDraw.Draw(im)
    arch(d, .17, .17, .48, .48, AMBER); tri(d, .33, .36, .13, INK)
    rr(d, (.52, .17, .83, .48), .05, fill=SKY)
    rr(d, (.17, .52, .48, .83), .05, fill=CORAL)
    rr(d, (.52, .52, .83, .83), .05, fill=TEAL)
    return im


def b():  # amber tile, navy panes, arched one carries the play
    im = tile(AMBER); d = ImageDraw.Draw(im)
    arch(d, .16, .16, .48, .48, NAVY); tri(d, .32, .35, .13, AMBER)
    rr(d, (.52, .16, .84, .48), .05, fill=NAVY)
    rr(d, (.16, .52, .48, .84), .05, fill=NAVY)
    rr(d, (.52, .52, .84, .84), .05, fill=NAVY)
    return im


def c():  # three lancet windows, middle tallest with play
    im = tile(NAVY); d = ImageDraw.Draw(im)
    arch(d, .13, .34, .35, .80, SKY)
    arch(d, .65, .34, .87, .80, CORAL)
    arch(d, .385, .20, .615, .80, AMBER); tri(d, .5, .50, .12, NAVY)
    return im


def d_():  # cascading screens, front one has play
    im = tile(CREAM); d = ImageDraw.Draw(im)
    rr(d, (.13, .13, .60, .50), .06, fill=SKY)
    rr(d, (.25, .25, .72, .62), .06, fill=TEAL)
    rr(d, (.38, .38, .86, .78), .07, fill=NAVY)
    tri(d, .62, .58, .15, AMBER)
    return im


def e():  # 2x2 where all four are arched, one with play
    im = tile(NAVY); d = ImageDraw.Draw(im)
    for (x, y), col in zip(((.17, .17), (.52, .17), (.17, .52), (.52, .52)), (AMBER, SKY, CORAL, TEAL)):
        arch(d, x, y, x + .31, y + .31, col)
    tri(d, .325, .36, .11, NAVY)
    return im


def f():  # play triangle built from four screens (2x2 grid with centered play cut)
    im = tile(WHITE); d = ImageDraw.Draw(im)
    for (x, y), col in zip(((.14, .14), (.52, .14), (.14, .52), (.52, .52)), (AMBER, SKY, CORAL, TEAL)):
        rr(d, (x, y, x + .34, y + .34), .06, fill=col)
    d.ellipse((.34 * W, .34 * W, .66 * W, .66 * W), fill=NAVY)
    tri(d, .5, .5, .17, WHITE)
    return im


SET = [("A · Arched play + 3 screens", a), ("B · Amber, arched play", b), ("C · Three windows", c),
       ("D · Cascading screens", d_), ("E · Four windows", e), ("F · Grid + play badge", f)]

if __name__ == "__main__":
    cell, pad, label = 300, 40, 44
    sheet = Image.new("RGB", (3 * cell + 4 * pad, 2 * (cell + label) + 3 * pad), (240, 241, 244))
    dr = ImageDraw.Draw(sheet); ft = ImageFont.truetype(FONT, 22)
    os.makedirs(os.path.join(HERE, "concepts"), exist_ok=True)
    for i, (name, fn) in enumerate(SET):
        im = fn().resize((N, N), Image.LANCZOS)
        im.save(os.path.join(HERE, "concepts", f"round2-{'abcdef'[i]}.png"))
        sm = im.resize((cell, cell), Image.LANCZOS)
        x, y = pad + (i % 3) * (cell + pad), pad + (i // 3) * (cell + label + pad)
        sheet.paste(sm, (x, y), sm); dr.text((x, y + cell + 10), name, font=ft, fill=(40, 44, 58))
    sheet.save(os.path.join(HERE, "concepts", "icon-concepts-round2.png")); print("ok")
