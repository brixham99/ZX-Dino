#!/usr/bin/env python3
"""Play Dino Run in real Fuse (fuse-sdl, 48K, the OpticOS ROM) and take the
screenshots. Fuse runs slowed down (--speed) so the pilot (tools/pilot.py) can
keep up; it sees only the Fuse window's pixels and presses SPACE or A through
xdotool, as a player would. The tape loads with the tape traps on.
Usage: fuse_play.py [speed] [games]   (shots go to ../shots/fuse_*.png)"""
import sys, os, time
HERE = os.path.dirname(os.path.abspath(__file__)); DR = os.path.dirname(HERE)
os.environ.setdefault('OPTICOS_REPO', os.environ.get('OPTICOS', '/workspace/opticos-repo'))
sys.path.insert(0, os.environ.get('HAPPYBAT_TOOLS', '/workspace/happybat/tools'))   # Fuse helpers from the Happy Bat repo
sys.path.insert(0, HERE)
from fuse_common import *            # Fuse wrapper, grab, load, down/up
import fuse_phase1, pilot
from paths import ROM
TAPE = os.path.join(DR, 'dino.tap'); OUT = os.path.join(DR, 'shots')
SPEED = int(sys.argv[1]) if len(sys.argv) > 1 else 20
GAMES = int(sys.argv[2]) if len(sys.argv) > 2 else 3
BX, BY = 32, 24                      # display origin in the Fuse window
FR = 0.02 * 100 / SPEED              # real seconds per Spectrum frame
def px(im):
    w = im.load(); return lambda X, Y: w[BX + X, BY + Y]
def black(p, X, Y): return sum(p(X, Y)) < 200
_orig = fuse_phase1.subprocess.Popen
def popen(args, **kw):
    if args and args[0] == 'fuse-sdl': args = args + ['--speed', str(SPEED)]
    return _orig(args, **kw)
fuse_phase1.subprocess.Popen = popen
def press(k, frames): down(k); time.sleep(FR * frames); up(k)
def save(im, name): im.save(os.path.join(OUT, name)); print('  shot', name)

kill(); f = Fuse(ROM, TAPE, traps=True)
time.sleep(3 * 100 / SPEED + 2)      # NEW is a cold start: let it boot
load(f, True, hold=0.12 * 100 / SPEED)
t0 = time.time()
while time.time() - t0 < 600:        # the title: "Press SPACE to start" and the copyright line
    time.sleep(1); p = px(grab(f))
    if any(black(p, X, 164) for X in range(88, 170)) and any(black(p, X, 188) for X in range(60, 190)): break
print('title after %.0f s' % (time.time() - t0))
time.sleep(30 * FR); im = grab(f); save(im, 'fuse_title.png')
p = px(im); print('title shows no score:', not any(black(p, X, Y) for X in range(232, 252) for Y in range(48, 56)))
saved = set(); results = []; DEBUG = os.environ.get('DEBUG'); LOG = []; RING = []
for game in range(1, GAMES + 1):
    press('space', 3)                # one short tap is enough (start, or restart)
    time.sleep(FR * 25)
    P = pilot.Pilot(); t1 = time.time(); jd = (False, False); last_air = 0
    flash_seen = set(); night_seen = False
    while time.time() - t1 < 1500:
        now = time.time(); im = grab(f); p = px(im); ink = pilot.inkf(p)
        if pilot.game_over(ink): break
        j, d, nxt = P.step(p, (now - t1) / FR)
        if DEBUG: RING.append(im); RING[:] = RING[-40:]
        if DEBUG: LOG.append((round((now - t1) / FR, 1), nxt, pilot.dino_top(ink), round(P.v, 1), j, d))
        if (j, d) != jd:
            (down if j else up)('space'); (down if d else up)('a'); jd = (j, d)
        night = p(0, 0)[0] < 100
        if night and not night_seen: night_seen = True; print('  night at %.0f s' % (now - t1))
        gs = pilot.obstacles(ink)
        if j and pilot.dino_top(ink) < pilot.GROUND - 34 and gs and 'jump' not in saved and not night:
            if any(ink(X, Y) for X in range(40, 256) for Y in range(60, 100)): save(im, 'fuse_jump.png'); saved.add('jump')
        if 'bird' not in saved and any(g[3] < pilot.GROUND - 4 and g[1] - g[0] >= 16 and 90 < g[0] < 220 for g in gs):
            save(im, 'fuse_bird.png'); saved.add('bird')
        if night and 'night' not in saved and gs and any(ink(X, Y) for X in range(40, 256) for Y in range(58, 80)) and now - t1 > 0:
            if pilot.obstacles(ink) and 60 < gs[0][0] < 200: save(im, 'fuse_night.png'); saved.add('night')
        # the 100-point blink: the score digits (x 232-251, row 6) go blank while play goes on
        dig = any(ink(X, Y) for X in range(232, 252) for Y in range(48, 56))
        if not dig and P.passed > 3: flash_seen.add('off')
        if dig and 'off' in flash_seen: flash_seen.add('on')
        if not dig and 'flash' not in saved and P.passed > 3 and not night: save(im, 'fuse_flash_off.png'); saved.add('flash')
        time.sleep(0.003)
    up('space'); up('a')
    if DEBUG:
        gaps = [b[0] - a[0] for a, b in zip(LOG, LOG[1:])]
        print('looks', len(LOG), 'mean gap %.2f frames, max %.1f' % (sum(gaps) / len(gaps), max(gaps)))
        print('\n'.join(map(str, LOG[-12:]))); LOG.clear()
        os.makedirs('/tmp/ring', exist_ok=True)
        for i, r in enumerate(RING + [im]): r.save('/tmp/ring/%02d.png' % i)
    time.sleep(FR * 150); im = grab(f); save(im, 'fuse_gameover%d.png' % game)
    p = px(im); ink = pilot.inkf(p)
    print('game %d: %.0f s, obstacles passed %d, speed %.1f px/step, night %s, blink seen %s, GAME OVER %s' % (
        game, time.time() - t1, P.passed, P.v, night_seen, sorted(flash_seen), pilot.game_over(ink)))
    results.append(P.passed)
press('space', 1)                    # restart from a 1-frame tap
time.sleep(FR * 40); p = px(grab(f)); print('restart from a 1-frame tap: GAME OVER gone', not pilot.game_over(pilot.inkf(p)))
grab(f).save(os.path.join(OUT, 'fuse_restart.png'))
f.close(); print('saved', sorted(saved), results)
