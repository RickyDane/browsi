"""Export native macOS icons from the approved SVG artwork.

Requires Xcode (Icon Composer), rsvg-convert and Pillow. Run from any directory.
Only Pulsar's layered document ships; alternates use Composer-rendered PNGs
because macOS's runtime Dock override accepts NSImage, not a layered icon.
"""

import copy
import json
from pathlib import Path
import runpy
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from PIL import Image


ROOT = Path(__file__).resolve().parent
RESOURCES = ROOT.parent / 'Browsi/Resources'
ASSETS = RESOURCES / 'Assets.xcassets'
SVG = '{http://www.w3.org/2000/svg}'
ET.register_namespace('', SVG[1:-1])


def layers(source):
    """Discard the concept's tile, border and shadow, not its artwork."""
    root = ET.parse(source).getroot()
    body = next(node for node in root if 'clip-path' in node.attrib)
    body = copy.deepcopy(body)
    del body.attrib['clip-path']
    if source.parent.name == 'galaxy':
        background = next(node for node in root if node.get('filter'))[0]
    else:
        background = body[0]
        body.remove(background)
    background = ET.Element(SVG + 'rect', {
        'width': '1024', 'height': '1024', 'fill': background.attrib['fill'],
    })
    for name, element in [('Background', background), ('Artwork', body)]:
        canvas = ET.Element(SVG + 'svg', {
            'width': '1024', 'height': '1024', 'viewBox': '0 0 1024 1024',
        })
        canvas.append(copy.deepcopy(root.find(SVG + 'defs')))
        canvas.append(element)
        yield name, ET.tostring(canvas)


def export():
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    composer = developer.parent / 'Applications/Icon Composer.app/Contents/Executables/ictool'
    icons = []
    for collection in ['space-02', 'space-03']:
        mapping = runpy.run_path(str(ROOT / collection / 'export-assets.py'))['ICONS']
        icons.extend((name, ROOT / collection / f'{slug}.svg') for name, slug in mapping.items())
    icons.extend((f'R{i}', ROOT / 'galaxy' / f'r{i}.svg') for i in range(1, 6))

    with tempfile.TemporaryDirectory() as temporary:
        temporary = Path(temporary)
        for name, source in icons:
            document = (RESOURCES / 'BrowsiIcon.icon' if name == 'Pulsar'
                        else temporary / f'{name}.icon')
            images = document / 'Assets'
            images.mkdir(parents=True, exist_ok=True)
            groups = []
            for layer_name, svg in layers(source):
                # Rasterize SVG filters consistently; Composer owns the enclosure
                # and material effects, not the concept's hand-drawn corner arcs.
                subprocess.run(['rsvg-convert', '-o', str(images / f'{layer_name}.png')],
                               input=svg, check=True)
                groups.append({
                    'layers': [{'image-name': f'{layer_name}.png', 'name': layer_name}],
                    'specular': layer_name == 'Artwork',
                    'shadow': {'kind': 'neutral', 'opacity': 0.25 if layer_name == 'Artwork' else 0},
                    'translucency': {'enabled': False, 'value': 0},
                })
            (document / 'icon.json').write_text(json.dumps({
                'fill': {'solid': 'srgb:0.03,0.05,0.1,1'},
                # Composer stores groups front-to-back (the background is last).
                'groups': list(reversed(groups)),
                'supported-platforms': {'squares': ['macOS']},
            }, indent=2) + '\n')
            rendered = temporary / f'{name}.png'
            subprocess.run([str(composer), str(document), '--export-image',
                            '--output-file', str(rendered), '--platform', 'macOS',
                            '--rendition', 'Default', '--width', '1024', '--height', '1024',
                            '--scale', '1'], check=True, stdout=subprocess.DEVNULL)
            with Image.open(rendered) as enclosure:
                # Composer exports just the enclosure. Legacy NSImage/ICNS Dock
                # icons need the standard macOS safe-area inset as well.
                image = Image.new('RGBA', (1024, 1024))
                image.paste(enclosure.resize((824, 824), Image.Resampling.LANCZOS), (100, 100))
                target = ASSETS / f'AppIcon{name}.imageset'
                for filename, size in [('icon.png', 512), ('icon@2x.png', 1024)]:
                    image.resize((size, size), Image.Resampling.LANCZOS).save(target / filename)
                if name == 'Pulsar':
                    fallback = ASSETS / 'AppIcon.appiconset'
                    for entry in json.loads((fallback / 'Contents.json').read_text())['images']:
                        size = int(entry['size'].split('x')[0]) * int(entry['scale'][0])
                        image.resize((size, size), Image.Resampling.LANCZOS).save(fallback / entry['filename'])
            print(f'Exported {name}', flush=True)


if __name__ == '__main__':
    export()
