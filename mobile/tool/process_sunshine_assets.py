"""Crop the reviewed 4x4 icon / 2x2 mascot sheets; remove exterior white only."""
import argparse
from collections import deque
import hashlib
import json
from pathlib import Path
from PIL import Image
import numpy as np

ICONS = ['home', 'calendar', 'log', 'ai', 'members', 'task', 'notification',
         'approval', 'report', 'settings', 'help', 'empty', 'error', 'loading',
         'success', 'mindmap']
MASCOTS = ['welcome', 'journal', 'empty', 'assistant']


def isolate(image):
    pixels = np.array(image.convert('RGBA'))
    rgb = pixels[:, :, :3].astype(int)
    eligible = (rgb.min(axis=2) >= 228) & (rgb.max(axis=2) - rgb.min(axis=2) < 23)
    height, width = eligible.shape
    seen = np.zeros((height, width), dtype=bool)
    queue = deque()
    for y in range(height):
        queue.extend([(y, 0), (y, width - 1)])
    for x in range(width):
        queue.extend([(0, x), (height - 1, x)])
    while queue:
        y, x = queue.popleft()
        if y < 0 or x < 0 or y >= height or x >= width or seen[y, x] or not eligible[y, x]:
            continue
        seen[y, x] = True
        queue.extend([(y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)])
    pixels[seen, 3] = 0
    result = Image.fromarray(pixels)
    bounds = result.getbbox()
    if bounds is None:
        raise ValueError('Empty tile')
    return result.crop(bounds), bounds


def process(source, names, columns, destination, size):
    source_image = Image.open(source).convert('RGBA')
    records = []
    destination.mkdir(parents=True, exist_ok=True)
    for index, name in enumerate(names):
        row, col = divmod(index, columns)
        bounds = tuple(round(n) for n in (col * source_image.width / columns,
                       row * source_image.height / columns,
                       (col + 1) * source_image.width / columns,
                       (row + 1) * source_image.height / columns))
        cut, content_bounds = isolate(source_image.crop(bounds))
        cut.thumbnail((round(size * .9), round(size * .9)), Image.Resampling.LANCZOS)
        canvas = Image.new('RGBA', (size, size))
        canvas.alpha_composite(cut, ((size - cut.width) // 2, (size - cut.height) // 2))
        path = destination / (name + '.png')
        canvas.save(path, optimize=True)
        records.append({'name': name, 'file': path.name, 'sheet_bounds': bounds,
                        'content_bounds': content_bounds, 'size': [size, size],
                        'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    return {'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'assets': records}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--icons', type=Path, required=True)
    parser.add_argument('--mascots', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    manifest = {
        'method': 'equal-grid crop, connected exterior near-white removal, alpha preserved, normalized padding',
        'icons': process(args.icons, ICONS, 4, args.out / 'icons', 192),
        'mascots': process(args.mascots, MASCOTS, 2, args.out / 'mascots', 384),
    }
    (args.out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print('Saved 16 icons and 4 mascots:', args.out)


if __name__ == '__main__':
    main()
