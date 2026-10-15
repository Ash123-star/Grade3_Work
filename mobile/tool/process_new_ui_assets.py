"""Deterministic local atlas extraction; originals are never written.

Requires Pillow and NumPy. Output paths and crop coordinates are recorded in a
manifest with SHA256 so a visual crop can be traced back to the supplied atlas.
"""
from pathlib import Path
from collections import deque
import argparse
import hashlib
import json
import numpy as np
from PIL import Image, ImageChops

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=Path(__file__).parents[1] / 'assets/new')
parser.add_argument('--output', type=Path, default=Path(__file__).parents[1] / 'assets/generated_ui/new_pack')
args = parser.parse_args()
manifest = []

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def crop(source, output, box, clean=False, texture=False):
    path = args.source / source
    with Image.open(path) as original:
        x, y, w, h = box
        if min(x, y) < 0 or min(w, h) <= 0 or x+w > original.width or y+h > original.height:
            raise ValueError(f'Invalid crop: {source} {box} / {original.size}')
        im = original.convert('RGBA').crop((x, y, x+w, y+h))
    if clean:
        # Remove only grayscale background reachable from the image edge. Cream
        # card interiors remain protected by the colored boundary.
        data = np.array(im)
        rgb = data[:, :, :3].astype(np.int16)
        background = (rgb.max(2)-rgb.min(2) <= 12) & (rgb.min(2) >= 175)
        seen = np.zeros((h, w), dtype=bool)
        queue = deque()
        def seed(px, py):
            if not seen[py, px] and background[py, px]:
                seen[py, px] = True
                queue.append((px, py))
        for px in range(w):
            seed(px, 0); seed(px, h-1)
        for py in range(h):
            seed(0, py); seed(w-1, py)
        while queue:
            px, py = queue.popleft()
            for nx, ny in ((px-1, py), (px+1, py), (px, py-1), (px, py+1)):
                if 0 <= nx < w and 0 <= ny < h:
                    seed(nx, ny)
        data[seen, 3] = 0
        im = Image.fromarray(data)
    if not texture:
        alpha = im.getchannel('A').point(lambda a: 0 if a < 24 else a)
        bounds = alpha.getbbox()
        if bounds is None:
            raise ValueError(f'Empty crop: {source} {output}')
        im.putalpha(alpha)
        im = im.crop(bounds)
    dest = args.output / output
    dest.parent.mkdir(parents=True, exist_ok=True)
    im.save(dest, optimize=True)
    manifest.append(dict(source=source, source_sha256=sha(path), crop=list(box),
        edge_cleanup=clean, output=output, size=list(im.size), sha256=sha(dest),
        alpha_extrema=list(im.getchannel('A').getextrema())))

def rows(source, folder, entries, **kw):
    for name, x, y, w, h in entries:
        crop(source, f'{folder}/{name}.png', (x,y,w,h), **kw)

rows('卡片边框.png', 'surfaces/cards', [
    ('card_mint',160,40,465,575), ('card_warm',640,40,475,575),
    ('card_blue',15,620,420,585), ('card_lavender',435,620,400,585),
    ('card_coral',835,620,415,585)])
rows('卡片角落叠加装饰.png', 'surfaces/card_corners', [
    ('mint_corner',15,35,395,455), ('warm_corner',430,35,395,455),
    ('blue_corner',840,35,395,455), ('lavender_corner',15,510,395,440),
    ('coral_corner',430,510,395,440), ('green_corner',840,510,395,440),
    ('blue_blob',15,950,330,270), ('lavender_wave',390,950,300,270),
    ('mint_arc',730,950,260,270), ('coral_swirl',990,950,260,270)])
rows('图标托盘和按钮皮肤.png', 'controls/button_skins', [
    ('button_mint',20,155,600,290), ('button_coral',635,155,605,290),
    ('button_lavender',20,475,600,300), ('button_warm',635,475,605,300),
    ('button_blue',20,795,600,300), ('button_cream',635,795,605,300)])
rows('详情页装饰.png', 'surfaces/detail_sections', [
    ('detail_mint',35,55,585,335), ('detail_warm',635,55,585,335),
    ('detail_blue',35,430,585,335), ('detail_lavender',635,430,585,335),
    ('detail_coral',35,805,1185,350)], clean=True)
rows('选中态和筛选器皮肤.png', 'controls/selection_skins', [
    (f'filter_{name}',x,y,540,220) for name,x,y in [
        ('coral',75,35),('mint',650,35),('lavender',75,270),('cream',650,270),
        ('coral_wave',75,505),('mint_leaf',650,505),('lavender_tail',75,740),
        ('warm',650,740),('blue',75,975),('pink',650,975)]])
# Cells contain no sample events; pills are extracted from the independent pack.
rows('日历.png','calendar/cells',[('cell_selected',735,845,247,288)])
rows('日历.png','calendar/record_pills',[
    ('pill_green',980,875,115,80),('pill_red',1100,875,140,80),
    ('pill_purple',980,960,115,80),('pill_blue',1100,960,140,80),
    ('pill_yellow',980,1050,115,75),('pill_blue_large',35,1030,290,125),
    ('pill_yellow_large',350,1030,290,125)])
# Only tile interiors are exported: the atlas outlines must not repeat as a grid.
names=['paper','coral_dots','mint_grid','coral_diagonal','warm_sparkle',
       'blue_swirl','lavender_cloud','mint_wave','paper_alt','coral_dots_alt',
       'mint_grid_alt','coral_diagonal_alt','warm_sparkle_alt','blue_swirl_alt',
       'lavender_cloud_alt','mint_wave_alt']
for i,name in enumerate(names):
    crop('纹理.jpg',f'textures/{name}.png',
         (67+(i%4)*310,76+(i//4)*300,178,178),texture=True)
rows('AI 建议卡.png','ai',[
    ('thinking_cluster',35,95,360,330),('source_cloud',390,95,420,330),
    ('relation_map',820,95,395,330),('priority_badge',35,450,360,350),
    ('confirm',440,450,360,350),('warning',825,450,390,350),
    ('thinking_mascot',390,815,430,380)])
rows('弹窗、底部弹层和 Toast 皮肤.png','surfaces/feedback',[
    ('modal_panel',30,90,690,490),('toast_success',760,90,450,160),
    ('toast_warning',760,270,450,160),('toast_error',760,450,450,160),
    ('bottom_sheet',35,650,1180,490)],clean=True)
rows('卡通背景插画层.png','backgrounds/illustration_layers',[
    ('workspace_top_left',0,0,360,360),('workspace_top_right',870,0,384,390),
    ('workspace_bottom_left',0,820,380,434),
    ('workspace_bottom_right',850,735,404,519)])
crop('指标卡背景.png','surfaces/metric_card/metric_card_warm.png',(20,160,984,700))
# Safe independently cropped corner ornaments, no full-card backdrop.
rows('卡片角落叠加装饰.png','decorations',[
    ('mint_corner',15,35,155,150),('warm_corner',430,35,155,150),
    ('blue_corner',1030,35,205,155),('lavender_corner',15,510,180,145),
    ('coral_corner',430,510,180,145)])
# Normalized nine-slice skins. Corners are kept at a fixed logical size by the
# Flutter image scale; only the blank content area may grow with real text.
for entry in list(manifest):
    folder = entry['output'].split('/')[0:2]
    category = '/'.join(folder)
    sizes = {
        'surfaces/cards': (240, 300),
        'surfaces/card_corners': (240, 260),
        'surfaces/detail_sections': (360, 190),
        'surfaces/metric_card': (360, 220),
        'controls/button_skins': (300, 130),
        'controls/selection_skins': (300, 120),
        'calendar/cells': (240, 280),
        'calendar/record_pills': (240, 100),
        'surfaces/feedback': (360, 160),
    }
    if category not in sizes:
        continue
    if category == 'surfaces/card_corners' and '_corner' not in Path(entry['output']).stem:
        continue
    if category == 'surfaces/feedback' and not Path(entry['output']).stem.startswith('toast_'):
        continue
    src = args.output / entry['output']
    dest = args.output / 'skins' / src.name
    dest.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(src) as im:
        im.resize(sizes[category], Image.Resampling.LANCZOS).save(dest, optimize=True)
    manifest.append(dict(source=entry['source'], source_sha256=entry['source_sha256'],
        crop=entry['crop'], derived_from=entry['output'], transform='normalized-nine-slice',
        output=f'skins/{src.name}', size=list(sizes[category]), sha256=sha(dest)))
(args.output/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(f'Processed {len(manifest)} assets; originals unchanged; manifest: {args.output / "manifest.json"}')
