#!/usr/bin/env python3
"""Generates the Church TV OS launch graphics (PNG) with Pillow.

Run:  python3 make_graphics.py     (from this folder; needs Pillow)
Output goes to ./out/.  Fonts: Lato (SIL OFL) in ./fonts.
Screens shown are the real built-in demo screens from store/screenshots/.
No store logos are used: platform names are plain text chips. Add each
store's official badge from its brand kit if you want logos.
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)

INK = (20, 24, 36)
NAVY = (27, 42, 74)
AMBER = (242, 163, 58)
SKY = (86, 156, 230)
CORAL = (232, 93, 76)
TEAL = (20, 150, 140)
WHITE = (255, 255, 255)
SOFT = (195, 202, 219)
CREAM = (255, 253, 249)

F = {w: os.path.join(HERE, "fonts", f"Lato-{w}.ttf") for w in ("Regular", "Bold", "Black")}


def font(weight, size):
    return ImageFont.truetype(F[weight], size)


SHOTS = {
    "countdown": os.path.join(ROOT, "store/screenshots/06-kids-demo-countdown.png"),
    "lyrics": os.path.join(ROOT, "store/screenshots/07-kids-demo-lyrics.png"),
    "welcome": os.path.join(ROOT, "store/screenshots/09-signage-demo-1.png"),
    "sunday": os.path.join(ROOT, "store/screenshots/10-signage-demo-2.png"),
    "checkin": os.path.join(ROOT, "store/screenshots/11-signage-demo-3.png"),
    "pairing": os.path.join(ROOT, "store/screenshots/03-pairing.png"),
}
LOGO = Image.open(os.path.join(ROOT, "brand/app-logo/icon-512.png")).convert("RGBA")


def bg(w, h, top=INK, bottom=NAVY):
    im = Image.new("RGB", (w, h), top)
    px = ImageDraw.Draw(im)
    for y in range(h):
        t = y / max(h - 1, 1)
        px.line([(0, y), (w, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return im


def logo(im, x, y, size):
    l = LOGO.resize((size, size), Image.LANCZOS)
    im.paste(l, (x, y), l)


def wordmark(im, x, y, size=44, color=WHITE):
    logo(im, x, y, int(size * 1.5))
    d = ImageDraw.Draw(im)
    d.text((x + int(size * 1.5) + 16, y + int(size * 0.75)), "CHURCH TV OS", font=font("Black", size), fill=color, anchor="lm")


def wrap(d, text, fnt, max_w):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if d.textlength(t, font=fnt) <= max_w:
            cur = t
        else:
            lines.append(cur)
            cur = w
    lines.append(cur)
    return lines


def para(im, x, y, text, weight, size, fill, max_w, lh=1.18, anchor="la", align_center=False):
    d = ImageDraw.Draw(im)
    fnt = font(weight, size)
    ys = y
    for ln in wrap(d, text, fnt, max_w):
        if align_center:
            d.text((x + max_w / 2, ys), ln, font=fnt, fill=fill, anchor="ma")
        else:
            d.text((x, ys), ln, font=fnt, fill=fill)
        ys += int(size * lh)
    return ys


def rrect(im, box, r, fill, outline=None, width=0):
    ImageDraw.Draw(im).rounded_rectangle(box, r, fill=fill, outline=outline, width=width)


def chip(im, x, y, text, fill, text_color=INK, size=30, pad=(26, 14), outline=None, dot=None):
    d = ImageDraw.Draw(im)
    fnt = font("Black", size)
    tw = d.textlength(text, font=fnt)
    dotw = (size * 0.9) if dot else 0
    w = int(tw + pad[0] * 2 + dotw)
    h = int(size + pad[1] * 2)
    d.rounded_rectangle((x, y, x + w, y + h), h // 2, fill=fill, outline=outline, width=3 if outline else 0)
    tx = x + pad[0]
    if dot:
        r = size * 0.28
        d.ellipse((tx, y + h / 2 - r, tx + 2 * r, y + h / 2 + r), fill=dot)
        tx += dotw
    d.text((tx, y + h / 2), text, font=fnt, fill=text_color, anchor="lm")
    return x + w, h


def tv(im, key, x, y, w, shadow=True):
    """Put a real demo screen in a simple TV frame. (x, y) is top-left; width w."""
    shot = Image.open(SHOTS[key]).convert("RGB")
    bez = max(8, w // 70)
    sw = w - 2 * bez
    sh = int(sw * 9 / 16)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    h = sh + 2 * bez
    if shadow:
        sh_im = Image.new("RGBA", (w + 80, h + 80), (0, 0, 0, 0))
        ImageDraw.Draw(sh_im).rounded_rectangle((40, 50, 40 + w, 50 + h), 18, fill=(0, 0, 0, 150))
        sh_im = sh_im.filter(ImageFilter.GaussianBlur(18))
        im.paste(sh_im, (x - 40, y - 40), sh_im)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((x, y, x + w, y + h), 14, fill=(11, 14, 22))
    im.paste(shot, (x + bez, y + bez))
    # stand
    d.rounded_rectangle((x + w * 0.38, y + h, x + w * 0.62, y + h + max(8, w // 60)), 6, fill=(26, 31, 44))
    return h


def tiles(im, x, y, size, gap=None):
    """The brand's four-tile mark, as a decorative row."""
    gap = gap or size // 6
    for i, c in enumerate((AMBER, SKY, CORAL, TEAL)):
        rrect(im, (x + i * (size + gap), y, x + i * (size + gap) + size, y + size), size // 5, c)


def platform_row(im, x, y, size=28, soon=True, max_x=None):
    """Live chips and a coming-soon chip (wraps to a second line if it would pass max_x). Returns bottom y."""
    max_x = max_x or (im.width - 70)
    cx = x
    for name in ("Fire TV", "Google TV", "Roku"):
        cx, h = chip(im, cx, y, name, WHITE, INK, size, dot=TEAL)
        cx += 14
    bottom = y + size + 28
    if soon:
        d = ImageDraw.Draw(im)
        wsoon = d.textlength("LG and Samsung: coming soon", font=font("Black", size - 4)) + 52
        if cx + wsoon > max_x:
            cx, y = x, y + size + 40
            bottom = y + size + 28
        chip(im, cx, y, "LG and Samsung: coming soon", None, SOFT, size - 4, outline=(110, 122, 150))
    return bottom


def save(im, name):
    p = os.path.join(OUT, name)
    im.convert("RGB").save(p, optimize=True)
    print("wrote", name, im.size)


# ---------------------------------------------------------------- social cards
def social_launch_square():
    W = H = 1080
    im = bg(W, H)
    wordmark(im, 80, 70, 36)
    y = para(im, 80, 180, "Every screen at your church, run from your phone.", "Black", 76, WHITE, 900, 1.08)
    y = para(im, 80, y + 20, "Kids rooms, lobby signs and Sunday slides on the TVs you already own.", "Regular", 34, SOFT, 860)
    y = platform_row(im, 80, y + 24, 28, max_x=1010)
    tv(im, "sunday", 80, y + 30, 520)
    tiles(im, 680, y + 80, 70, 18)
    d = ImageDraw.Draw(im)
    d.text((680, y + 190), "Free trial", font=font("Black", 40), fill=AMBER)
    d.text((680, y + 240), "churchtvos.com", font=font("Bold", 34), fill=WHITE)
    save(im, "social-launch-1080x1080.png")


def social_launch_portrait():
    W, H = 1080, 1350
    im = bg(W, H)
    wordmark(im, 80, 80, 38)
    para(im, 80, 240, "It's live on Fire TV, Google TV and Roku.", "Black", 92, WHITE, 920, 1.06)
    para(im, 80, 560, "Run your kids rooms, lobby signs and Sunday slides from your phone. LG and Samsung are on the way.", "Regular", 38, SOFT, 900)
    platform_row(im, 80, 740, 30, max_x=1010)
    tv(im, "countdown", 80, 960, 540)
    tiles(im, 680, 1000, 64, 14)
    ImageDraw.Draw(im).text((680, 1120), "Free trial", font=font("Black", 44), fill=AMBER)
    ImageDraw.Draw(im).text((680, 1180), "churchtvos.com", font=font("Bold", 36), fill=WHITE)
    save(im, "social-launch-1080x1350.png")


def social_usetv():
    W = H = 1080
    im = bg(W, H, NAVY, INK)
    wordmark(im, 80, 70, 34)
    para(im, 80, 200, "The TVs you already own, working all week.", "Black", 88, WHITE, 900, 1.07)
    labels = [("Kids", CORAL, "Sunday rooms"), ("Signage", SKY, "Lobby, all week"), ("Slides", TEAL, "Songs and sermon")]
    x = 80
    for name, col, sub in labels:
        rrect(im, (x, 560, x + 290, 820), 30, col)
        d = ImageDraw.Draw(im)
        d.text((x + 28, 620), name, font=font("Black", 56), fill=WHITE)
        d.text((x + 28, 700), sub, font=font("Bold", 30), fill=WHITE)
        x += 315
    para(im, 80, 880, "Fire TV, Google TV and Roku. Pair with a six-character code. churchtvos.com", "Bold", 34, SOFT, 900)
    save(im, "social-usetv-1080x1080.png")


def social_thursday():
    W, H = 1080, 1350
    im = bg(W, H, INK, (22, 34, 62))
    wordmark(im, 80, 80, 36)
    para(im, 80, 220, "Set it Thursday.", "Black", 116, WHITE, 920, 1.0)
    para(im, 80, 345, "Forget it Sunday.", "Black", 116, AMBER, 920, 1.0)
    para(im, 80, 520, "Schedule each room ahead of time. The TV downloads it and keeps playing if the Wi-Fi drops.", "Regular", 38, SOFT, 900)
    tv(im, "countdown", 120, 740, 840)
    ImageDraw.Draw(im).text((120, 1270), "churchtvos.com", font=font("Black", 40), fill=AMBER)
    save(im, "social-thursday-1080x1350.png")


def og():
    W, H = 1200, 630
    im = bg(W, H)
    wordmark(im, 64, 56, 30)
    para(im, 64, 170, "Every screen at your church, run from your phone.", "Black", 68, WHITE, 640, 1.08)
    platform_row(im, 64, 480, 24)
    tv(im, "sunday", 740, 190, 410)
    tiles(im, 740, 80, 52, 14)
    save(im, "og-1200x630.png")


def banner():
    # 1500x500. X puts the avatar at lower left, LinkedIn/Facebook crop edges: keep text in the centre-right.
    W, H = 1500, 500
    im = bg(W, H)
    tiles(im, 560, 70, 56, 14)
    para(im, 560, 150, "Kids rooms, lobby signs and Sunday slides. One system, run from your phone.", "Black", 44, WHITE, 600, 1.12)
    platform_row(im, 560, 340, 22, max_x=1180)
    ImageDraw.Draw(im).text((560, 450), "churchtvos.com", font=font("Bold", 28), fill=AMBER)
    tv(im, "lyrics", 1210, 150, 240, shadow=False)
    save(im, "banner-1500x500.png")


def launch_card():
    W, H = 1920, 1080
    im = bg(W, H, INK, NAVY)
    wordmark(im, 110, 90, 44)
    y = para(im, 110, 250, "Church TV OS is live.", "Black", 120, WHITE, 860, 1.02)
    y = para(im, 110, y + 30, "Run the kids rooms, the lobby and the sanctuary screens from your phone.", "Regular", 46, SOFT, 820)
    platform_row(im, 110, y + 40, 36, max_x=900)
    ImageDraw.Draw(im).text((110, 930), "Start a free trial at churchtvos.com", font=font("Black", 50), fill=AMBER)
    tv(im, "welcome", 1020, 330, 780)
    tiles(im, 1020, 150, 80, 22)
    save(im, "launch-announcement-1920x1080.png")


def launch_card_square():
    W = H = 1080
    im = bg(W, H, INK, NAVY)
    wordmark(im, 80, 70, 34)
    y = para(im, 80, 200, "Church TV OS is live.", "Black", 112, WHITE, 900, 1.02)
    y = para(im, 80, y + 24, "Your kids rooms, lobby and sanctuary screens, run from your phone.", "Regular", 40, SOFT, 880)
    platform_row(im, 80, y + 30, 30, max_x=1010)
    tv(im, "welcome", 80, 790, 500)
    ImageDraw.Draw(im).text((640, 880), "Free trial", font=font("Black", 44), fill=AMBER)
    ImageDraw.Draw(im).text((640, 940), "churchtvos.com", font=font("Bold", 36), fill=WHITE)
    save(im, "launch-announcement-1080x1080.png")


def badge_strip(light=False):
    W, H = 1600, 300
    base = CREAM if light else INK
    im = Image.new("RGB", (W, H), base)
    d = ImageDraw.Draw(im)
    txt = INK if light else WHITE
    mut = (91, 100, 117) if light else SOFT
    d.text((60, 52), "LIVE NOW", font=font("Black", 26), fill=TEAL)
    d.text((960, 52), "COMING SOON", font=font("Black", 26), fill=(184, 118, 20) if light else AMBER)
    x = 60
    for n in ("Fire TV", "Google TV", "Roku"):
        fill = WHITE if not light else (255, 255, 255)
        rrect(im, (x, 100, x + 280, 230), 28, fill, outline=None if not light else (214, 208, 190), width=3)
        d.ellipse((x + 24, 153, x + 48, 177), fill=TEAL)
        d.text((x + 64, 165), n, font=font("Black", 40), fill=INK, anchor="lm")
        x += 300
    x = 960
    for n in ("LG", "Samsung"):
        w = 270
        rrect(im, (x, 100, x + w, 230), 28, None, outline=(120, 132, 160) if not light else (150, 150, 140), width=4)
        d.text((x + w / 2, 165), n, font=font("Black", 40), fill=txt, anchor="mm")
        x += w + 20
    save(im, "badge-strip-live-and-soon-1600x300.png" if not light else "badge-strip-live-and-soon-light-1600x300.png")


def feature_card(name, color, tagline, bullets, shot, fname, textcolor=WHITE):
    W = H = 1080
    im = bg(W, H, INK, NAVY)
    rrect(im, (0, 0, W, 330), 0, color)
    ImageDraw.Draw(im).rectangle((0, 0, W, 330), fill=color)
    d = ImageDraw.Draw(im)
    d.text((80, 60), "CHURCH TV OS", font=font("Black", 28), fill=textcolor)
    d.text((80, 105), name, font=font("Black", 120), fill=textcolor)
    para(im, 80, 245, tagline, "Bold", 38, textcolor, 920)
    y = 390
    for b in bullets:
        d.ellipse((80, y + 12, 104, y + 36), fill=color)
        y = para(im, 130, y, b, "Bold", 36, WHITE, 860, 1.2) + 18
    tv(im, shot, 80, 690, 600)
    d.text((730, 820), "Free trial", font=font("Black", 40), fill=AMBER)
    d.text((730, 875), "churchtvos.com", font=font("Bold", 34), fill=WHITE)
    save(im, fname)


def features():
    feature_card("Kids", CORAL, "Curriculum that plays itself into the room.",
                 ["Playlists, countdowns, lyrics and YouTube", "Scheduled per room, weekly rotation", "Keeps playing if the internet drops"],
                 "countdown", "feature-kids-1080x1080.png", textcolor=INK)
    feature_card("Signage", SKY, "Lobby screens that look after themselves.",
                 ["Pictures, video and text signs", "Weekly slots and screen groups", "Landscape or portrait"],
                 "checkin", "feature-signage-1080x1080.png", textcolor=INK)
    feature_card("Slides", TEAL, "Decks for your services, without a laptop.",
                 ["Songs, lyrics, pictures and video", "Import a PDF or PowerPoint", "Step through from your phone"],
                 "lyrics", "feature-slides-1080x1080.png")


if __name__ == "__main__":
    social_launch_square(); social_launch_portrait(); social_usetv(); social_thursday()
    og(); banner(); launch_card(); launch_card_square()
    badge_strip(False); badge_strip(True); features()
