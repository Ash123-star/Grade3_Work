"""Create reusable transparent PNGs from the user's 4x4 dog sprite sheets."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SHEETS = {
    "avatar": ("头像.png", "avatars", 4),
    "pose": ("全身像.png", "poses", 4),
    "background": ("淡化背景.png", "backgrounds", 4),
}

# Tilted heads cross grid rows. Keep their lower edge and exclude it
# from the following row. Coordinates were reviewed on original sheets.
REVIEWED_BOXES = {
    ('avatar', 4): (1086, 0, 1448, 295),
    ('avatar', 8): (1086, 295, 1448, 543),
    ('pose', 1): (0, 0, 314, 345),
    ('pose', 2): (314, 0, 627, 345),
    ('pose', 5): (0, 345, 314, 627),
    ('pose', 6): (314, 345, 627, 627),
}
USAGE = {
    'avatars': {
        'recommended': [4, 8, 9, 10, 11, 12, 16],
        'today': 15,
        'dashboard_cards': [1, 8, 11, 16],
        'purpose': 'page and section titles, weekday labels, dashboard decoration; never user identity',
    },
    'poses': {'recommended': [7, 10, 16], 'purpose': 'welcome or form decoration, never status'},
    'backgrounds': {'recommended': [3, 4, 7, 8], 'purpose': 'single faint figure; preserve source alpha'},
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def crop_sheet(source: Path, output: Path, name: str, grid: int) -> list[dict]:
    records = []
    with Image.open(source) as original:
        if original.format != "PNG" or "A" not in original.getbands():
            raise ValueError(f"Expected an alpha PNG: {source}")
        image = original.convert("RGBA")
        width, height = image.size
        for row in range(grid):
            for column in range(grid):
                left = round(column * width / grid)
                top = round(row * height / grid)
                right = round((column + 1) * width / grid)
                bottom = round((row + 1) * height / grid)
                number = row * grid + column + 1
                left, top, right, bottom = REVIEWED_BOXES.get(
                    (name, number), (left, top, right, bottom)
                )
                tile = image.crop((left, top, right, bottom))
                alpha = tile.getchannel("A").point(lambda value: 0 if value < 16 else value)
                bounds = alpha.getbbox()
                if bounds is None:
                    raise ValueError(f"Transparent grid cell: {source} row={row + 1} col={column + 1}")
                tile.putalpha(alpha)
                x0, y0, x1, y1 = bounds
                padding = max(4, round(min(tile.size) * 0.035))
                bounds = (
                    max(0, x0 - padding),
                    max(0, y0 - padding),
                    min(tile.width, x1 + padding),
                    min(tile.height, y1 + padding),
                )
                tile = tile.crop(bounds)
                filename = f"{name}_{row * grid + column + 1:02d}.png"
                destination = output / filename
                destination.parent.mkdir(parents=True, exist_ok=True)
                tile.save(destination, optimize=True)
                records.append(
                    {
                        "source": source.relative_to(ROOT).as_posix(),
                        "source_sha256": sha256(source),
                        "grid": [grid, grid],
                        "cell": [row + 1, column + 1],
                        "crop_box": [left, top, right, bottom],
                        "content_crop_box": [
                            left + bounds[0], top + bounds[1],
                            left + bounds[2], top + bounds[3],
                        ],
                        "notes": (
                            'Source touches the left sheet edge; do not use as a complete pose'
                            if name == 'pose' and number == 1 else
                            'Reviewed crop crossing a grid row'
                            if (name, number) in REVIEWED_BOXES else ''
                        ),
                        "output": destination.relative_to(ROOT).as_posix(),
                        "size": list(tile.size),
                        "alpha_extrema": list(tile.getchannel("A").getextrema()),
                        "sha256": sha256(destination),
                    }
                )
    return records


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=ROOT / "assets" / "dog")
    parser.add_argument(
        "--output", type=Path, default=ROOT / "assets" / "generated_ui" / "dog"
    )
    args = parser.parse_args()
    source_root = args.source.resolve()
    output_root = args.output.resolve()
    manifest = []
    for category, (filename, folder, grid) in SHEETS.items():
        source = source_root / filename
        if not source.is_file():
            raise FileNotFoundError(source)
        manifest.extend(crop_sheet(source, output_root / folder, category, grid))
    manifest_path = output_root / "manifest.json"
    manifest_path.write_text(
        json.dumps(
            {
                "source_type": "user-provided-generated-transparent-png",
                "grid": "4x4 row-major with reviewed cross-row crop boxes; originals unchanged",
                "usage": USAGE,
                "review": "Contact sheets inspected on warm white; runtime UI not verified",
                "asset_count": len(manifest),
                "assets": manifest,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"Generated {len(manifest)} reusable PNGs: {output_root}")


if __name__ == "__main__":
    main()
