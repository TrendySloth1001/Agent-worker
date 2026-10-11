"""Compose Open Peeps (CC0) parts + hand-drawn props into app illustrations.

Usage: python3 -I compose.py <peeps_dl_dir> <out_dir>
Ink = #000000, paper = #FFFFFF, accent = #D71921 (swapped at runtime).
"""
import glob
import os
import re
import sys
import xml.etree.ElementTree as ET

NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)
INK, PAPER, RED = '#000000', '#FFFFFF', '#D71921'

DL, OUT = sys.argv[1], sys.argv[2]


def load(name):
    path = glob.glob(os.path.join(DL, '*_' + name + '.svg'))[0]
    return ET.parse(path).getroot()


def strip(el):
    for child in list(el):
        tag = child.tag.split('}')[-1]
        if tag in ('title', 'desc'):
            el.remove(child)
        else:
            strip(child)
    el.attrib.pop('id', None)
    return el


def to_str(el):
    s = ET.tostring(strip(el), encoding='unicode')
    return s.replace(' xmlns="%s"' % NS, '').replace('ns0:', '')


def bust_part(peep, part_prefix):
    """Return the component group (body/, head/, face/ ...) of a bust peep."""
    root = load(peep)
    for g in root.iter('{%s}g' % NS):
        if g.get('id', '').startswith(part_prefix):
            return to_str(g)
    raise KeyError(part_prefix)


def bust(body, head, face, extra=()):
    parts = [bust_part(body, 'body/'), bust_part(head, 'head/'),
             bust_part(face, 'face/')]
    parts += [bust_part(p, pre) for p, pre in extra]
    return '<g>%s</g>' % ''.join(parts)


def whole(peep):
    root = load(peep)
    return ''.join(to_str(c) for c in list(root)
                   if c.tag.split('}')[-1] not in ('title', 'desc'))


# --- hand-drawn props ------------------------------------------------------
def stroke(d, w=4, color=INK, fill='none', extra=''):
    return ('<path d="%s" fill="%s" stroke="%s" stroke-width="%s" '
            'stroke-linecap="round" stroke-linejoin="round"%s/>'
            % (d, fill, color, w, extra))


def spark(cx, cy, r, color=RED):
    """Four-point hand-drawn spark (filled)."""
    k = r * 0.22
    d = ('M{x},{t} C{a},{b} {c},{e} {rr},{y} C{c},{f} {a},{g} {x},{bo} '
         'C{h},{g} {i},{f} {l},{y} C{i},{e} {h},{b} {x},{t}Z').format(
        x=cx, y=cy, t=cy - r, bo=cy + r, l=cx - r, rr=cx + r,
        a=cx + k * 0.6, b=cy - k * 1.2, c=cx + k * 1.2, e=cy - k * 0.6,
        f=cy + k * 0.6, g=cy + k * 1.2, h=cx - k * 0.6, i=cx - k * 1.2)
    return '<path d="%s" fill="%s"/>' % (d, color)


def ticks(cx, cy, r1, r2, angles, w=3.5, color=INK):
    import math
    out = []
    for a in angles:
        rad = math.radians(a)
        x1, y1 = cx + r1 * math.cos(rad), cy - r1 * math.sin(rad)
        x2, y2 = cx + r2 * math.cos(rad), cy - r2 * math.sin(rad)
        out.append(stroke('M%.1f,%.1f L%.1f,%.1f' % (x1, y1, x2, y2), w, color))
    return ''.join(out)


def svg(viewbox, body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="%s">%s</svg>'
            % (viewbox, body))


# --- optimisation ------------------------------------------------------------
NUM = re.compile(r'-?\d+\.\d+')


def optimise(s):
    s = re.sub(r'<!--.*?-->', '', s, flags=re.S)
    s = re.sub(r'\s+', ' ', s)
    s = re.sub(r'>\s+<', '><', s)

    def rnd(m):
        v = round(float(m.group(0)), 1)
        t = ('%.1f' % v).rstrip('0').rstrip('.')
        return '0' if t in ('-0', '') else t

    s = re.sub(r'(d|transform|viewBox)="([^"]*)"',
               lambda m: '%s="%s"' % (m.group(1), NUM.sub(rnd, m.group(2))), s)
    # Path syntax compaction: drop spaces after commands / before negatives.
    s = re.sub(r'd="([^"]*)"', lambda m: 'd="%s"' % re.sub(
        r'\s*([MLCSQTAZHVmlcsqtazhv])\s*', r'\1',
        m.group(1)).replace(' -', '-').replace(',-', '-'), s)
    s = s.replace(' transform="translate(0, 0)"', '')
    s = s.replace('fill="#000"', 'fill="%s"' % INK)
    s = re.sub(r'<g[^>]*/>', '', s)
    for _ in range(3):
        s = re.sub(r'<g[^>/]*></g>', '', s)
    return s.strip()


def write(name, content):
    os.makedirs(OUT, exist_ok=True)
    data = optimise(content)
    with open(os.path.join(OUT, name + '.svg'), 'w') as f:
        f.write(data)
    print('%-16s %6d bytes' % (name, len(data)))


# --- scenes -----------------------------------------------------------------
def login():
    person = bust('peep-46', 'peep-46', 'peep-13')
    props = (
        '<ellipse cx="206" cy="214" rx="14" ry="13" fill="%s"/>' % PAPER
        + spark(205, 214, 11)
        + spark(222, 150, 9, INK)
        + ticks(222, 150, 15, 23, (30, 150, 90), 3.5)
    )
    return svg('20 26 240 284', person + props)


def hello():
    person = whole('peep-standing-16')
    bubble = stroke(
        'M216,30 C250,22 304,24 318,44 C330,62 322,92 296,98 '
        'C276,103 252,101 236,99 L216,116 L220,96 '
        'C200,92 192,74 194,58 C196,42 204,34 216,30Z',
        5, INK, PAPER)
    dots = ('<circle cx="232" cy="64" r="6.5" fill="%s"/>'
            '<circle cx="258" cy="64" r="6.5" fill="%s"/>'
            '<circle cx="284" cy="64" r="6.5" fill="%s"/>' % (INK, INK, RED))
    return svg('-6 14 340 652', person + bubble + dots)


def github():
    person = bust('peep-44', 'peep-91', 'peep-13')
    # Left piece: knob on top and a knob reaching right.
    left = stroke(
        'M22,142 L36,142 A9,9 0 1,1 49,142 L64,143 '
        'C64,150 65,155 64,160 L67,160 A10,10 0 1,1 67,172 L64,172 '
        'C65,178 64,186 64,192 C52,193 34,193 22,192 '
        'C21,176 21,158 22,142Z', 4.5, INK, PAPER)
    # Right piece: knob on top and a socket on its left side.
    right = stroke(
        'M196,152 L210,152 A9,9 0 1,1 223,152 L238,153 '
        'C239,168 239,186 238,202 C226,203 208,203 196,202 '
        'C196,196 195,190 196,183 L199,183 A10,10 0 1,0 199,171 L196,171 '
        'C195,165 196,158 196,152Z', 4.5, INK, PAPER)
    props = left + right + spark(232, 110, 11) + ticks(
        232, 110, 16, 23, (20, 90, 160), 3.5)
    return svg('6 40 252 270', person + props)


def empty_knowledge():
    person = whole('peep-sitting-9')
    box = (
        # back flaps
        stroke('M352,360 L338,326 L392,322 L410,352', 4.5, INK, PAPER)
        + stroke('M410,352 L446,330 L470,356', 4.5, INK, PAPER)
        # box body
        + stroke('M340,360 C370,357 420,356 452,358 C453,390 452,420 451,452 '
                 'C415,455 375,455 342,453 C341,420 340,390 340,360Z',
                 5, INK, PAPER)
        # inner rim (open, empty)
        + stroke('M340,360 L362,380 C390,381 420,381 452,358', 4)
        # front flaps flopped open
        + stroke('M340,360 L314,392 L332,404', 4.5, INK, PAPER)
        + stroke('M452,358 L480,388 L462,398', 4.5, INK, PAPER)
    )
    props = box + spark(400, 296, 13) + ticks(400, 296, 19, 27, (20, 160), 3.5)
    return svg('0 0 490 470', person + props)


def empty_history():
    person = whole('peep-sitting-12')
    clock = (
        stroke('M362,30 C392,28 414,52 414,82 C414,112 392,134 362,134 '
               'C332,134 310,112 310,82 C310,50 332,30 362,30Z', 5, INK, PAPER)
        + stroke('M362,46 L362,52', 4) + stroke('M362,112 L362,118', 4)
        + stroke('M326,82 L332,82', 4) + stroke('M392,82 L398,82', 4)
        + stroke('M362,82 L362,60', 5)
        + stroke('M362,82 L382,94', 5, RED)
        + '<circle cx="362" cy="82" r="4.5" fill="%s"/>' % INK
        # motion swooshes
        + stroke('M300,52 C296,62 294,72 294,82', 3.5)
        + stroke('M426,104 C430,96 432,88 432,80', 3.5)
    )
    return svg('0 0 446 504', person + clock)


SCENES = {
    'login': login,
    'hello': hello,
    'github': github,
    'empty_knowledge': empty_knowledge,
    'empty_history': empty_history,
}

if __name__ == '__main__':
    for name, fn in SCENES.items():
        write(name, fn())
