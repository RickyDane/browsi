# Browsi — space collection 03

Eight new space-themed logo directions. Open **sheet.png** for the comparison
and small-size checks. Every concept includes an editable SVG and a transparent
1024 × 1024 PNG with an inset macOS-style tile.

| Concept | Direction |
| --- | --- |
| 01 / Gravity b | A mint monogram bent by a passing peach-colored world. |
| 02 / Nova bloom | Six luminous petals unfolding from a stellar core. |
| 03 / Deepfield | A hexagonal telescope aperture framing a distant nebula. |
| 04 / Star trail | A comet wrapping around a browser window. |
| 05 / Red dwarf | A warm stellar heart and a tiny companion. |
| 06 / Lagrange | Interlocking orbital trajectories and a guiding star. |
| 07 / Ion ribbon | A continuous icy-blue ribbon accelerating into space. |
| 08 / Cosmic eye | A lavender eye with an interstellar lens. |

All eight are available in Settings › Appearance. Pulsar remains the default,
and existing saved icon choices are preserved.

Regenerate from any working directory:

```sh
python3 /path/to/browsi/Design/space-03/make.py
```

Requires Python 3 and `rsvg-convert` (`brew install librsvg`). Output is
deterministic; artwork uses no downloaded assets or fonts. Keep the PNGs beside
`sheet.svg` when sharing the vector sheet, as its small-size previews link to them.

After regenerating the PNGs, run `python3 Design/space-03/export-assets.py`
from the repository root to refresh the eight app image sets. This requires
Pillow and does not change the bundled Pulsar icon.
