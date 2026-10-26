"""Export collection 03 to alternate app image sets (requires Pillow)."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
ASSETS = ROOT.parents[1] / 'Browsi/Resources/Assets.xcassets'
ICONS = {
    'GravityB': '01-gravity-b',
    'NovaBloom': '02-nova-bloom',
    'Deepfield': '03-deepfield',
    'StarTrail': '04-star-trail',
    'RedDwarf': '05-red-dwarf',
    'Lagrange': '06-lagrange',
    'IonRibbon': '07-ion-ribbon',
    'CosmicEye': '08-cosmic-eye',
}


def export():
    for name, slug in ICONS.items():
        with Image.open(ROOT / f'{slug}.png') as image:
            target = ASSETS / f'AppIcon{name}.imageset'
            for filename, size in [('icon.png', 512), ('icon@2x.png', 1024)]:
                image.resize((size, size), Image.Resampling.LANCZOS).save(target / filename)
    print('Exported all eight collection 03 icons; Pulsar is unchanged.')


if __name__ == '__main__':
    export()
