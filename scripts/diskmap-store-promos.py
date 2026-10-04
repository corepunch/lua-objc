"""Compose five 2880 × 1800 Mac App Store JPEGs from native showcase captures.

Run with the bundled Python runtime (Pillow and NumPy), after the capture plan
in make diskmap-store-screenshots. UI pixels and the existing app icon are
preserved; only the surrounding marketing artboard is authored here.
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "build/diskmap-store"
OUTPUT = ROOT / "apps/diskmap/store-assets/en/screenshots"
SIZE = (2880, 1800)
FONT = "/System/Library/Fonts/SFNS.ttf"
SHOTS = (
    ("map", "STORAGE MAP", "See what fills your Mac.",
     "Explore your storage in rings or rectangles. Follow the space.",
     "#121321", "#39325d", "#183a4a", "#f7f5ff", "#c4bfd9"),
    ("cleanup", "GUIDED CLEANUP", "Make space. Stay in control.",
     "Understand what can be rebuilt. Review before moving to Trash.",
     "#ecf2ef", "#d2e5dd", "#d9e7f3", "#19352c", "#516d62"),
    ("files", "LARGE FILES", "Find the files worth a look.",
     "Sort by size. Filter by kind. See when each file was last used.",
     "#0b2027", "#124e59", "#233c58", "#eefbfa", "#afd0d6"),
    ("kinds", "FILE TYPES", "Your storage, by kind.",
     "Videos, installers, archives and more. See where it all adds up.",
     "#f0edf7", "#e0d6f0", "#dce9ee", "#302744", "#736484"),
    ("developer", "DEVELOPER TOOLS", "Less clutter. More building.",
     "Understand Xcode, simulators, package caches and project data.",
     "#14182e", "#433255", "#233f68", "#f7f6ff", "#bdbfda"),
)


def font(size, weight=400):
    face = ImageFont.truetype(FONT, size)
    face.set_variation_by_axes([100, min(size, 96), 400, weight])
    return face


def rgb(color):
    return np.array(tuple(bytes.fromhex(color[1:])), dtype=np.float32)


def background(base, glow_a, glow_b):
    # Soft, continuous gradients survive JPEG export without obvious banding.
    width, height = SIZE
    y, x = np.mgrid[0:height, 0:width].astype(np.float32)
    pixels = np.broadcast_to(rgb(base), (height, width, 3)).copy()
    for color, cx, cy, spread in ((glow_a, 2550, 350, 1350), (glow_b, 500, 1600, 1150)):
        alpha = (0.7 * np.exp(-((x - cx) ** 2 + (y - cy) ** 2) / spread ** 2))[..., None]
        pixels = pixels * (1 - alpha) + rgb(color) * alpha
    return Image.fromarray(np.uint8(np.clip(pixels, 0, 255))).convert("RGBA")


def render(index, shot):
    page, label, headline, subtitle, base, glow_a, glow_b, ink, muted = shot
    source = Image.open(SOURCE / f"{page}.png").convert("RGBA")
    assert source.size == (2560, 1280), f"Unexpected native capture size: {source.size}"
    canvas = background(base, glow_a, glow_b)
    draw = ImageDraw.Draw(canvas)
    icon = Image.open(ROOT / "apps/diskmap/Assets.xcassets/AppIcon.appiconset/icon_1024.png").convert("RGBA")
    canvas.alpha_composite(icon.resize((88, 88), Image.Resampling.LANCZOS), (152, 56))
    draw.text((254, 71), "Diskmap", font=font(54, 650), fill=ink)
    draw.text((2718, 90), f"{label}   /   {index:02d}", font=font(29, 550), fill=muted, anchor="ra")
    assert draw.textlength(headline, font=font(152, 650)) < 2550, "Headline must fit without truncation"
    assert draw.textlength(subtitle, font=font(49)) < 2550, "Subtitle must fit without truncation"
    draw.text((160, 181), headline, font=font(152, 650), fill=ink, stroke_width=0)
    draw.text((166, 372), subtitle, font=font(49), fill=muted)

    # Keep the whole window, its native corners, and all UI at one scale.
    window = source.resize((2520, 1260), Image.Resampling.LANCZOS)
    shadow = Image.new("RGBA", SIZE)
    shadow_mask = Image.new("L", SIZE)
    shadow_mask.paste(window.getchannel("A"), (180, 520))
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(35)).point(lambda v: int(v * 0.27))
    shadow.putalpha(shadow_mask)
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(window, (180, 500))
    path = OUTPUT / f"{index:02d}-{page}.jpg"
    canvas.convert("RGB").save(path, quality=95, subsampling=0, optimize=True)
    print(path)
    return path


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    # The product gallery has exactly these five assets, in this order.
    for path in OUTPUT.glob("*.jpg"):
        path.unlink()
    paths = [render(index, shot) for index, shot in enumerate(SHOTS, 1)]
    sheet = Image.new("RGB", (1440, 1350), "#161923")
    for index, path in enumerate(paths):
        preview = Image.open(path).resize((720, 450), Image.Resampling.LANCZOS)
        sheet.paste(preview, ((index % 2) * 720, (index // 2) * 450))
    sheet.save(SOURCE / "contact-sheet.jpg", quality=94)


if __name__ == "__main__":
    main()
