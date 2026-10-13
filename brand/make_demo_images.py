"""Bundled demo-mode slides for app-store reviewers (no network needed). Run: python3 make_demo_images.py"""
import os
from PIL import Image, ImageDraw, ImageFont
HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "..", "tv-app", "app", "src", "main", "res")
LATO = os.path.join(RES, "font", "lato_black.ttf"); LATO_R = os.path.join(RES, "font", "lato_regular.ttf")
SLIDES = {
    "demo_welcome": ((27, 42, 74), "Welcome", "Church TV OS demo"),
    "demo_events": ((20, 150, 140), "This Sunday", "Services at 9:00 and 11:00"),
    "demo_info": ((232, 93, 76), "Kids Check-in", "Opens 15 minutes before each service"),
}
for name, (bg, title, sub) in SLIDES.items():
    im = Image.new("RGB", (1280, 720), bg); d = ImageDraw.Draw(im)
    for text, font, y in ((title, ImageFont.truetype(LATO, 120), 250), (sub, ImageFont.truetype(LATO_R, 48), 420)):
        w = d.textlength(text, font=font); d.text(((1280 - w) / 2, y), text, font=font, fill=(255, 255, 255))
    im.save(os.path.join(RES, "drawable-nodpi", name + ".png"), optimize=True)
print("ok")
