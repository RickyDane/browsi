import random, math
SQ='M286 100 H738 A186 186 0 0 1 924 286 V738 A186 186 0 0 1 738 924 H286 A186 186 0 0 1 100 738 V286 A186 186 0 0 1 286 100 Z'
COMMON='''<filter id="g8" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="8"/></filter>
<filter id="g20" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="20"/></filter>
<filter id="g45" x="-80%" y="-80%" width="260%" height="260%"><feGaussianBlur stdDeviation="45"/></filter>
<filter id="sh" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="14" stdDeviation="16" flood-opacity="0.35"/></filter>'''

def stars(seed, n, avoid=None, bright=0.9):
    r = random.Random(seed); out = []
    for _ in range(n):
        x = r.uniform(110, 914); y = r.uniform(110, 914)
        if avoid and avoid(x, y): continue
        s = r.choice([1, 1.3, 1.6, 2, 2.6]); o = r.uniform(0.3, bright)
        out.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{s}" fill="#fff" opacity="{o:.2f}"/>')
    return ''.join(out)

def tile(bg, defs, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<defs><clipPath id="c"><path d="{SQ}"/></clipPath>{COMMON}{defs}</defs>'
            f'<g filter="url(#sh)"><path d="{SQ}" fill="{bg}"/></g><g clip-path="url(#c)">{body}</g>'
            f'<path d="{SQ}" fill="none" stroke="#fff" stroke-opacity="0.12" stroke-width="3"/></svg>')

C = {}

# 1 Black hole with lensed accretion disk
C['01 Black hole'] = tile('#030308', '''
<radialGradient id="disk" cx="0.5" cy="0.5" r="0.5"><stop offset="0.55" stop-color="#FFE7B0" stop-opacity="0"/><stop offset="0.62" stop-color="#FFF4D6"/><stop offset="0.72" stop-color="#FF9A3C"/><stop offset="0.86" stop-color="#C2321F" stop-opacity="0.6"/><stop offset="1" stop-color="#5A0F2E" stop-opacity="0"/></radialGradient>
<clipPath id="back"><rect x="0" y="0" width="1024" height="512"/></clipPath>''',
 stars(1, 90) +
 '<circle cx="512" cy="512" r="250" fill="url(#disk)" filter="url(#g20)" opacity="0.9"/>'
 '<g clip-path="url(#back)"><ellipse cx="512" cy="512" rx="380" ry="96" fill="none" stroke="#FFB459" stroke-width="40" opacity="0.8" filter="url(#g8)"/></g>'
 '<circle cx="512" cy="512" r="168" fill="#000"/>'
 '<circle cx="512" cy="512" r="172" fill="none" stroke="#FFE6B8" stroke-width="5" opacity="0.9"/>'
 '<path d="M132 512 A380 96 0 0 0 892 512" fill="none" stroke="#FFD9A0" stroke-width="44" filter="url(#g8)"/>'
 '<path d="M132 512 A380 96 0 0 0 892 512" fill="none" stroke="#FFF7E6" stroke-width="12"/>')

# 2 Astronaut helmet visor reflecting a nebula
C['02 Visor'] = tile('#0D0F1E', '''
<linearGradient id="vis" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFB25A"/><stop offset="0.35" stop-color="#E5487A"/><stop offset="0.7" stop-color="#4B2A9E"/><stop offset="1" stop-color="#0B1236"/></linearGradient>
<radialGradient id="helm" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="#FFFFFF"/><stop offset="0.6" stop-color="#D8DCE8"/><stop offset="1" stop-color="#8E95AC"/></radialGradient>
<clipPath id="vc"><rect x="290" y="330" width="444" height="330" rx="160"/></clipPath>''',
 stars(2, 60) +
 '<circle cx="512" cy="520" r="320" fill="url(#helm)"/>'
 '<rect x="270" y="310" width="484" height="370" rx="180" fill="#2A2E40"/>'
 '<rect x="290" y="330" width="444" height="330" rx="160" fill="url(#vis)"/>'
 '<g clip-path="url(#vc)">' + stars(22, 40, bright=1) +
 '<circle cx="610" cy="560" r="80" fill="#FFD27A" opacity="0.9"/><path d="M290 610 Q512 520 734 610 V700 H290Z" fill="#0B1236" opacity="0.8"/></g>'
 '<path d="M330 380 Q400 340 480 340" stroke="#fff" stroke-width="22" stroke-linecap="round" opacity="0.7" fill="none"/>'
 '<circle cx="512" cy="860" r="140" fill="#B9BFD0"/>')

# 3 Orbital sunrise over a planet's limb
C['03 Orbital sunrise'] = tile('#02030A', '''
<radialGradient id="pl" cx="0.5" cy="0" r="1"><stop offset="0" stop-color="#1D3B8F"/><stop offset="0.25" stop-color="#0A1640"/><stop offset="1" stop-color="#02040F"/></radialGradient>''',
 stars(3, 80, lambda x, y: y > 560) +
 '<circle cx="512" cy="1500" r="900" fill="#58C8FF" filter="url(#g45)" opacity="0.7"/>'
 '<circle cx="512" cy="1500" r="900" fill="url(#pl)"/>'
 '<circle cx="512" cy="1500" r="900" fill="none" stroke="#9EE7FF" stroke-width="8"/>'
 '<circle cx="512" cy="600" r="70" fill="#FFF3D6" filter="url(#g45)"/>'
 '<circle cx="512" cy="600" r="34" fill="#FFFFFF"/>'
 '<path d="M180 600 H844" stroke="#FFFFFF" stroke-width="4" opacity="0.8" filter="url(#g8)"/>'
 '<path d="M512 420 V780" stroke="#FFFFFF" stroke-width="3" opacity="0.5" filter="url(#g8)"/>')

# 4 Rocket launch arc into the night
C['04 Launch'] = tile('url(#sky4)', '''
<linearGradient id="sky4" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0B0830"/><stop offset="0.6" stop-color="#3B1670"/><stop offset="1" stop-color="#E2507E"/></linearGradient>
<linearGradient id="ex" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="#FF8A3C" stop-opacity="0"/><stop offset="0.7" stop-color="#FFC861"/><stop offset="1" stop-color="#FFFFFF"/></linearGradient>''',
 stars(4, 70, lambda x, y: y > 650) +
 '<path d="M150 930 Q300 620 690 340" stroke="#FFB25A" stroke-width="80" fill="none" opacity="0.5" filter="url(#g20)"/>'
 '<path d="M150 930 Q300 620 690 340" stroke="url(#ex)" stroke-width="26" fill="none" stroke-linecap="round"/>'
 '<g transform="translate(700 330) rotate(42)"><path d="M0 -110 C40 -70 46 -10 40 60 H-40 C-46 -10 -40 -70 0 -110Z" fill="#F4F5FA"/>'
 '<circle cx="0" cy="-30" r="20" fill="#4FC3FF" stroke="#2A2E40" stroke-width="8"/>'
 '<path d="M-40 20 L-80 80 L-40 60Z M40 20 L80 80 L40 60Z" fill="#FF4D6D"/><path d="M-22 60 H22 L0 110Z" fill="#FFB627"/></g>'
 '<path d="M100 924 Q512 760 924 924Z" fill="#12082A"/>')

# 5 Spiral galaxy
gal = []
r = random.Random(5)
for arm in range(2):
    for i in range(380):
        t = i / 380 * 3.6 * math.pi; rad = 20 + t * 28
        a = t + arm * math.pi + r.gauss(0, 0.22)
        x = 512 + math.cos(a) * rad; y = 512 + math.sin(a) * rad * 0.62
        sz = r.choice([1.2, 1.6, 2.2, 3]); col = r.choice(['#FFFFFF', '#CDE4FF', '#FFC6E8', '#B9A6FF'])
        gal.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{sz}" fill="{col}" opacity="{r.uniform(.4, 1):.2f}"/>')
C['05 Galaxy'] = tile('#05040E',
 '<radialGradient id="core"><stop offset="0" stop-color="#FFF6E0"/><stop offset="0.3" stop-color="#FFB8E2" stop-opacity="0.7"/><stop offset="1" stop-color="#6B3CFF" stop-opacity="0"/></radialGradient>',
 stars(5, 50) + '<g transform="rotate(-24 512 512)"><ellipse cx="512" cy="512" rx="360" ry="220" fill="#7A4CFF" opacity="0.35" filter="url(#g45)"/>'
 + ''.join(gal) + '</g><circle cx="512" cy="512" r="150" fill="url(#core)"/><circle cx="512" cy="512" r="30" fill="#fff" filter="url(#g8)"/>')

# 6 Golden crescent moon + star
C['06 Crescent'] = tile('url(#bg6)', '''
<linearGradient id="bg6" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#20195E"/><stop offset="1" stop-color="#07061A"/></linearGradient>
<linearGradient id="moon" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFF6D8"/><stop offset="1" stop-color="#F0C46A"/></linearGradient>
<mask id="cres"><rect width="1024" height="1024" fill="#fff"/><circle cx="600" cy="430" r="230" fill="#000"/></mask>''',
 stars(6, 60) +
 '<circle cx="480" cy="530" r="270" fill="#F7D98A" opacity="0.35" filter="url(#g45)" mask="url(#cres)"/>'
 '<circle cx="480" cy="530" r="270" fill="url(#moon)" mask="url(#cres)"/>'
 '<path d="M730 280 C740 340 756 356 816 366 C756 376 740 392 730 452 C720 392 704 376 644 366 C704 356 720 340 730 280Z" fill="#FFF6D8"/>')

# 7 Comet
C['07 Comet'] = tile('#060A1F', '''
<linearGradient id="tail" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#5BD6FF" stop-opacity="0"/><stop offset="0.7" stop-color="#9CE8FF" stop-opacity="0.6"/><stop offset="1" stop-color="#FFFFFF"/></linearGradient>''',
 stars(7, 90) +
 '<path d="M140 160 L690 650 L640 700 Z" fill="url(#tail)" filter="url(#g20)"/>'
 '<path d="M220 200 L700 660" stroke="url(#tail)" stroke-width="40" stroke-linecap="round" filter="url(#g8)"/>'
 '<path d="M300 210 L700 660" stroke="#C9F2FF" stroke-width="8" opacity="0.7" stroke-linecap="round"/>'
 '<circle cx="700" cy="660" r="110" fill="#7FE0FF" opacity="0.6" filter="url(#g45)"/>'
 '<circle cx="700" cy="660" r="54" fill="#FFFFFF"/>')

# 8 Wormhole tunnel
rings = ''.join(f'<ellipse cx="{512 + k * 14}" cy="{512 - k * 10}" rx="{360 - k * 34}" ry="{300 - k * 30}" fill="none" '
                f'stroke="hsl({250 + k * 12},90%,{55 + k * 3}%)" stroke-width="{14 - k}" opacity="{0.35 + k * 0.06:.2f}"/>' for k in range(10))
C['08 Wormhole'] = tile('#04020F',
 '<radialGradient id="eye"><stop offset="0" stop-color="#FFFFFF"/><stop offset="0.4" stop-color="#9AF2FF"/><stop offset="1" stop-color="#3B2BFF" stop-opacity="0"/></radialGradient>',
 stars(8, 60) + '<circle cx="640" cy="420" r="300" fill="#5A2BFF" opacity="0.5" filter="url(#g45)"/>' + rings
 + '<circle cx="652" cy="412" r="90" fill="url(#eye)"/>')

# 9 A constellation tracing a "b"
pts = [(380, 230), (380, 400), (380, 560), (380, 760), (520, 780), (650, 700), (680, 560), (590, 450), (450, 470)]
lines = ''.join(f'<line x1="{a[0]}" y1="{a[1]}" x2="{b[0]}" y2="{b[1]}" stroke="#9FC8FF" stroke-width="5" opacity="0.6"/>' for a, b in zip(pts, pts[1:]))
lines += '<line x1="450" y1="470" x2="380" y2="560" stroke="#9FC8FF" stroke-width="5" opacity="0.6"/>'
dots = ''.join(f'<circle cx="{x}" cy="{y}" r="{s * 3}" fill="#fff" filter="url(#g8)" opacity="0.8"/><circle cx="{x}" cy="{y}" r="{s}" fill="#fff"/>'
               for (x, y), s in zip(pts, [14, 9, 11, 16, 10, 12, 9, 11, 8]))
C['09 Constellation'] = tile('url(#bg9)',
 '<radialGradient id="bg9" cx="0.5" cy="0.4" r="0.8"><stop offset="0" stop-color="#18245E"/><stop offset="1" stop-color="#04061A"/></radialGradient>',
 stars(9, 110, bright=0.6) + lines + dots)

# 10 Earth from orbit under an aurora
C['10 Aurora'] = tile('#01020A', '''
<radialGradient id="earth" cx="0.4" cy="0.2" r="0.9"><stop offset="0" stop-color="#3FA9FF"/><stop offset="0.35" stop-color="#0E4FA8"/><stop offset="1" stop-color="#020A24"/></radialGradient>
<linearGradient id="aur" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="#3DFFB0" stop-opacity="0.9"/><stop offset="0.6" stop-color="#2BD6FF" stop-opacity="0.4"/><stop offset="1" stop-color="#A65CFF" stop-opacity="0"/></linearGradient>''',
 stars(10, 80, lambda x, y: y > 500) +
 '<path d="M140 560 C300 380 420 520 520 400 C620 280 760 420 900 300 V620 H140Z" fill="url(#aur)" filter="url(#g20)"/>'
 '<circle cx="512" cy="1240" r="720" fill="url(#earth)"/>'
 '<circle cx="512" cy="1240" r="720" fill="none" stroke="#8FE2FF" stroke-width="10" filter="url(#g8)"/>'
 '<path d="M300 640 q40 -20 80 0 t90 10 M560 600 q60 -30 120 -5" stroke="#E8F6FF" stroke-width="10" opacity="0.35" fill="none" stroke-linecap="round"/>')

names = []
for k, svg in C.items():
    fn = k.replace(' ', '-').lower()
    open(fn + '.svg', 'w').write(svg); names.append((k, fn))
cell = 340; n = 5; parts = []
for i, (label, f) in enumerate(names):
    x = (i % n) * cell; y = (i // n) * (cell + 50)
    parts.append(f'<image href="{f}.png" x="{x + 20}" y="{y + 16}" width="300" height="300"/>'
                 f'<text x="{x + cell / 2}" y="{y + 352}" font-family="Helvetica" font-size="22" text-anchor="middle" fill="#ddd">{label}</text>')
open('sheet.svg', 'w').write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{cell * n}" height="{2 * (cell + 50)}">'
                             f'<rect width="100%" height="100%" fill="#16171B"/>{"".join(parts)}</svg>')
print('\n'.join(f for _, f in names))
