"""Render Browsi's third space-logo collection with rsvg-convert."""

from html import escape
from pathlib import Path
import math
import random
import shutil
import subprocess


ROOT = Path(__file__).resolve().parent
SHAPE = 'M286 100H738A186 186 0 0 1 924 286V738A186 186 0 0 1 738 924H286A186 186 0 0 1 100 738V286A186 186 0 0 1 286 100Z'


def gradient(name, colors):
    stops = ''.join(f'<stop offset="{i/(len(colors)-1):.3f}" stop-color="{color}"/>'
                    for i, color in enumerate(colors))
    return f'<linearGradient id="{name}" x1="0" y1="0" x2="0.85" y2="1">{stops}</linearGradient>'


def star(x, y, r=24, color='#FFF4DD'):
    return (f'<path d="M{x} {y-r}Q{x+3} {y-3} {x+r} {y}'
            f'Q{x+3} {y+3} {x} {y+r}Q{x-3} {y+3} {x-r} {y}'
            f'Q{x-3} {y-3} {x} {y-r}Z" fill="{color}"/>')


def tile(title, colors, body, seed, defs=''):
    rng = random.Random(seed)
    dust = ''.join(f'<circle cx="{rng.randint(170, 854)}" cy="{rng.randint(170, 854)}" '
                   f'r="{rng.choice([1.2, 1.8, 2.4])}" fill="#E1E6FF" opacity="{rng.uniform(.2,.5):.2f}"/>'
                   for _ in range(25))
    common = (gradient('bg', colors) + gradient('mint', ['#EEFFF4', '#8FE8CC', '#4A9CCA'])
              + gradient('violet', ['#E9DDFF', '#B397F0', '#615DCC'])
              + gradient('fire', ['#FFF1C7', '#FFB48A', '#F06B84'])
              + gradient('pink', ['#FFE1EC', '#E99DDE', '#8A79D3']))
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            f'viewBox="0 0 1024 1024" role="img" aria-labelledby="title">'
            f'<title id="title">Browsi — {escape(title)}</title><defs>{common}{defs}'
            f'<clipPath id="clip"><path d="{SHAPE}"/></clipPath>'
            '<filter id="blur" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="26"/></filter>'
            f'</defs><g clip-path="url(#clip)"><path d="{SHAPE}" fill="url(#bg)"/>{dust}{body}</g>'
            f'<path d="{SHAPE}" fill="none" stroke="#D5DFFF" stroke-opacity="0.16" stroke-width="2"/></svg>')


CONCEPTS = []


def add(slug, title, description, colors, body, defs=''):
    CONCEPTS.append((slug, title, description, tile(title, colors, body, len(CONCEPTS)+31, defs)))


add('01-gravity-b', 'Gravity b', 'A sculpted monogram, bent by a passing world.', ['#192F39', '#09161F'], '''
<circle cx="535" cy="536" r="264" fill="none" stroke="#9AE4CB" stroke-width="3" opacity="0.18"/>
<path d="M365 284V570A156 156 0 1 0 521 414A156 156 0 0 0 365 570" fill="none" stroke="url(#mint)" stroke-width="87" stroke-linecap="round"/>
<path d="M546 352Q707 351 737 498" fill="none" stroke="#C2FFE8" stroke-width="7" stroke-linecap="round" opacity="0.5"/>
<circle cx="680" cy="364" r="62" fill="#0D202B"/>
<circle cx="680" cy="364" r="46" fill="url(#fire)"/>
''' + star(285, 720, 20))

petals = ''.join(
    f'<path d="M512 501C435 435 444 325 512 222C580 325 589 435 512 501Z" '
    f'fill="url(#{"fire" if i % 2 else "pink"})" transform="rotate({i*60} 512 512)"/>'
    for i in range(6)
)
add('02-nova-bloom', 'Nova bloom', 'A star unfolding into six luminous petals.', ['#342039', '#150E25'], '''
<circle cx="512" cy="512" r="221" fill="#D483C7" opacity="0.2" filter="url(#blur)"/>
''' + petals + '<circle cx="512" cy="512" r="38" fill="#FFF0D6"/>' + star(767, 274, 20))

hexagon = ' '.join(f'{512+263*math.cos(math.radians(i*60-30)):.2f},{512+263*math.sin(math.radians(i*60-30)):.2f}' for i in range(6))
add('03-deepfield', 'Deepfield', 'A telescope aperture with a universe inside.', ['#1D284A', '#0A1025'], f'''
<polygon points="{hexagon}" fill="url(#violet)"/>
<polygon points="{hexagon}" transform="translate(512 512) scale(.77) translate(-512 -512)" fill="#10172F"/>
<g clip-path="url(#lens)">
<path d="M277 646Q443 349 748 388" fill="none" stroke="#967BE0" stroke-width="73" opacity="0.45" filter="url(#blur)"/>
<path d="M307 644Q465 427 706 392" fill="none" stroke="url(#pink)" stroke-width="27"/>
<path d="M365 660Q518 412 685 390" fill="none" stroke="#C9EBFF" stroke-width="6"/>
<circle cx="543" cy="480" r="42" fill="#E8D9FF" opacity="0.7" filter="url(#blur)"/>
</g>
''' + star(543, 480, 42) + star(390, 443, 14, '#ABC8FF'),
    '<clipPath id="lens"><circle cx="512" cy="512" r="192"/></clipPath>')

add('04-star-trail', 'Star trail', 'A comet carving a path around a browser window.', ['#18313D', '#0A1529'], '''
<rect x="302" y="305" width="418" height="416" rx="100" fill="#244554" stroke="#6D99A9" stroke-width="5"/>
<path d="M302 411H720" stroke="#6D99A9" stroke-width="5"/>
<circle cx="358" cy="360" r="9" fill="#B9D8DC"/><circle cx="391" cy="360" r="9" fill="#B9D8DC" opacity="0.5"/>
<path d="M265 692C193 495 467 217 745 290" fill="none" stroke="#8AE1CB" stroke-width="13" stroke-linecap="round" opacity="0.25"/>
<path d="M263 690C265 810 632 766 751 443" fill="none" stroke="url(#mint)" stroke-width="43" stroke-linecap="round"/>
<path d="M344 732Q574 734 718 509" fill="none" stroke="#E8FFF4" stroke-width="7" stroke-linecap="round"/>
''' + star(751, 443, 65, '#E6FFF0'))

add('05-red-dwarf', 'Red dwarf', 'A warm stellar heart and its solitary companion.', ['#3D242C', '#1A1221'], '''
<circle cx="512" cy="512" r="232" fill="#F99778" opacity="0.24" filter="url(#blur)"/>
<circle cx="512" cy="512" r="200" fill="url(#fire)"/>
<circle cx="512" cy="512" r="258" fill="none" stroke="#D99788" stroke-width="3" opacity="0.3"/>
<circle cx="512" cy="512" r="303" fill="none" stroke="#D99788" stroke-width="3" opacity="0.16"/>
<path d="M359 434A167 167 0 0 1 544 352" fill="none" stroke="#FFF2D7" stroke-width="10" stroke-linecap="round" opacity="0.65"/>
<circle cx="737" cy="638" r="46" fill="#23172B"/>
<path d="M714 601A44 44 0 0 1 774 651" fill="none" stroke="#F6D0D0" stroke-width="6" stroke-linecap="round"/>
''')

add('06-lagrange', 'Lagrange', 'Two sweeping trajectories meeting at a single star.', ['#282545', '#111327'], '''
<g transform="rotate(-29 512 512)">
<ellipse cx="512" cy="512" rx="282" ry="126" fill="none" stroke="url(#violet)" stroke-width="32"/>
<ellipse cx="512" cy="512" rx="126" ry="282" fill="none" stroke="url(#mint)" stroke-width="32"/>
<path d="M512 230A126 282 0 0 0 386 512" fill="none" stroke="#E4FFF2" stroke-width="8" stroke-linecap="round"/>
</g>
<circle cx="512" cy="512" r="64" fill="#13152B"/>
''' + star(512, 512, 53) + '<circle cx="759" cy="375" r="22" fill="#FFCEA2"/>')

add('07-ion-ribbon', 'Ion ribbon', 'A continuous ribbon accelerating into the unknown.', ['#152E48', '#10152E'], '''
<path d="M355 712C166 594 423 266 629 343C836 420 597 793 420 655C281 548 549 420 662 291" fill="none" stroke="#7EC9F2" stroke-width="73" opacity="0.17" filter="url(#blur)"/>
<path d="M355 712C166 594 423 266 629 343C836 420 597 793 420 655C281 548 549 420 662 291" fill="none" stroke="url(#ribbon)" stroke-width="55" stroke-linecap="round"/>
<path d="M355 712C207 613 369 360 559 344" fill="none" stroke="#E9FBFF" stroke-width="8" stroke-linecap="round" opacity="0.65"/>
''' + star(662, 291, 39, '#DBFFF2'),
    gradient('ribbon', ['#C2D9FF', '#7DABEE', '#9FEFE3']))

add('08-cosmic-eye', 'Cosmic eye', 'Curiosity, focused through an interstellar lens.', ['#242344', '#0C1429'], '''
<path d="M231 512Q512 204 793 512Q512 820 231 512Z" fill="url(#violet)"/>
<path d="M269 512Q512 255 755 512Q512 769 269 512Z" fill="#141A35"/>
<circle cx="512" cy="512" r="157" fill="url(#iris)"/>
<circle cx="512" cy="512" r="74" fill="#12182D"/>
<circle cx="512" cy="512" r="103" fill="none" stroke="#EAFFF0" stroke-width="4" opacity="0.42"/>
<path d="M424 403A140 140 0 0 1 613 414" fill="none" stroke="#DAFFF0" stroke-width="11" stroke-linecap="round" opacity="0.6"/>
''' + star(542, 473, 27, '#FFF4DD') + star(757, 297, 20),
    gradient('iris', ['#D7FFF2', '#70C9BF', '#566CC4']))


def make():
    renderer = shutil.which('rsvg-convert')
    if not renderer:
        raise SystemExit('Requires rsvg-convert (brew install librsvg).')
    fragments = ['<rect width="1600" height="1140" fill="#10131E"/>',
                 '<text x="70" y="78" fill="#F4F2ED" font-family="Helvetica, sans-serif" font-size="36" font-weight="bold">browsi / further out</text>',
                 '<text x="70" y="117" fill="#A3ACC0" font-family="Helvetica, sans-serif" font-size="16" letter-spacing="3">SPACE EXPLORATIONS — COLLECTION 03</text>']
    for i, (slug, title, _, svg) in enumerate(CONCEPTS):
        source = ROOT / f'{slug}.svg'
        source.write_text(svg, encoding='utf-8')
        subprocess.run([renderer, str(source), '-o', str(source.with_suffix('.png'))], check=True)
        inner = svg[svg.index('>')+1:svg.rindex('</svg>')]
        for ident in ['title', 'bg', 'mint', 'violet', 'fire', 'pink', 'clip', 'blur', 'lens', 'ribbon', 'iris']:
            inner = inner.replace(f'id="{ident}"', f'id="c{i}-{ident}"').replace(f'#{ident})', f'#c{i}-{ident})')
        x, y = 45 + i % 4 * 385, 155 + i // 4 * 450
        fragments.append(f'<svg x="{x}" y="{y}" width="355" height="355" viewBox="0 0 1024 1024">{inner}</svg>')
        fragments.append(f'<text x="{x+177.5}" y="{y+386}" fill="#F4F2ED" text-anchor="middle" font-family="Helvetica, sans-serif" font-size="21">{i+1:02} / {escape(title)}</text>')
        for j, size in enumerate([16, 32, 64]):
            fragments.append(f'<image href="{slug}.png" x="{x+126+j*43}" y="{y+402+(32-size)/2}" width="{size}" height="{size}"/>')
    fragments.append('<text x="70" y="1100" fill="#A3ACC0" font-family="Helvetica, sans-serif" font-size="15">Eight new directions · 1024 px originals · Small-size checks at 16 / 32 / 64 px · Concept artwork only</text>')
    sheet = ROOT / 'sheet.svg'
    sheet.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1140">' + ''.join(fragments) + '</svg>', encoding='utf-8')
    subprocess.run([renderer, str(sheet), '-o', str(sheet.with_suffix('.png'))], check=True)
    print(f'Generated {len(CONCEPTS)} SVG/PNG concepts and the comparison sheet.')


if __name__ == '__main__':
    make()
