"""Generate Browsi's second space collection. Requires rsvg-convert on PATH."""

from html import escape
from pathlib import Path
import random
import shutil
import subprocess


ROOT = Path(__file__).resolve().parent
TILE = 'M286 100H738A186 186 0 0 1 924 286V738A186 186 0 0 1 738 924H286A186 186 0 0 1 100 738V286A186 186 0 0 1 286 100Z'
COMMON = '''
<clipPath id="tile"><path d="''' + TILE + '''"/></clipPath>
<filter id="glow" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="22"/></filter>
<linearGradient id="sky" x2="0.8" y2="1"><stop stop-color="#1E2146"/><stop offset="1" stop-color="#070C1C"/></linearGradient>
<linearGradient id="ice" x2="0.8" y2="1"><stop stop-color="#EBFFFF"/><stop offset="0.45" stop-color="#8BF5E4"/><stop offset="1" stop-color="#48A7FF"/></linearGradient>
<linearGradient id="rose" x2="0.85" y2="1"><stop stop-color="#FFE6CF"/><stop offset="0.5" stop-color="#FF9EA9"/><stop offset="1" stop-color="#AA86F4"/></linearGradient>
<linearGradient id="gold" x2="0.9" y2="1"><stop stop-color="#FFF4CB"/><stop offset="0.55" stop-color="#FFCF7D"/><stop offset="1" stop-color="#F0806D"/></linearGradient>
<radialGradient id="planet" cx="0.28" cy="0.2" r="0.85"><stop stop-color="#B2A3FF"/><stop offset="0.5" stop-color="#6557C5"/><stop offset="1" stop-color="#252446"/></radialGradient>
'''


def stars(seed):
    rng = random.Random(seed)
    return ''.join(
        f'<circle cx="{rng.randrange(160, 865)}" cy="{rng.randrange(160, 865)}" '
        f'r="{rng.choice([1.5, 2, 2.5])}" fill="#DDE5FF" opacity="{rng.uniform(.2, .55):.2f}"/>'
        for _ in range(32)
    )


def spark(x, y, size, color='#FFF4DE'):
    return (f'<path d="M{x} {y-size}Q{x+3} {y-3} {x+size} {y}'
            f'Q{x+3} {y+3} {x} {y+size}Q{x-3} {y+3} {x-size} {y}'
            f'Q{x-3} {y-3} {x} {y-size}Z" fill="{color}"/>')


def icon(title, body, seed, defs=''):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            f'viewBox="0 0 1024 1024" role="img" aria-labelledby="title">'
            f'<title id="title">Browsi — {escape(title)}</title><defs>{COMMON}{defs}</defs>'
            f'<g clip-path="url(#tile)"><path d="{TILE}" fill="url(#sky)"/>'
            f'{stars(seed)}{body}</g><path d="{TILE}" fill="none" stroke="#DAE4FF" '
            'stroke-opacity="0.14" stroke-width="2"/></svg>')


# Broad silhouettes and deliberately restrained detail keep these legible in the Dock.
CONCEPTS = [
    ('01-orbital-b', 'Orbital b', 'A planetary monogram. Small letter, big universe.', icon('Orbital b', '''
<ellipse cx="520" cy="560" rx="327" ry="116" transform="rotate(-28 520 560)" fill="none" stroke="#8BF5E4" stroke-width="5" opacity="0.24"/>
<path d="M365 273V562A158 158 0 1 0 523 404" fill="none" stroke="#63C9DE" stroke-width="105" opacity="0.28" filter="url(#glow)"/>
<path d="M365 273V562A158 158 0 1 0 523 404A158 158 0 0 0 365 562" fill="none" stroke="url(#ice)" stroke-width="78" stroke-linecap="round"/>
<path d="M226 651Q453 745 806 416" fill="none" stroke="#DCFFF8" stroke-width="12" stroke-linecap="round"/>
<circle cx="790" cy="433" r="22" fill="#FFF2CB"/>
''' + spark(698, 269, 27), 21)),

    ('02-saturn', 'Soft Saturn', 'A quiet lilac planet with a champagne orbit.', icon('Soft Saturn', '''
<g transform="rotate(-27 512 520)">
<ellipse cx="512" cy="520" rx="330" ry="105" fill="none" stroke="#D8B3BB" stroke-width="38"/>
<circle cx="512" cy="520" r="205" fill="url(#planet)"/>
<path d="M324 446Q499 520 697 449M312 520Q500 597 707 523M337 604Q512 660 686 606" fill="none" stroke="#C3AFFF" stroke-opacity="0.16" stroke-width="17"/>
<path d="M182 520A330 105 0 0 0 842 520" fill="none" stroke="url(#gold)" stroke-width="38"/>
<path d="M184 530Q218 584 337 610" fill="none" stroke="#FFF2D4" stroke-width="7" stroke-linecap="round"/>
</g>
''' + spark(727, 286, 25), 22)),

    ('03-transit', 'Transit', 'A tiny world crossing a warm, luminous sun.', icon('Transit', '''
<circle cx="512" cy="514" r="246" fill="#FFB786" opacity="0.22" filter="url(#glow)"/>
<circle cx="512" cy="514" r="226" fill="url(#gold)"/>
<path d="M277 695Q494 705 755 374" fill="none" stroke="#FFF2D6" stroke-width="5" opacity="0.6"/>
<circle cx="622" cy="560" r="98" fill="#10162A"/>
<path d="M597 465A98 98 0 0 1 716 588" fill="none" stroke="#FFF5D7" stroke-width="4"/>
''' + spark(292, 296, 24), 23)),

    ('04-pulsar', 'Pulsar', 'A navigation star. A signal through the noise.', icon('Pulsar', '''
<circle cx="512" cy="512" r="251" fill="none" stroke="#9AC1FF" stroke-width="3" opacity="0.22"/>
<circle cx="512" cy="512" r="170" fill="none" stroke="#9AC1FF" stroke-width="3" opacity="0.17"/>
<g transform="rotate(22 512 512)">
<path d="M512 227Q537 474 734 512Q537 550 512 797Q487 550 290 512Q487 474 512 227Z" fill="#83DFFF" opacity="0.5" filter="url(#glow)"/>
<path d="M512 227Q537 474 734 512Q537 550 512 797Q487 550 290 512Q487 474 512 227Z" fill="url(#ice)"/>
</g>
<circle cx="512" cy="512" r="26" fill="#F4FFFF"/>
<circle cx="741" cy="409" r="17" fill="#FFCEA0"/>
''', 24)),

    ('05-moon-gate', 'Moon gate', 'An open doorway onto another world.', icon('Moon gate', '''
<path d="M317 759V439A195 195 0 0 1 707 439V759Z" fill="url(#rose)"/>
<path d="M369 759V443A143 143 0 0 1 655 443V759Z" fill="#131A33"/>
<g clip-path="url(#door)">
<circle cx="590" cy="437" r="92" fill="url(#gold)"/>
<path d="M337 678Q464 510 702 656V800H337Z" fill="#7669B0"/>
<path d="M337 744Q480 619 702 713V800H337Z" fill="#393D6A"/>
</g>
<path d="M287 763H737" stroke="#FFD2C6" stroke-width="13" stroke-linecap="round"/>
''' + spark(476, 420, 17), 25,
        '<clipPath id="door"><path d="M369 759V443A143 143 0 0 1 655 443V759Z"/></clipPath>')),

    ('06-orbit-cursor', 'Orbit cursor', 'A browser pointer, ready for deep-space discovery.', icon('Orbit cursor', '''
<g transform="rotate(-31 512 512)">
<ellipse cx="512" cy="512" rx="299" ry="192" fill="none" stroke="#8B91C4" stroke-width="5" opacity="0.45"/>
<path d="M213 512A299 192 0 0 1 811 512" fill="none" stroke="url(#rose)" stroke-width="18" stroke-linecap="round"/>
<circle cx="811" cy="512" r="28" fill="#FFD3B9"/>
</g>
<path d="M401 326L680 589L553 607L489 718Z" fill="#4FAEBF" opacity="0.3" filter="url(#glow)"/>
<path d="M389 309L687 585L552 605L485 725Z" fill="url(#ice)" stroke="#D9FFFA" stroke-width="5" stroke-linejoin="round"/>
<path d="M405 332L552 605" stroke="#FFFFFF" stroke-opacity="0.5" stroke-width="5"/>
''', 26)),

    ('07-solar-sail', 'Solar sail', 'An explorer powered by starlight.', icon('Solar sail', '''
<path d="M300 743Q483 730 733 290" fill="none" stroke="#8E9BCE" stroke-width="4" opacity="0.35"/>
<path d="M350 554L574 271L696 550L471 732Z" fill="url(#rose)"/>
<path d="M574 271L471 732L510 526Z" fill="#FDE7D1"/>
<path d="M350 554L510 526L574 271Z" fill="#FFE0CA" opacity="0.55"/>
<path d="M510 526L696 550L471 732Z" fill="#7167A9" opacity="0.6"/>
<path d="M510 526L602 622" stroke="#FFEFDC" stroke-width="8" stroke-linecap="round"/>
<circle cx="605" cy="625" r="13" fill="#FFF2D9"/>
''' + spark(282, 351, 31), 27)),

    ('08-binary', 'Binary', 'Two worlds. One shared orbit.', icon('Binary', '''
<g transform="rotate(-34 512 512)">
<ellipse cx="512" cy="512" rx="301" ry="177" fill="none" stroke="#BDB5E8" stroke-width="5" opacity="0.4"/>
<circle cx="369" cy="512" r="129" fill="#7ADACD" opacity="0.2" filter="url(#glow)"/>
<circle cx="655" cy="512" r="99" fill="#FFAAAD" opacity="0.25" filter="url(#glow)"/>
<circle cx="369" cy="512" r="117" fill="url(#ice)"/>
<circle cx="655" cy="512" r="87" fill="url(#rose)"/>
<path d="M211 512A301 177 0 0 0 813 512" fill="none" stroke="#DBD5FF" stroke-width="11"/>
</g>
''' + spark(675, 273, 23), 28)),
]


def make():
    renderer = shutil.which('rsvg-convert')
    if renderer is None:
        raise SystemExit('rsvg-convert is required (brew install librsvg).')
    sheet = ['<rect width="1600" height="1140" fill="#10131E"/>',
             '<text x="70" y="80" fill="#F4F1EA" font-family="Helvetica, sans-serif" font-size="34" font-weight="bold">browsi / beyond the familiar</text>',
             '<text x="70" y="116" fill="#9DA6BD" font-family="Helvetica, sans-serif" font-size="16" letter-spacing="3">SPACE EXPLORATIONS — COLLECTION 02</text>']
    for i, (slug, title, _, svg) in enumerate(CONCEPTS):
        source = ROOT / f'{slug}.svg'
        source.write_text(svg, encoding='utf-8')
        subprocess.run([renderer, str(source), '-o', str(source.with_suffix('.png'))], check=True)
        x, y = 45 + (i % 4) * 385, 152 + (i // 4) * 450
        # Keep the main previews as vectors; thumbnails reference the PNG exports.
        inner = svg[svg.index('>') + 1:svg.rindex('</svg>')]
        # Each nested SVG has its own unique paint and clip IDs.
        for ident in ['title', 'tile', 'glow', 'sky', 'ice', 'rose', 'gold', 'planet', 'door']:
            inner = inner.replace(f'id="{ident}"', f'id="c{i}-{ident}"').replace(f'#{ident})', f'#c{i}-{ident})')
        sheet.append(f'<svg x="{x}" y="{y}" width="355" height="355" viewBox="0 0 1024 1024">{inner}</svg>')
        sheet.append(f'<text x="{x+177.5}" y="{y+387}" fill="#F4F1EA" text-anchor="middle" font-family="Helvetica, sans-serif" font-size="21">{i+1:02} / {escape(title)}</text>')
        for j, size in enumerate([16, 32, 64]):
            sheet.append(f'<image href="{slug}.png" x="{x+126+j*43}" y="{y+403+(32-size)/2}" width="{size}" height="{size}"/>')
    sheet.append('<text x="70" y="1100" fill="#9DA6BD" font-family="Helvetica, sans-serif" font-size="15">Eight directions · 1024 px originals · Small-size checks at 16 / 32 / 64 px · Concept artwork, not an installed app icon</text>')
    source = ROOT / 'sheet.svg'
    source.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1140">' + ''.join(sheet) + '</svg>', encoding='utf-8')
    subprocess.run([renderer, str(source), '-o', str(source.with_suffix('.png'))], check=True)
    print(f'Generated {len(CONCEPTS)} SVG/PNG concepts and comparison sheet in {ROOT}')


if __name__ == '__main__':
    make()
