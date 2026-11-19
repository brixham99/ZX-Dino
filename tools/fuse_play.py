#!/usr/bin/env python3
"""Play Dino Run in real Fuse (fuse-sdl, 48K, the OpticOS ROM) and take the
screenshots. Fuse runs slowed down (--speed) so a pilot can keep up. It reads
the obstacles from the Fuse window's pixels only, and presses SPACE or A
through xdotool, as a player would. The tape loads with the tape traps on.
Usage: fuse_play.py [speed]   (shots go to ../shots)"""
import sys, os, time
HERE = os.path.dirname(os.path.abspath(__file__)); DR = os.path.dirname(HERE)
os.environ.setdefault('OPTICOS_REPO', '/workspace/opticos-repo')
sys.path.insert(0, '/workspace/happybat/tools')
from fuse_common import *            # Fuse wrapper, grab, load, down/up (from Happy Bat)
import fuse_phase1
from paths import ROM
TAPE = os.path.join(DR, 'dino.tap'); OUT = os.path.join(DR, 'shots')
SPEED = int(sys.argv[1]) if len(sys.argv) > 1 else 25
BX, BY = 32, 24                      # display origin in the Fuse window
GROUND = 56 + 82                     # screen line of the ground line
def ink(p, X, Y): return sum(p(X, Y)) < 200
def px(im):
    w = im.load(); return lambda X, Y: w[BX + X, BY + Y]
def obstacles(p):
    """black groups right of the dino over the play strip -> [left, right, top, bottom]"""
    cols = {}
    for X in range(44, 256):
        ys = [Y for Y in range(96, GROUND - 1) if ink(p, X, Y)]
        if ys: cols[X] = (min(ys), max(ys))
    gs = []
    for X in sorted(cols):
        if gs and X - gs[-1][1] <= 3:
            g = gs[-1]; gs[-1] = [g[0], X, min(g[2], cols[X][0]), max(g[3], cols[X][1])]
        else: gs.append([X, X, cols[X][0], cols[X][1]])
    return [g for g in gs if g[3] >= 104]   # clouds stay higher
def game_over(p): return any(ink(p, X, Y) for X in range(92, 160) for Y in range(72, 80))
def title(p): return any(ink(p, X, Y) for X in range(0, 120) for Y in range(160, 168))

_orig = fuse_phase1.subprocess.Popen
def popen(args, **kw):
    if args and args[0] == 'fuse-sdl': args = args + ['--speed', str(SPEED)]
    return _orig(args, **kw)
fuse_phase1.subprocess.Popen = popen
kill(); f = Fuse(ROM, TAPE, traps=True)
time.sleep(3 * 100 / SPEED + 2)      # NEW is a cold start: let it boot
load(f, True, hold=0.12 * 100 / SPEED)
t0 = time.time()
while time.time() - t0 < 400:
    time.sleep(1); p = px(grab(f))
    if title(p): break
print('title after %.0f s' % (time.time() - t0))
time.sleep(2 * 100 / SPEED); grab(f).save(os.path.join(OUT, 'fuse_title.png'))
FR = 0.02 * 100 / SPEED              # real seconds per frame
def press(k, frames): down(k); time.sleep(FR * frames); up(k)
saved = set(); results = []; DBG = []
for attempt in range(1, 6):
    press('space', 10); time.sleep(FR * 30)
    t1 = time.time(); jumps = 0; ducking = False; held = None; holdfor = 0; last = 0
    passed = 0; prevx = None; speed_px = 7.2
    steer = True
    while time.time() - t1 < 900:
        now = time.time(); im = grab(f); p = px(im)
        if game_over(p): break
        if {'jump', 'bird'} <= saved and passed >= 25: steer = False   # let it crash
        if not steer:
            if held: up('space'); held = None
            if ducking: up('a'); ducking = False
            time.sleep(0.01); continue
        gs = obstacles(p); ahead = [g for g in gs if g[0] > 47]; nxt = ahead[0] if ahead else None
        if held and now - held > holdfor: up('space'); held = None
        if nxt and prevx is not None and nxt[0] > prevx[0] + 30: passed += 1
        elif nxt and prevx is not None and now > prevx[1] and nxt[0] < prevx[0]:
            v = (prevx[0] - nxt[0]) / (now - prevx[1]) * FR * 2         # px per step
            if 4 < v < 20: speed_px = 0.8 * speed_px + 0.2 * v
        prevx = (nxt[0], now) if nxt else None
        lead = 38 + speed_px * 2.5 + 4                                   # as the rig bot
        duck = False
        DBG.append((round(now - t1, 2), nxt, round(lead), round(speed_px, 1), bool(held), jumps))
        if nxt:
            d = nxt[0]; bottom = nxt[3]; top = nxt[2]
            if bottom < GROUND - 22: pass                    # high bird: run under
            elif bottom < GROUND - 9:                        # mid bird: duck
                duck = d < 60 + speed_px * 3 and nxt[1] > 20
            elif d <= lead and not held and now - last > FR * 16:
                big = GROUND - top > 19
                n = max(1, (nxt[1] - nxt[0] + 4) // (12 if big else 8))
                holdfor = FR * ((8 if big else 2) + 2 * n)
                if top < GROUND - 30: holdfor = FR * 12        # low bird
                down('space'); held = now; last = now; jumps += 1
                if passed >= 2 and 'jump' not in saved:
                    time.sleep(FR * 7); im2 = grab(f); q = px(im2)
                    clouds = any(ink(q, X, Y) for X in range(40, 256) for Y in range(60, 100))
                    if clouds and len(obstacles(q)) >= 1:
                        im2.save(os.path.join(OUT, 'fuse_jump.png')); saved.add('jump'); print('jump shot')
        if duck != ducking: (down if duck else up)('a'); ducking = duck
        if 'bird' not in saved and any(g[3] < GROUND - 4 and g[1] - g[0] >= 16 and 100 < g[0] < 200 for g in gs):
            im.save(os.path.join(OUT, 'fuse_bird.png')); saved.add('bird'); print('bird shot')
        time.sleep(0.005)
    if held: up('space')
    if ducking: up('a')
    if '-v' in sys.argv:
        ch = [d for i, d in enumerate(DBG) if i == 0 or d[1:] != DBG[i - 1][1:]]
        print('\n'.join(map(str, ch[-16:])))
    DBG.clear()
    time.sleep(FR * 150); im = grab(f)
    im.save(os.path.join(OUT, 'fuse_gameover%d.png' % attempt))
    print('attempt', attempt, 'jumps', jumps, 'obstacles passed', passed, 'seconds', round(time.time() - t1))
    results.append(passed)
    if {'jump', 'bird'} <= saved: break
# restart: SPACE from the game over screen starts a new game (score back to 0)
press('space', 10); time.sleep(FR * 60); im = grab(f); p = px(im)
print('restart: GAME OVER gone', not game_over(p))
im.save(os.path.join(OUT, 'fuse_restart.png'))
f.close(); print('saved', sorted(saved), results)
