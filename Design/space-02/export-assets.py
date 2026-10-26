"""Export the space collection to the app asset catalog (requires Pillow)."""

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
ASSETS = ROOT.parents[1] / 'Browsi/Resources/Assets.xcassets'
ICONS = {
    'OrbitalB': '01-orbital-b',
    'SoftSaturn': '02-saturn',
    'Transit': '03-transit',
    'Pulsar': '04-pulsar',
    'MoonGate': '05-moon-gate',
    'OrbitCursor': '06-orbit-cursor',
    'SolarSail': '07-solar-sail',
    'Binary': '08-binary',
}


def export():
    for name, slug in ICONS.items():
        with Image.open(ROOT / f'{slug}.png') as image:
            target = ASSETS / f'AppIcon{name}.imageset'
            for filename, size in [('icon.png', 512), ('icon@2x.png', 1024)]:
                image.resize((size, size), Image.Resampling.LANCZOS).save(target / filename)

    target = ASSETS / 'AppIcon.appiconset'
    manifest = json.loads((target / 'Contents.json').read_text())
    with Image.open(ROOT / '04-pulsar.png') as image:
        for entry in manifest['images']:
            size = int(entry['size'].split('x')[0]) * int(entry['scale'][0])
            image.resize((size, size), Image.Resampling.LANCZOS).save(target / entry['filename'])
    print('Exported eight alternate icons and the Pulsar bundle icon.')


if __name__ == '__main__':
    export()
