"""Create HTML artboards from real native captures for 1440 × 1080 JPEG exports.

Run the website capture plan and diskmap-website-cutouts.lua, then this script. Serve build/diskmap-website
locally and capture each promo-*.html at a 1440 × 1080 viewport. Save the JPEGs to
web/diskmap/assets/ with the same names and the .jpg extension. Artboards arrange real UI cutouts without any full application windows.
"""

from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build" / "diskmap-website"
OUTPUT.mkdir(parents=True, exist_ok=True)
shutil.copyfile(ROOT / "web/diskmap/assets/icon.png", OUTPUT / "icon.png")

SHOTS = {
    "map": ("See what fills your Mac.", "Explore a visual map of your storage, one category at a time.", "#161621", "#f6f2ff", "#b3a6c9", "#6a3c8155", "#334b7955"),
    "cleanup": ("Make space. With context.", "Understand what can be rebuilt. Review the details before you clear.", "#e8eeeb", "#203930", "#597166", "#b2cfcf88", "#cfdfb988"),
    "developer": ("Know your tools’ footprint.", "Xcode, simulators, package caches, and more. See where it all adds up.", "#e9e5f2", "#302544", "#71627e", "#d8b4db77", "#aebfe577"),
}

PIECES = ("map-cutout", "map-row-1", "map-row-2", "map-row-3", "rebuildable-cutout", "review-cutout", "checked-cutout", "developer-row-1", "developer-row-2", "developer-row-3")
for piece in PIECES:
    shutil.copyfile(ROOT / "web/diskmap/assets" / f"{piece}.png", OUTPUT / f"{piece}.png")

COMPOSITIONS = {
    "map": '<img class="sunburst" src="map-cutout.png" alt="Isolated storage map">' + ''.join(f'<img class="map-row row-{i}" src="map-row-{i}.png" alt="Storage category row">' for i in range(1, 4)),
    "cleanup": '<img class="stat rebuildable" src="rebuildable-cutout.png" alt="Rebuildable storage"><img class="stat review" src="review-cutout.png" alt="Storage to review"><img class="stat checked" src="checked-cutout.png" alt="Checked locations">',
    "developer": '<p class="group-label">XCODE &amp; SIMULATORS</p>' + ''.join(f'<img class="developer-row row-{i}" src="developer-row-{i}.png" alt="Developer storage row">' for i in range(1, 4)),
}

for name, (title, subtitle, background, ink, muted, glow_a, glow_b) in SHOTS.items():
    html = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Diskmap — {name}</title>
<style>
* {{ box-sizing: border-box; }}
html {{ margin: 0; width: 1440px; height: 1080px; overflow: hidden; }}
body {{ margin: 0; width: 1600px; height: 1200px; overflow: hidden; transform: scale(.9); transform-origin: top left; }}
body {{ color: {ink}; background: radial-gradient(ellipse at 100% 20%, {glow_a}, transparent 60%), radial-gradient(ellipse at 0% 85%, {glow_b}, transparent 60%), {background}; font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }}
header {{ position: absolute; top: 48px; left: 80px; right: 80px; display: flex; align-items: center; justify-content: space-between; }}
.brand {{ display: flex; align-items: center; gap: 12px; font-size: 26px; font-weight: 650; letter-spacing: -.04em; }}
.brand img {{ width: 44px; height: 44px; border-radius: 10px; }}
.platform {{ font-size: 12px; letter-spacing: .15em; color: {muted}; }}
h1 {{ position: absolute; top: 132px; left: 80px; margin: 0; font-size: 82px; line-height: 1.1; letter-spacing: -.055em; font-weight: 650; }}
.subtitle {{ position: absolute; top: 235px; left: 84px; margin: 0; font-size: 24px; color: {muted}; }}
.sunburst {{ position: absolute; left: 750px; top: 345px; width: 768px; height: 768px; filter: drop-shadow(0 30px 30px #00000030); }}
.map-row {{ position: absolute; left: 100px; width: 620px; height: auto; border-radius: 13px; box-shadow: 0 20px 40px #00000040; }}
.map-row.row-1 {{ top: 590px; }}
.map-row.row-2 {{ top: 720px; }}
.map-row.row-3 {{ top: 850px; }}
.stat {{ position: absolute; height: auto; border-radius: 28px; box-shadow: 0 30px 60px #23483c22; }}
.rebuildable {{ top: 380px; left: 110px; width: 700px; }}
.review {{ top: 545px; left: 790px; width: 700px; }}
.checked {{ top: 800px; left: 220px; width: 800px; }}
.group-label {{ position: absolute; top: 380px; left: 150px; color: {muted}; font-size: 15px; letter-spacing: .13em; }}
.developer-row {{ position: absolute; left: 150px; width: 1300px; height: auto; border-radius: 14px; box-shadow: 0 24px 42px #30254430; }}
.developer-row.row-1 {{ top: 480px; }}
.developer-row.row-2 {{ top: 680px; }}
.developer-row.row-3 {{ top: 880px; }}
footer {{ position: absolute; bottom: 34px; left: 80px; right: 80px; display: flex; justify-content: space-between; font-size: 13px; color: {muted}; }}
</style></head><body><header><div class="brand"><img src="icon.png" alt="">Diskmap</div><span class="platform">NATIVE ON MACOS 26</span></header><h1>{title}</h1><p class="subtitle">{subtitle}</p>{COMPOSITIONS[name]}<footer><span>Real UI cutouts. Synthetic example data.</span><span>corepunch.github.io/lua-objc/diskmap</span></footer></body></html>'''
    (OUTPUT / f"promo-{name}.html").write_text(html, encoding="utf-8")
    print(OUTPUT / f"promo-{name}.html")
