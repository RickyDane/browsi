"""Exploration icon mapping and compatibility entry point for the native exporter."""

from pathlib import Path
import runpy


ROOT = Path(__file__).resolve().parent
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
    runpy.run_path(str(ROOT.parent / 'export-native-icons.py'), run_name='__main__')


if __name__ == '__main__':
    export()
