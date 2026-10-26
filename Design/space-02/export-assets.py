"""Space icon mapping and compatibility entry point for the native exporter."""

import runpy
from pathlib import Path

ROOT = Path(__file__).resolve().parent
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
    runpy.run_path(str(ROOT.parent / 'export-native-icons.py'), run_name='__main__')


if __name__ == '__main__':
    export()
