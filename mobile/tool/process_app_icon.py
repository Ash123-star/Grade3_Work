"""Create tightly framed Android and Flutter icon assets from the supplied icon."""
from pathlib import Path
from PIL import Image

root = Path(__file__).parents[1]
source = root / "assets" / "icon_desktop.png"
image = Image.open(source).convert("RGBA")

# The source contains a nearly transparent cream shadow around the illustration.
# Use the visible colored core, then retain a small transparent safety margin.
pixels = image.load()
points = []
for y in range(image.height):
    for x in range(image.width):
        r, g, b, a = pixels[x, y]
        if a >= 60 and (max(r, g, b) - min(r, g, b) > 12 or min(r, g, b) < 235):
            points.append((x, y))
if not points:
    raise RuntimeError("icon has no visible core")
left = max(0, min(x for x, _ in points) - 28)
top = max(0, min(y for _, y in points) - 28)
right = min(image.width, max(x for x, _ in points) + 29)
bottom = min(image.height, max(y for _, y in points) + 29)
side = max(right - left, bottom - top)
cx, cy = (left + right) / 2, (top + bottom) / 2
left = max(0, int(round(cx - side / 2)))
top = max(0, int(round(cy - side / 2)))
right = min(image.width, left + side)
bottom = min(image.height, top + side)
side = min(right - left, bottom - top)
right, bottom = left + side, top + side

cropped = image.crop((left, top, right, bottom))
out = root / "assets" / "icon_splash.png"
out.parent.mkdir(parents=True, exist_ok=True)
cropped.resize((512, 512), Image.Resampling.LANCZOS).save(out, optimize=True)

res = root / "android" / "app" / "src" / "main" / "res"
for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    target = res / f"mipmap-{density}" / "ic_launcher.png"
    cropped.resize((size, size), Image.Resampling.LANCZOS).save(target, optimize=True)

# Native splash uses a transparent bitmap over the paper background drawable.
cropped.resize((512, 512), Image.Resampling.LANCZOS).save(
    res / "drawable-nodpi" / "launch_image.png", optimize=True
)
print(f"Generated tightly framed icon from {source.name}: crop={(left, top, right, bottom)}")
