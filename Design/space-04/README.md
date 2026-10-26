# Browsi — space collection 04

Open **sheet.png** to compare eight new concepts and their 16 / 32 / 64 px
previews. Each concept has an editable SVG and a transparent 1024 × 1024 PNG
with an inset macOS-style tile.

1. **Moon moth** — a nocturnal explorer with crescent markings on pastel wings.
2. **Astrolabe** — a brass celestial instrument and its mint-colored companion.
3. **Starglass** — an hourglass measuring time in falling stars.
4. **Helios** — a golden sun with a cool crescent heart.
5. **Escape velocity** — a rising vector leaving an orbital wake.
6. **Night sail** — a crescent vessel sailing between stars.
7. **Pocket cosmos** — a ringed world tucked inside a browser tab.
8. **Nebula knot** — three luminous loops woven around a guiding star.

Design concepts only: no changes to Settings, installed icons, or the Pulsar
default. The comparison SVG embeds its PNG previews and can be shared alone.

Regenerate with Python 3 and `rsvg-convert` (`brew install librsvg`):

```sh
python3 Design/space-04/make.py
```

The script resolves output paths relative to itself and is deterministic.
No downloaded artwork or fonts are used.
