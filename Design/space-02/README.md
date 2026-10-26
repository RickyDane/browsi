# Browsi — space collection 02

Eight additional space-themed logo concepts, all available in Settings › Appearance.
Pulsar is the default bundled app icon; existing saved icon choices are preserved.

Open **sheet.png** for the comparison, including 16 / 32 / 64 px checks.
Each concept has an editable SVG and a transparent 1024 × 1024 PNG with a
macOS-style rounded tile inset.

1. **Orbital b** — a planetary lowercase monogram in mint and ice blue.
2. **Soft Saturn** — a lilac planet with a champagne ring.
3. **Transit** — a dark planet crossing a warm sun.
4. **Pulsar** — an icy navigation star and signal rings.
5. **Moon gate** — a rose-colored portal onto a lunar landscape.
6. **Orbit cursor** — a browser pointer on a discovery orbit.
7. **Solar sail** — a folded, starlight-powered explorer.
8. **Binary** — two pastel worlds sharing an orbit.

Regenerate from any working directory with:

```sh
python3 Design/space-02/make.py
```

Requires Python 3 and `rsvg-convert` (Homebrew: `brew install librsvg`).
Artwork is deterministic and self-contained; no downloaded assets or fonts.

After regenerating the PNGs, run `python3 Design/space-02/export-assets.py`
to refresh the eight Settings image sets and the Pulsar bundle icon. This step
requires Pillow and uses the existing asset catalog manifests.
