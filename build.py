#!/usr/bin/env python3
"""Build Dino Run: sprites.inc, dinocode.bin (pasmo), then dino.tap and dino.tzx.

The tape holds what the OpticOS ROM itself writes: dino.bas is typed into
the ROM in the OpticOS test rig (opticos-repo/tools/rig), the code is put
at 46900, and the ROM's own  SAVE "dinorun" AUTO start  and
SAVE "dinocode" CODE 46900,n  are recorded off the MIC signal and decoded
into blocks, checking names, the OpticBASIC "OB" $01 $00 signature and the
parity bytes.  Usage: python3 build.py   (needs pasmo, the OpticOS repo
with build/opticos.rom and the rig's libz80.so)"""
import os, sys, struct, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.environ.get('OPTICOS', '/workspace/opticos-repo')   # a checkout of github.com/brixham99/OpticOS (built)
PASMO = os.environ.get('PASMO', '/workspace/tools-prefix/usr/bin/pasmo')
ORG = 46900
subprocess.run([sys.executable, os.path.join(HERE, 'sprites.py')], check=True, stdout=subprocess.DEVNULL)
subprocess.run([PASMO, '--bin', 'dino.asm', 'dinocode.bin', 'dino.sym'], cwd=HERE, check=True)
code = open(os.path.join(HERE, 'dinocode.bin'), 'rb').read()
sys.path.insert(0, os.path.join(REPO, 'tools', 'rig'))
from p3lib import Basic
from rig import decode_pulses
prog = [l.strip() for l in open(os.path.join(HERE, 'dino.bas')) if l.strip()]
b = Basic(); s = b.s
b.line('NEW'); b.enter(prog)
s.load(ORG, code)
def record(cmd, name, typ):
    s.mic_start(3); b.line(cmd, 3_000_000_000)
    got = decode_pulses(s.mic_pulses())
    assert len(got) == 2, (name, len(got))
    hdr, data = got
    assert hdr[0] == 0 and hdr[1] == typ and len(hdr) == 19 and hdr[2:12].decode().rstrip() == name, hdr
    for blk in got:
        p = 0
        for x in blk[:-1]: p ^= x
        assert p == blk[-1], name
    return [bytes(hdr), bytes(data)]
blocks = record('SAVE "dinorun" AUTO start', 'dinorun', 0)
assert blocks[1][1:5] == b'OB\x01\x00', 'not an OpticBASIC program'
blocks += record('SAVE "dinocode" CODE %d,%d' % (ORG, len(code)), 'dinocode', 3)
assert blocks[3][1:-1] == code and blocks[2][14] | blocks[2][15] << 8 == ORG
tap = b''.join(struct.pack('<H', len(x)) + x for x in blocks)
open(os.path.join(HERE, 'dino.tap'), 'wb').write(tap)
tzx = b'ZXTape!\x1a\x01\x14' + b''.join(b'\x10' + struct.pack('<HH', 1000, len(x)) + x for x in blocks)
open(os.path.join(HERE, 'dino.tzx'), 'wb').write(tzx)
print('program dinorun: %d bytes; dinocode: CODE %d,%d (ends %d)' % (len(blocks[1]) - 2, ORG, len(code), ORG + len(code) - 1))
print('wrote dino.tap (%d bytes) and dino.tzx (%d bytes)' % (len(tap), len(tzx)))
