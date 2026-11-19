#!/usr/bin/env python3
"""Run Dino Run in the OpticOS test rig (fast, headless): load dino.tap's
program the way the ROM does, run it, press keys by frame and save images.
Usage: tools/rigtest.py [out_dir]"""
import os, sys, time
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.environ.get('OPTICOS', '/workspace/opticos-repo')
sys.path.insert(0, os.path.join(REPO, 'tools', 'rig'))
from p3lib import Basic, SYM
OUT = sys.argv[1] if len(sys.argv) > 1 else '/tmp/dino_rig'; os.makedirs(OUT, exist_ok=True)
prog = [l.strip() for l in open(os.path.join(HERE, 'dino.bas')) if l.strip()]
code = open(os.path.join(HERE, 'dinocode.bin'), 'rb').read()
b = Basic(); s = b.s
from rig import lib
lib.z_options(1, 1)          # ROM write-protect and memory contention, as on a real 48K
b.line('NEW'); b.line('CLS'); b.enter(prog)
err = [r for r in b.screen() if r and r != ']']
print('after entering:', err[-5:])
s.load(48000, code)
try: b.line('RUN', 30_000_000)
except TimeoutError: pass
s.frame(100)
s.image().save(os.path.join(OUT, 'title.png'))
print('screen rows:', [r for r in b.screen() if r][:8])
import re
SY = {m.group(1): int(m.group(2), 16) for m in (re.match(r'(\S+)\s+EQU\s+0?([0-9A-F]+)H', l) for l in open(os.path.join(HERE, 'dino.sym'))) if m}
def objs():
    o = []
    for i in range(3):
        a = SY['objs'] + 6 * i; t = s.peek(a)
        if t:
            x = s.dpeek(a + 2); x = x - 65536 if x > 32767 else x
            o.append((t, s.peek(a + 1), x, s.peek(a + 4)))
    return o
def score(): return s.dpeek(48014)
WIDTH = {1: 8, 2: 12, 3: 23}
LOG = []
def bot(frames, smart=True, shots=()):
    """play like a person: hold SPACE for a full jump when a cactus or low bird
    gets close, duck under a mid bird, run under a high one"""
    f = 0; hold = 0
    while f < frames:
        duck = False
        if smart:
            spd = s.dpeek(48012) / 256
            for t, n, x, y in objs():
                d = x - 38                                         # gap to the dino's nose
                if t == 3 and y < 50: continue                     # high bird
                if t == 3 and y < 62:
                    if -30 < d < spd * 4: duck = True
                    continue
                if 0 <= d <= spd * 2 + 4 and s.peek(SY['air']) == 0 and hold == 0:
                    hold = {1: 2 + 2 * n, 2: 8 + 2 * n, 3: 12}[t]      # short hops for small cacti
        if any(t == 3 and 70 < x < 140 for t, n, x, y in objs()) and not os.path.exists(os.path.join(OUT, 'bird.png')):
            s.image().save(os.path.join(OUT, 'bird.png'))
        LOG.append((f, [(t, n, x) for t, n, x, y in objs()], s.peek(SY['air']), round(s.dpeek(SY['hgt']) / 256), hold))
        s.key(' ', hold > 0); s.key('a', duck and hold == 0)
        hold = max(0, hold - 1)
        s.frame(1); f += 1
        if s.peek(SY['crash']): break
        for fr, name in shots:
            if f == fr: s.image().save(os.path.join(OUT, name))
    s.key(' ', False); s.key('a', False)
    return f
def rate(n=500):
    """frames per step while playing: ticks counted over n frames"""
    return n / ((s.peek(SY['tick']) - t0) % 256 or 1)
s.press([' '], 2, 2)
t0 = s.peek(SY['tick']); f0 = s.frames
ticks = 0; last = s.peek(SY['tick'])
def counting_bot(frames, **kw):
    global ticks, last
    n = 0
    while n < frames:
        g = bot(50, **kw); n += g
        now = s.peek(SY['tick']); ticks += (now - last) % 256; last = now
        if s.peek(SY['crash']): break
    return n
f = counting_bot(9000)
import collections
seen = collections.Counter(); prev = set()
for fr, ob, *_ in LOG:
    for t, n, x in ob:
        if x > 150: seen[(t, n)] += 1 if (t, n, x) not in prev else 0
    prev = set(ob)
print('obstacles seen near the right edge (type, count): frames', dict(seen))
print('\n'.join(map(str, LOG[-40::2]))); print('at the crash: objects', objs(), 'dino height', s.dpeek(SY['hgt']) / 256, 'air', s.peek(SY['air']), 'duck', s.peek(SY['duck']))
print('smart bot: ran %d frames (%d steps: %.2f frames a step), score %d, crashed %d, speed %.2f px/step' % (
    f, ticks, f / max(ticks, 1), score(), s.peek(SY['crash']), s.dpeek(48012) / 256))
if not s.peek(SY['crash']):
    g = bot(3000, smart=False); print('  (no crash in that run; stopped steering: crashed after %d more frames)' % g)
s.frame(80); s.image().save(os.path.join(OUT, 'over.png'))
print([r for r in b.screen() if 'G A M E' in r or 'HI' in r])
s.press([' '], 3, 3); s.frame(20)
print('restarted: crash', s.peek(SY['crash']), 'mode', s.peek(SY['mode']), 'score', score())
f = bot(2000, smart=False)
print('no-jump bot: crashed after %d frames, score %d, crash flag %d' % (f, score(), s.peek(SY['crash'])))
s.frame(60); s.image().save(os.path.join(OUT, 'over2.png'))
