"""The pilot's eyes and hands, shared by the rig check and real Fuse: it sees
only the screen's pixels (any colours, so night works too) and answers which
keys to hold. p(X, Y) gives the colour at screen pixel X, Y."""
GROUND = 56 + 82                     # screen line of the ground line
def inkf(p):
    paper = p(0, 0)                  # row 0 is always empty in play
    return lambda X, Y: p(X, Y) != paper
def obstacles(ink):
    """ink groups right of the dino across the play strip -> [left, right, top, bottom]"""
    cols = {}
    for X in range(40, 256):
        ys = [Y for Y in range(96, GROUND - 1) if ink(X, Y)]
        if ys: cols[X] = (min(ys), max(ys))
    gs = []
    for X in sorted(cols):
        if gs and X - gs[-1][1] <= 3:
            g = gs[-1]; gs[-1] = [g[0], X, min(g[2], cols[X][0]), max(g[3], cols[X][1])]
        else: gs.append([X, X, cols[X][0], cols[X][1]])
    return [g for g in gs if g[3] >= 104]          # clouds, moon and stars stay higher
def dino_top(ink):
    for Y in range(90, GROUND):
        if any(ink(X, Y) for X in range(18, 36)): return Y
    return GROUND
def game_over(ink):
    """GAME OVER is drawn at x 94, lines 72-79, a letter in every other 4-pixel
    cell: all eight must have ink (one cloud can't cover them all)"""
    return all(any(ink(94 + 4 * i + dx, Y) for dx in range(4) for Y in range(72, 80)) for i in (0, 2, 4, 6, 10, 12, 14, 16))
class Pilot:
    def __init__(self): self.v = 7.2; self.prev = None; self.until = -1; self.passed = 0
    def step(self, p, t):
        """-> (jump, duck, next obstacle) for a look at the screen at time t (in frames)"""
        ink = inkf(p); gs = obstacles(ink)
        ahead = [g for g in gs if g[0] > 44]; nxt = ahead[0] if ahead else None
        if nxt and self.prev:
            dx = self.prev[0] - nxt[0]
            if 3 <= dx <= 20: self.v = 0.7 * self.v + 0.3 * dx     # one step's move
            elif dx < -30: self.passed += 1
        if nxt and (not self.prev or nxt[0] != self.prev[0]): self.prev = nxt
        if not nxt: self.prev = None
        top = dino_top(ink); on_ground = top >= GROUND - 23
        duck = False; jump = t < self.until
        if nxt:
            d = nxt[0] - 38; bottom = nxt[3]
            if bottom < GROUND - 22: pass                          # high bird: run under
            elif bottom < GROUND - 9:                              # mid bird: duck
                duck = d < self.v * 3 + 8 and not jump
            elif on_ground and not jump and d <= self.v * 2.5 + 6:
                big = GROUND - nxt[2] > 19
                n = max(1, (nxt[1] - nxt[0] + 4) // (12 if big else 8))
                bird = GROUND - nxt[2] > 26
                self.until = t + (12 if bird else (8 if big else 2) + 2 * n)
                jump = True
        return jump, duck, nxt
