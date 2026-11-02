"""Generate Android launcher bitmaps without changing splash assets."""

import argparse
from pathlib import Path

from PIL import Image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Square PNG supplied by the user")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    source_bytes = args.source.read_bytes()
    with Image.open(args.source) as source:
        if source.format != "PNG" or source.width != source.height:
            parser.error("Source must be a square PNG")
        source.load()
        image = source.convert("RGB")

    desktop = root / "assets" / "icon_desktop.png"
    desktop.write_bytes(source_bytes)
    print(f"Stored original: {desktop}")
    res = root / "android" / "app" / "src" / "main" / "res"
    for density, size in {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }.items():
        target = res / f"mipmap-{density}" / "ic_launcher.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        image.resize((size, size), Image.Resampling.LANCZOS).save(target)
        print(f"Generated {density}: {size}x{size}")


if __name__ == "__main__":
    main()
