import random, math
SQ = 'M286 100 H738 A186 186 0 0 1 924 286 V738 A186 186 0 0 1 738 924 H286 A186 186 0 0 1 100 738 V286 A186 186 0 0 1 286 100 Z'
FILTERS = '''<filter id="b4" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="4"/></filter>
<filter id="b12" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="12"/></filter>
<filter id="b30" x="-80%" y="-80%" width="260%" height="260%"><feGaussianBlur stdDeviation="30"/></filter>
<filter id="b60" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="60"/></filter>
<filter id="sh" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="14" stdDeviation="16" flood-opacity="0.4"/></filter>'''


def tile(bg, defs, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<defs><clipPath id="c"><path d="{SQ}"/></clipPath>{FILTERS}{defs}</defs>'
            f'<g filter="url(#sh)"><path d="{SQ}" fill="{bg}"/></g><g clip-path="url(#c)">{body}</g>'
            f'<path d="{SQ}" fill="none" stroke="#fff" stroke-opacity="0.12" stroke-width="3"/></svg>')


def bg_stars(seed, n, bright=0.8):
    r = random.Random(seed)
    return ''.join(f'<circle cx="{r.uniform(110, 914):.0f}" cy="{r.uniform(110, 914):.0f}" r="{r.choice([0.9, 1.2, 1.6, 2.2])}" '
                   f'fill="#fff" opacity="{r.uniform(0.25, bright):.2f}"/>' for _ in range(n))


def spiral(arm_offset, turns=1.6, r0=40, r1=360, tilt=0.62, n=90):
    """Points along a logarithmic-ish spiral arm (centered at 512,512, flattened by `tilt`)."""
    pts = []
    for i in range(n):
        t = i / (n - 1)
        a = arm_offset + t * turns * 2 * math.pi
        rad = r0 + (r1 - r0) * t ** 0.9
        pts.append((512 + math.cos(a) * rad, 512 + math.sin(a) * rad * tilt, t))
    return pts


def tapered_arm(pts, w0, w1, color, opacity=1.0, filt=None):
    """Arm drawn as overlapping segments whose width tapers from w0 (core) to w1 (tip)."""
    segs = []
    for (x0, y0, t), (x1, y1, _) in zip(pts, pts[1:]):
        w = w0 + (w1 - w0) * t
        o = opacity * (1 - 0.75 * t)
        segs.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}" stroke="{color}" '
                    f'stroke-width="{w:.1f}" stroke-linecap="round" opacity="{o:.2f}"/>')
    f = f' filter="url(#{filt})"' if filt else ''
    return f'<g{f}>' + ''.join(segs) + '</g>'


def arm_stars(pts, seed, count, spread, colors):
    r = random.Random(seed); out = []
    for _ in range(count):
        x, y, t = pts[int(r.random() ** 0.8 * (len(pts) - 1))]
        s = spread * (0.4 + t)
        x += r.gauss(0, s); y += r.gauss(0, s * 0.7)
        rad = r.choice([1.1, 1.5, 2, 2.6, 3.4]) * (1.2 - 0.5 * t)
        out.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{rad:.1f}" fill="{r.choice(colors)}" opacity="{r.uniform(0.5, 1):.2f}"/>')
    return ''.join(out)


def core(r_glow, r_mid, r_hot, c_glow, c_mid):
    return (f'<circle cx="512" cy="512" r="{r_glow}" fill="{c_glow}" opacity="0.55" filter="url(#b60)"/>'
            f'<circle cx="512" cy="512" r="{r_mid}" fill="{c_mid}" opacity="0.9" filter="url(#b30)"/>'
            f'<circle cx="512" cy="512" r="{r_hot}" fill="#FFFFFF" filter="url(#b12)"/>'
            f'<circle cx="512" cy="512" r="{r_hot * 0.45:.0f}" fill="#FFFFFF"/>')


def galaxy(arms, turns, r1, tilt, glow_col, arm_col, hi_col, star_cols, seed, rotate=-24, w=(70, 16), stars_per_arm=260):
    body = f'<g transform="rotate({rotate} 512 512)">'
    body += f'<ellipse cx="512" cy="512" rx="{r1 * 1.05:.0f}" ry="{r1 * tilt * 1.1:.0f}" fill="{glow_col}" opacity="0.35" filter="url(#b60)"/>'
    for k in range(arms):
        pts = spiral(k * 2 * math.pi / arms, turns=turns, r1=r1, tilt=tilt)
        body += tapered_arm(pts, w[0] * 1.8, w[1] * 2, arm_col, 0.55, 'b30')   # soft halo
        body += tapered_arm(pts, w[0], w[1], arm_col, 0.85, 'b12')            # body
        body += tapered_arm(pts, w[0] * 0.28, 2, hi_col, 0.9, 'b4')           # bright spine
        body += arm_stars(pts, seed + k, stars_per_arm, 22, star_cols)
    return body + '</g>'


V = {}

# R1 — Bigger & bolder: fills the tile, smooth glowing arms, violet/pink like the original.
V['R1 Bold violet'] = tile('#06041A', '''
<radialGradient id="bg1" cx="0.5" cy="0.5" r="0.7"><stop offset="0" stop-color="#1B0F4A"/><stop offset="1" stop-color="#05030F"/></radialGradient>''',
    '<rect x="0" y="0" width="1024" height="1024" fill="url(#bg1)"/>' + bg_stars(11, 70) +
    galaxy(2, 1.45, 390, 0.62, '#7A4CFF', '#9C6BFF', '#FFD0F2', ['#FFFFFF', '#E6D8FF', '#FFC6E8', '#BFD6FF'], 100) +
    core(230, 120, 46, '#B57CFF', '#FFC2EA'))

# R2 — Face-on, warm core + cool blue arms (more realistic, high contrast between core and arms).
V['R2 Gold and blue'] = tile('#030616', '''
<radialGradient id="bg2" cx="0.5" cy="0.5" r="0.7"><stop offset="0" stop-color="#0C1A44"/><stop offset="1" stop-color="#02040E"/></radialGradient>''',
    '<rect width="1024" height="1024" fill="url(#bg2)"/>' + bg_stars(12, 70) +
    galaxy(2, 1.25, 380, 0.92, '#2F6BFF', '#4D8BFF', '#CFE6FF', ['#FFFFFF', '#CFE4FF', '#9EC7FF', '#FFE2B0'], 200, rotate=10) +
    core(220, 130, 52, '#FFB347', '#FFD98A'))

# R3 — Cinematic tilt with a dark dust lane through the disk (sense of depth).
V['R3 Dust lane'] = tile('#04030C', '''
<radialGradient id="bg3" cx="0.5" cy="0.5" r="0.7"><stop offset="0" stop-color="#1A0C33"/><stop offset="1" stop-color="#030208"/></radialGradient>
<linearGradient id="lane" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#05030C" stop-opacity="0"/><stop offset="0.3" stop-color="#05030C" stop-opacity="0.85"/><stop offset="0.7" stop-color="#05030C" stop-opacity="0.85"/><stop offset="1" stop-color="#05030C" stop-opacity="0"/></linearGradient>''',
    '<rect width="1024" height="1024" fill="url(#bg3)"/>' + bg_stars(13, 80) +
    galaxy(2, 1.5, 420, 0.38, '#FF5FA8', '#FF8AC4', '#FFE4F2', ['#FFFFFF', '#FFD0E8', '#FFE7C2', '#D8C6FF'], 300, rotate=-20, w=(60, 12)) +
    core(200, 110, 48, '#FF9AD0', '#FFE0B8') +
    '<ellipse cx="512" cy="520" rx="400" ry="22" transform="rotate(-20 512 512)" fill="url(#lane)" filter="url(#b12)"/>')

# R4 — Icon-first: three smooth tapered arms, no loose particles, reads at 16 px.
V['R4 Minimal swirl'] = tile('url(#bg4)', '''
<linearGradient id="bg4" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2A1470"/><stop offset="1" stop-color="#090522"/></linearGradient>''',
    bg_stars(14, 45, 0.7) +
    galaxy(3, 1.05, 350, 1.0, '#8A5CFF', '#A07BFF', '#FFFFFF', ['#FFFFFF'], 400, rotate=0, w=(96, 18), stars_per_arm=0) +
    core(200, 110, 60, '#C9A6FF', '#F2E6FF'))

# R5 — Nebula colour: teal→magenta arms, four-point sparkle at the core (ties to the AI sparkle).
V['R5 Nebula sparkle'] = tile('#020A12', '''
<radialGradient id="bg5" cx="0.3" cy="0.25" r="0.9"><stop offset="0" stop-color="#0B3A4A"/><stop offset="0.6" stop-color="#140A30"/><stop offset="1" stop-color="#020208"/></radialGradient>''',
    '<rect width="1024" height="1024" fill="url(#bg5)"/>' + bg_stars(15, 80) +
    galaxy(2, 1.4, 390, 0.6, '#1FD1C8', '#2FE0D2', '#E8FFFC', ['#FFFFFF', '#BFFFF6', '#FFC0F0', '#9FE8FF'], 500, rotate=-30) +
    '<g transform="rotate(150 512 512)">' + tapered_arm(spiral(0, 1.4, r1=390, tilt=0.6), 60, 14, '#FF4FD8', 0.55, 'b30') + '</g>' +
    core(220, 120, 40, '#FF6FE0', '#FFE3F8') +
    '<path d="M512 400 C520 486 538 504 624 512 C538 520 520 538 512 624 C504 538 486 520 400 512 C486 504 504 486 512 400Z" fill="#FFFFFF"/>')

names = []
for k, svg in V.items():
    fn = k.split(' ')[0].lower()
    open(fn + '.svg', 'w').write(svg); names.append((k, fn))

# Sheet: each revision large + at 64 px and 32 px to judge small sizes.
cell = 380; parts = []
for i, (label, f) in enumerate(names):
    x = i * cell
    parts.append(f'<image href="{f}.png" x="{x + 20}" y="20" width="340" height="340"/>'
                 f'<image href="{f}.png" x="{x + 110}" y="380" width="64" height="64"/>'
                 f'<image href="{f}.png" x="{x + 200}" y="396" width="32" height="32"/>'
                 f'<text x="{x + cell / 2}" y="490" font-family="Helvetica" font-size="22" text-anchor="middle" fill="#ddd">{label}</text>')
open('sheet.svg', 'w').write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{cell * len(names)}" height="520">'
                             f'<rect width="100%" height="100%" fill="#16171B"/>{"".join(parts)}</svg>')
print('\n'.join(f for _, f in names))
