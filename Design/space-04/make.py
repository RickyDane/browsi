"""Render collection 04. Python 3 + rsvg-convert; no downloaded assets."""

import base64
from html import escape
from pathlib import Path
import random
import shutil
import subprocess


ROOT = Path(__file__).resolve().parent
SHAPE = 'M286 100H738A186 186 0 0 1 924 286V738A186 186 0 0 1 738 924H286A186 186 0 0 1 100 738V286A186 186 0 0 1 286 100Z'


def gradient(name, colors):
    stops = ''.join(f'<stop offset="{i/(len(colors)-1):.3f}" stop-color="{c}"/>' for i, c in enumerate(colors))
    return f'<linearGradient id="{name}" x1="0" y1="0" x2="0.9" y2="1">{stops}</linearGradient>'


def star(x, y, r=25, color='#FFF3D6'):
    return (f'<path d="M{x} {y-r}Q{x+3} {y-3} {x+r} {y}'
            f'Q{x+3} {y+3} {x} {y+r}Q{x-3} {y+3} {x-r} {y}'
            f'Q{x-3} {y-3} {x} {y-r}Z" fill="{color}"/>')


CONCEPTS = []


def add(slug, title, description, background, body, defs=''):
    rng = random.Random(40 + len(CONCEPTS))
    stars = ''.join(f'<circle cx="{rng.randrange(160,865)}" cy="{rng.randrange(160,865)}" '
                    f'r="{rng.choice([1.3,1.8,2.3])}" fill="#E5E5FF" opacity="{rng.uniform(.15,.4):.2f}"/>' for _ in range(28))
    palette = (gradient('bg', background) + gradient('mint', ['#F2FFF2', '#94E5CD', '#4C9CB5'])
               + gradient('gold', ['#FFF3CC', '#EEC078', '#C78964'])
               + gradient('rose', ['#FFE2D1', '#F5A8C0', '#A882D2'])
               + gradient('blue', ['#E1E9FF', '#A2B7F1', '#6C78C1']))
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" role="img" aria-labelledby="title">'
           f'<title id="title">Browsi — {escape(title)}</title><defs>{palette}{defs}'
           f'<clipPath id="tile"><path d="{SHAPE}"/></clipPath>'
           '<filter id="glow" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="24"/></filter>'
           f'</defs><g clip-path="url(#tile)"><path d="{SHAPE}" fill="url(#bg)"/>{stars}{body}</g>'
           f'<path d="{SHAPE}" fill="none" stroke="#ECEDFF" stroke-opacity="0.15" stroke-width="2"/></svg>')
    CONCEPTS.append((slug, title, description, svg))


add('01-moon-moth', 'Moon moth', 'A nocturnal explorer with lunar wings.', ['#293044', '#11192A'], '''
<path d="M507 493C419 326 275 311 259 360C239 441 318 555 445 558C316 549 302 666 358 714C425 746 488 636 507 538Z" fill="url(#blue)"/>
<path d="M517 493C605 326 749 311 765 360C785 441 706 555 579 558C708 549 722 666 666 714C599 746 536 636 517 538Z" fill="url(#rose)"/>
<path d="M512 443V639M512 455Q487 404 465 397M512 455Q537 404 559 397" fill="none" stroke="#FFF0D6" stroke-width="14" stroke-linecap="round"/>
<path d="M351 396A68 68 0 1 0 425 488A60 60 0 0 1 351 396Z" fill="#263047"/>
<path d="M673 396A68 68 0 1 1 599 488A60 60 0 0 0 673 396Z" fill="#313049"/>
''' + star(512, 286, 32))

add('02-astrolabe', 'Astrolabe', 'A brass instrument for finding your next world.', ['#30303B', '#151724'], '''
<circle cx="512" cy="512" r="245" fill="none" stroke="url(#gold)" stroke-width="23"/>
<ellipse cx="512" cy="512" rx="112" ry="245" transform="rotate(30 512 512)" fill="none" stroke="url(#gold)" stroke-width="17"/>
<ellipse cx="512" cy="512" rx="245" ry="95" transform="rotate(-22 512 512)" fill="none" stroke="url(#gold)" stroke-width="17"/>
<path d="M512 231V268M512 756V793M231 512H268M756 512H793" stroke="#F4D4A0" stroke-width="9" stroke-linecap="round"/>
<circle cx="512" cy="512" r="53" fill="#232330"/>
''' + star(512, 512, 42) + '<circle cx="696" cy="351" r="25" fill="#B7E9DD"/>')

add('03-starglass', 'Starglass', 'Time measured in falling stars.', ['#302440', '#161329'], '''
<path d="M353 278H671C671 407 563 450 552 512C563 574 671 617 671 746H353C353 617 461 574 472 512C461 450 353 407 353 278Z" fill="url(#blue)"/>
<path d="M391 314H633C624 405 530 455 512 494C494 455 400 405 391 314Z" fill="#1D1B36"/>
<path d="M391 710C401 622 487 580 512 533C537 580 623 622 633 710Z" fill="#25203D"/>
<path d="M399 710Q512 565 625 710Z" fill="url(#rose)"/>
<path d="M337 278H687M337 746H687" stroke="#F2D8EB" stroke-width="27" stroke-linecap="round"/>
<path d="M512 522V598" stroke="#FFE9D6" stroke-width="6" stroke-dasharray="3 17" stroke-linecap="round"/>
''' + star(512, 389, 39) + star(457, 346, 14))

rays = ''.join(f'<path d="M512 229V279" transform="rotate({i*30} 512 512)" stroke="#EEC078" stroke-width="23" stroke-linecap="round"/>' for i in range(12))
add('04-helios', 'Helios', 'A golden sun with a cool crescent heart.', ['#38302C', '#191822'], rays + '''
<circle cx="512" cy="512" r="188" fill="url(#gold)"/>
<path d="M560 340A183 183 0 1 0 560 684A177 177 0 0 1 560 340Z" fill="#FFF0CB"/>
<circle cx="565" cy="495" r="91" fill="#30323D"/>
''' + star(565, 495, 40, '#B2E7DE'))

add('05-escape-velocity', 'Escape velocity', 'A rising vector leaving an orbital wake.', ['#1D3443', '#0D1D30'], '''
<ellipse cx="512" cy="620" rx="260" ry="110" fill="none" stroke="#7DADB7" stroke-width="5" opacity="0.4"/>
<path d="M274 666Q512 816 750 666" fill="none" stroke="url(#mint)" stroke-width="14" stroke-linecap="round"/>
<path d="M512 269L697 650L512 559L327 650Z" fill="url(#mint)"/>
<path d="M512 269V559L697 650Z" fill="#75B9C9"/>
<path d="M512 307V524" stroke="#E6FFF2" stroke-width="8" stroke-linecap="round" opacity="0.6"/>
<path d="M512 618V749" stroke="#DDFBEA" stroke-width="8" stroke-dasharray="21 24" stroke-linecap="round"/>
''' + star(755, 340, 23))

add('06-night-sail', 'Night sail', 'A crescent vessel sailing between the stars.', ['#232B47', '#10192E'], '''
<path d="M512 294V616H306Z" fill="url(#blue)"/>
<path d="M537 372L697 616H537Z" fill="url(#rose)"/>
<path d="M277 654Q512 773 747 654C685 849 359 849 277 654Z" fill="url(#gold)"/>
<path d="M512 294V655" stroke="#FFF0D9" stroke-width="9" stroke-linecap="round"/>
<path d="M325 783Q512 824 699 783" fill="none" stroke="#9CAFE0" stroke-width="4" opacity="0.35"/>
''' + star(688, 333, 43) + star(331, 323, 17))

add('07-pocket-cosmos', 'Pocket cosmos', 'An entire universe inside a little browser tab.', ['#323044', '#18192B'], '''
<path d="M300 708V366Q300 305 361 305H452L499 355H664Q725 355 725 416V708Q725 742 691 742H334Q300 742 300 708Z" fill="url(#blue)"/>
<path d="M334 702V409Q334 389 355 389H670Q691 389 691 409V702Z" fill="#1E2440"/>
<g clip-path="url(#window)">
<circle cx="574" cy="577" r="108" fill="url(#rose)"/>
<ellipse cx="574" cy="577" rx="164" ry="42" transform="rotate(-28 574 577)" fill="none" stroke="#F3D4AE" stroke-width="15"/>
</g>
''' + star(403, 468, 32) + star(626, 444, 14),
    '<clipPath id="window"><path d="M334 702V409Q334 389 355 389H670Q691 389 691 409V702Z"/></clipPath>')

add('08-nebula-knot', 'Nebula knot', 'Three luminous loops, woven into one discovery.', ['#34233D', '#17142B'], '''
<g fill="none" stroke-width="54">
<path d="M512 333C327 190 225 419 387 538C558 664 666 435 512 333Z" stroke="url(#rose)"/>
<path d="M512 333C327 190 225 419 387 538C558 664 666 435 512 333Z" stroke="url(#blue)" transform="rotate(120 512 512)"/>
<path d="M512 333C327 190 225 419 387 538C558 664 666 435 512 333Z" stroke="url(#mint)" transform="rotate(240 512 512)"/>
<path d="M512 333C462 294 417 282 381 290" stroke="url(#rose)"/>
</g>
''' + star(512, 512, 29))


def make():
    renderer = shutil.which('rsvg-convert')
    if not renderer:
        raise SystemExit('Requires rsvg-convert (brew install librsvg).')
    sheet = ['<rect width="1600" height="1140" fill="#10131E"/>',
             '<text x="70" y="78" fill="#F4F1E9" font-family="Helvetica, sans-serif" font-size="36" font-weight="bold">browsi / curious by nature</text>',
             '<text x="70" y="117" fill="#A3ACC0" font-family="Helvetica, sans-serif" font-size="16" letter-spacing="3">SPACE EXPLORATIONS — COLLECTION 04</text>']
    for i, (slug, title, _, svg) in enumerate(CONCEPTS):
        path = ROOT / f'{slug}.svg'
        path.write_text(svg, encoding='utf-8')
        png = path.with_suffix('.png')
        subprocess.run([renderer, str(path), '-o', str(png)], check=True)
        # Embedded images keep the SVG comparison sheet portable on its own.
        data = base64.b64encode(png.read_bytes()).decode('ascii')
        x, y = 45 + i % 4 * 385, 155 + i // 4 * 450
        sheet.append(f'<image href="data:image/png;base64,{data}" x="{x}" y="{y}" width="355" height="355"/>')
        sheet.append(f'<text x="{x+177.5}" y="{y+386}" text-anchor="middle" fill="#F4F1E9" font-family="Helvetica, sans-serif" font-size="21">{i+1:02} / {escape(title)}</text>')
        for j, size in enumerate([16, 32, 64]):
            sheet.append(f'<image href="data:image/png;base64,{data}" x="{x+126+j*43}" y="{y+402+(32-size)/2}" width="{size}" height="{size}"/>')
    sheet.append('<text x="70" y="1100" fill="#A3ACC0" font-family="Helvetica, sans-serif" font-size="15">Eight new directions · 1024 px originals · Small-size checks at 16 / 32 / 64 px · Concept artwork only</text>')
    path = ROOT / 'sheet.svg'
    path.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1140">' + ''.join(sheet) + '</svg>', encoding='utf-8')
    subprocess.run([renderer, str(path), '-o', str(path.with_suffix('.png'))], check=True)
    print('Generated eight SVG/PNG logos and a self-contained comparison sheet.')


if __name__ == '__main__':
    make()
