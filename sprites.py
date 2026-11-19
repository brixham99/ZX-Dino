#!/usr/bin/env python3
"""Dino Run sprites, drawn by hand at Spectrum scale (about half the size of the
Chrome game's 1x sprites: the T-Rex is 22 x 21 here, 44 x 47 there).
'#' is an ink pixel. Writes sprites.inc (for dino.asm) and shots/sprites.png.
Each dino frame is followed by its collision mask: the frame shrunk by one
pixel all round (a pixel stays if it and its 4 neighbours are ink), so a
graze of the outline does not count, as in the original's forgiving boxes."""
import os
HERE = os.path.dirname(os.path.abspath(__file__))
HEAD = """\
............########..
...........##.########
...........###########
...........###########
...........###########
...........#####......
...........########...
#.........#####.......
#........######.......
##......##########....
###....#########.#....
###############.......
.##############.......
..#############.......
...###########........
....#########.........
.....#######..........""".split('\n')
LEGS = {
 'stand': ["......###.##..........",
           "......##...#..........",
           "......#....#..........",
           "......##...##........."],
 'run1':  ["......###.##..........",
           "......##...##.........",
           "......#...............",
           "......##.............."],
 'run2':  ["......###.##..........",
           ".......##..#..........",
           "...........#..........",
           "...........##........."],
}
def dino(legs, eye='.'):
    rows = [r for r in HEAD] + LEGS[legs]
    if eye != '.': rows[1] = rows[1][:13] + eye + rows[1][14:]
    return rows
STAND = dino('stand'); BLINK = dino('stand', '#'); RUN1 = dino('run1'); RUN2 = dino('run2')
DEAD = dino('stand')
DEAD[0] = "............########.."
DEAD[1] = "...........#.#.#######"   # the X eye: a 3x3 cross in a hollow
DEAD[2] = "...........##.########"
DEAD[3] = "...........#.#.#######"
DEAD[5] = "...........#####......"
DEAD[6] = "...........###........"   # mouth open: the lower jaw dropped
DEAD[7] = "#.........######......"
DUCK_TOP = """\
......................########
#.......#################.####
##...#########################
###.##########################
##########################....
.####################.#######.
..##################..#.......
....##############............""".split('\n')
DUCK1 = DUCK_TOP + ["......###.##..................",
                    "......##...##.................",
                    "......#.......................",
                    "......##......................"]
DUCK2 = DUCK_TOP + ["......###.##..................",
                    ".......##..#..................",
                    "...........#..................",
                    "...........##................."]
CACTUS_S = """\
...##...
..####..
..####..
#.####..
#.####.#
#.####.#
#.####.#
######.#
.#######
..######
..####..
..####..
..####..
..####..
..####..
..####..
..####..""".split('\n')
CACTUS_L = """\
.....##.....
....####....
....####....
....####....
##..####....
##..####..##
##..####..##
##..####..##
##..####..##
##..####..##
##..####..##
##..######.#
###.####..##
.#######..##
..######.###
....#######.
....######..
....####....
....####....
....####....
....####....
....####....
....####....
....####....""".split('\n')
PTERO1 = """\
.........#.............
.........##............
.........###...........
.........####..........
....##...#####.........
...###...######........
..####...#######.......
.##.##############.....
#######################
....###############....
.......##########......
.........#####.........
.......................
.......................
.......................
.......................""".split('\n')   # wings up
PTERO2 = """\
.......................
.......................
.......................
.......................
....##.................
...###.................
..####.................
.##.##############.....
#######################
....###############....
.......#######.........
.........#####.........
.........####..........
.........###...........
.........##............
.........#.............""".split('\n')   # wings down
CLOUD = """\
..........#####........
........##.....##......
.......#.........#.....
.....##...........#....
...##.............##...
..#.................#..
.#...................#.
#######################""".split('\n')
RESTART = """\
.....#######......
...###########.#..
..###.......####..
.##........#####..
.##.......######..
##................
##................
##................
##..............##
##..............##
.##............##.
.###..........###.
..####......####..
...############...
.....########.....""".split('\n')
def mask(rows):
    H, W = len(rows), max(len(r) for r in rows)
    ink = lambda y, x: 0 <= y < H and 0 <= x < len(rows[y]) and rows[y][x] == '#'
    return [''.join('#' if ink(y, x) and ink(y - 1, x) and ink(y + 1, x) and ink(y, x - 1) and ink(y, x + 1) else '.'
                    for x in range(W)) for y in range(H)]
def tobytes(rows):
    W = max(len(r) for r in rows); wb = (W + 7) // 8; out = []
    for r in rows:
        r = r.ljust(wb * 8, '.')
        out += [int(r[i * 8:i * 8 + 8].replace('#', '1').replace('.', '0'), 2) for i in range(wb)]
    return wb, len(rows), out
SPRITES = [('stand', STAND, True), ('blink', BLINK, True), ('run1', RUN1, True), ('run2', RUN2, True),
           ('duck1', DUCK1, True), ('duck2', DUCK2, True), ('dead', DEAD, False),
           ('cs', CACTUS_S, False), ('cl', CACTUS_L, False), ('pt1', PTERO1, False), ('pt2', PTERO2, False),
           ('cloud', CLOUD, False), ('restart', RESTART, False)]
def ground():
    """The ground: a 512-pixel loop, 7 rows. Row 1 is the line; here and there it
    rises a pixel (a bump, rows 0-1) or dips (rows 1-2); rows 3-6 hold the pebbles
    and short dashes of the original's sand texture."""
    import random
    rnd = random.Random(1119); W = 512
    g = [['.'] * W for _ in range(7)]
    for x in range(W): g[1][x] = '#'
    x = 20
    while x < W - 20:
        w = rnd.choice([4, 5, 6, 8]); up = rnd.random() < 0.6
        for i in range(w):
            g[1][x + i] = '.'
            g[0 if up else 2][x + i] = '#'
        g[0 if up else 2][x - 1] = '.'
        x += w + rnd.randint(40, 110)
    for _ in range(70):
        y = rnd.choice([3, 3, 4, 4, 5, 6]); x = rnd.randrange(W); n = rnd.choice([1, 1, 2, 2, 3, 4])
        for i in range(n): g[y][(x + i) % W] = '#'
    return [''.join(r) for r in g]
def width(rows): return max(len(r) for r in rows)
if __name__ == '__main__':
    lines = ['; sprites.inc - made by sprites.py: width in bytes, height, then the rows (MSB = left pixel)']
    for name, rows, m in SPRITES:
        for lab, rr in [(name, rows)] + ([(name + '_m', mask(rows))] if m else []):
            wb, h, b = tobytes(rr)
            lines.append('spr_%s:' % lab); lines.append('        defb %d,%d' % (wb, h))
            for i in range(0, len(b), 12): lines.append('        defb ' + ','.join('$%02X' % v for v in b[i:i + 12]))
    g = ground(); lines.append('gstrip:   ; 7 rows of 512 pixels: bumps, the line, dips, pebbles')
    for r in g:
        b = [int(r[i:i + 8].replace('#', '1').replace('.', '0'), 2) for i in range(0, 512, 8)]
        for i in range(0, 64, 16): lines.append('        defb ' + ','.join('$%02X' % v for v in b[i:i + 16]))
    hs = {n: len(r) for n, r, _ in SPRITES}
    font = open(os.path.join(os.environ.get('OPTICOS', '/workspace/opticos-repo'), 'font', 'font4x8.bin'), 'rb').read()   # OpticOS's own 4x8 font
    lines.append('digits:   ; 0-9 from the OpticOS font, 8 lines each, glyph in the top nibble')
    for d in range(10):
        k = (48 + d - 32) >> 1
        g = [(font[8 * k + r] & 0xF0) if d % 2 == 0 else ((font[8 * k + r] & 15) << 4) for r in range(8)]
        lines.append('        defb ' + ','.join('$%02X' % v for v in g))
    for n, r, _ in SPRITES:
        wb, h, _ = tobytes(r); lines.append('SZ_%s equ %d' % (n, (wb + 1) * h + 2))
    lines.append('H_CS equ %d\nH_CL equ %d\nH_PT equ %d' % (hs['cs'], hs['cl'], hs['pt1']))
    open(os.path.join(HERE, 'sprites.inc'), 'w').write('\n'.join(lines) + '\n')
    from PIL import Image, ImageDraw
    Z = 6; X = 4; Y = 4; im = Image.new('RGB', (900, 420), (255, 255, 255)); d = ImageDraw.Draw(im)
    for name, rows, m in SPRITES:
        w = width(rows)
        if X + w * Z > 890: X = 4; Y += 26 * Z
        for y, r in enumerate(rows):
            for x, ch in enumerate(r):
                if ch == '#': d.rectangle([X + x * Z, Y + y * Z, X + x * Z + Z - 1, Y + y * Z + Z - 1], fill=(83, 83, 83))
        X += w * Z + 14
    im.save(os.path.join(HERE, 'shots', 'sprites_preview.png'))
    for name, rows, m in SPRITES: print(name, width(rows), 'x', len(rows))
