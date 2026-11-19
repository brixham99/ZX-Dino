# Dino Run (OpticOS, phase 1)

Dino Run is a tribute to the Chrome offline T-Rex game for the OpticOS 48K ROM (unchanged ROM, SHA a508e65a…2423).
(c) 2026 Optica Technology Design.

**Load:** `dino.tzx` (on The Spectrum: M in Media select, then LOAD "") or `dino.tap`. The tape has two blocks: the program `dinorun` (auto-runs PROC start) and `dinocode` (CODE 48000,4408).

**Controls:**
- SPACE, Q or 7 (cursor up): jump. Hold the key for a higher jump.
- A or 6 (cursor down): duck, or a fast drop in the air.
- SPACE: start, or restart after GAME OVER.
- BREAK (CAPS SHIFT + SPACE): stop.

## Split
- **OpticBASIC, `dino.bas` (4220-byte program block):**
  - Title screen and game loop.
  - Picks each obstacle: type, group size, gap, bird height, no three of a kind in a row.
  - Speed ramp.
  - Beeps.
  - HI score.
  - GAME OVER and restart.
- **Machine code, `dino.asm` (4408 bytes at 48000, assembled with pasmo):**
  - Runs from an IM 2 frame interrupt at 25 steps a second (the handler also calls the ROM's own $0038).
  - Physics and collision.
  - Scrolling ground (8 pre-shifted copies).
  - Pre-shifted sprites, built in RAM at start-up.
  - An off-screen buffer copied to the screen by dirty spans, ahead of the beam, so nothing tears.
  - Clouds and the score digits.
- **BASIC to machine code interface:** CALL/USR/POKE (documented at the top of `dino.bas`).
  - Code entry points: 48000 init, 48003 step, 48006 dead, 48022 go live.
  - Parameters: 48012 speed, 48014 score, 48016–48020 next obstacle, 48021 events, 48026 crash.

## Build and test
```
python3 build.py          # sprites.py -> sprites.inc, pasmo, then dino.tap / dino.tzx recorded through the ROM's own SAVE
python3 tools/rigtest.py  # headless rig: bot reaches about 2700 points, crash, restart
python3 tools/fuse_play.py 25   # real Fuse (slowed), pixel-reading pilot via xdotool; grabs in shots/
```
The best grabs are in `shots/best/` at 3x. The pterodactyl grab comes from the rig, because the Fuse pilot doesn't survive to bird speed (score about 590).
