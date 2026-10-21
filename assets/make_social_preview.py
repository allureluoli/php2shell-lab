#!/usr/bin/env python3
"""Render the 1280x640 social preview from the same text the README shows."""
from PIL import Image, ImageDraw, ImageFont

W, H = 1280, 640
BG = (13, 17, 23)
PANEL = (22, 27, 34)
FG = (201, 209, 217)
DIM = (139, 148, 158)
RED = (248, 81, 73)
GREEN = (63, 185, 80)
BLUE = (88, 166, 255)

font_paths = [
    r"C:\Windows\Fonts\CascadiaMono.ttf",
    r"C:\Windows\Fonts\consola.ttf",
    r"C:\Windows\Fonts\lucon.ttf",
]


def load(size):
    for p in font_paths:
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            continue
    return ImageFont.load_default()


big = load(46)
mid = load(24)
mono = load(20)
small = load(17)

img = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img)

# top accent
d.rectangle([0, 0, W, 6], fill=BLUE)

d.text((64, 56), "php2shell-lab", font=big, fill=FG)
d.text((64, 118), "CVE-2026-109618 / CVE-2026-109619 — differential reproduction",
       font=mid, fill=DIM)

# terminal panel
px, py, pw, ph = 64, 178, W - 128, 372
d.rounded_rectangle([px, py, px + pw, py + ph], radius=14, fill=PANEL, outline=(48, 54, 61))

lines = [
    ("$ ", DIM, "PHP_VULN=/usr/bin/php PHP_FIXED=/opt/php-8.4.27/bin/php lab/quickstart.sh", FG),
    ("", FG, "", FG),
    ("── vulnerable: PHP 8.4.16 (cli) ──", BLUE, "", FG),
    ("   R1 arm  : HTTP/1.0 500 Internal Server Error", DIM, "", FG),
    ("   R2 probe: <no response / process aborted>", DIM, "", FG),
    ("   server: DEAD (exit 139, SIGSEGV)", RED, "", RED),
    ("", FG, "", FG),
    ("── fixed: PHP 8.4.27 (cli) ──", BLUE, "", FG),
    ("   R1 arm  : HTTP/1.1 200 OK", DIM, "", FG),
    ("   R2 probe: HTTP/1.1 200 OK", DIM, "", FG),
    ("   server: ALIVE", GREEN, "", GREEN),
    ("", FG, "", FG),
    ("RESULT: reproduced (vulnerable dies, fixed survives)", GREEN, "", GREEN),
]

y = py + 26
for lead, lead_color, text, text_color in lines:
    if lead:
        d.text((px + 28, y), lead, font=mono, fill=lead_color)
    if text:
        w = d.textlength(lead, font=mono) if lead else 0
        d.text((px + 28 + w, y), text, font=mono, fill=text_color)
    y += 26

d.text((64, H - 56), "same two requests · same body · same limits — only the PHP source differs",
       font=small, fill=DIM)
d.text((W - 360, H - 56), "MIT · no docker required", font=small, fill=DIM)

img.save("assets/social-preview.png", "PNG")
print("assets/social-preview.png", img.size)
