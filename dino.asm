; =============================================================================
; dino.asm - the machine-code half of Dino Run, for OpticOS (ROM v1.0.3)
; Assemble with pasmo:   pasmo --bin dino.asm dinocode.bin
;
; Written from scratch for OpticOS (clean room): no Sinclair ROM code is used
; or called. It touches only its own memory, the screen bitmap, the keyboard
; port and FRAMES (23672). It does not use IX, IY or the alternate registers.
; It needs interrupts on (they are, under OpticBASIC): it paces with HALT.
;
; OpticBASIC runs the game (title, which obstacle comes next and when, the
; speed, the score display, sounds, game over and restart). This code does
; what has to happen 25 times a second: the T-Rex's jump and duck, moving the
; cacti, pterodactyls, clouds and ground, the collision test and drawing.
;
; Every step draws the playfield into an off-screen buffer (90 lines
; of 44 bytes: 6 spare bytes each side so sprites can slide off the edges
; without clipping), then copies the middle 32 bytes of each line to screen
; lines 56-145. Nothing flickers. The attributes are left to BASIC.
;
; Entry points (no register arguments: BASIC POKEs the block below):
;   CALL 48000      new game: clear everything, the dino standing; draws once
;   r% = USR 48003  one step (2 frames). r% is 0 if nothing happened, else bits:
;                   1 crashed, 4 ready for the next obstacle, 8 a jump began,
;                   16 the score reached a hundred (the same is left in 48021)
;   CALL 48006      game over: draw the restart icon and show it
;
; Drawing: the buffer is cleared, drawn and copied only along each line's dirty
; span (the columns drawn on that line this step or the last), so a step costs
; about what the sprites cover, not the whole playfield. The score (top right)
; is drawn here too, in the ROM's 4x8 digits, as it changes several times a
; second; BASIC prints the HI score and the titles.
; =============================================================================

BUF     equ 52600           ; play buffer, BW x BH
BW      equ 44
BH      equ 90              ; lines 0-89 (nothing is drawn below the ground's last row, 87)
SCR0    equ 56              ; screen line of buffer line 0
GY      equ 82              ; buffer line of the ground line
GROWS   equ 7               ; ground strip rows (GY-1 .. GY+5)
GSH     equ BUF+BW*BH       ; 8 pre-shifted ground strips, 7 rows of 96 bytes
GTMP    equ BUF             ; work copy of the strip while shifting (once)
PRE     equ GSH+8*GROWS*96  ; obstacles and cloud, each pre-shifted 8 ways
                            ; (P_END, below, is the end of these)
FRAMES  equ 23672
DINOBX  equ 48+16           ; the dino stands 16 pixels from the left edge
NOBJ    equ 3               ; obstacle slots, 6 bytes each
NCL     equ 4               ; cloud slots, 4 bytes each
V0      equ 3072            ; jump: 12 px/step up (8.8 fixed point)
GRAV    equ 442             ; 1.73 px/step/step
DROPV   equ 1536            ; a jump that ends early slows to 6 px/step
SDROP   equ 3072            ; duck in the air: fall at 12 px/step
MINH    equ 15*256          ; a jump rises at least 15 px
MAXH    equ 32*256          ; and ends (slows) at 32 px when held
LEAD    equ 80              ; ask for the next obstacle 80 px before it is due
IMTAB   equ $FE00           ; IM 2 table: 257 bytes of $FD, so the handler is
IMJP    equ $FDFD           ;   entered at $FDFD (a JP to isr)

        org 48000
        jp init             ; 48000
        jp step             ; 48003
        jp dead             ; 48006
; ---- parameters, POKEd and PEEKed by BASIC --------------------------------
mode:   defb 0              ; 48009  0 = title (still, the dino blinks), 1 = play
sig:    defm "DR"           ; 48010  signature: the code is loaded
speed:  defw 1843           ; 48012  pixels a step, 8.8 (7.2 at the start)
score:  defw 0              ; 48014  score (one point per 20 pixels run)
sptype: defb 0              ; 48016  next obstacle: 1 small cacti, 2 large
                            ;        cacti, 3 pterodactyl; 0 once it is out
spcnt:  defb 1              ; 48017  how many cacti in the group (1-3)
spy:    defb 0              ; 48018  pterodactyl height 0-2 (low, mid, high)
spgap:  defw 100            ; 48019  pixels after it before the next one
rflags: defb 0              ; 48021  events since BASIC last cleared it (bits as USR)
        jp golive           ; 48022  CALL: run the game from the frame interrupt
live:   defb 0              ; 48025  1 while it runs from the interrupt
crash:  defb 0              ; 48026  1 once the dino has hit something

; ---- state (zeroed by init) -------------------------------------------------
st0:
hgt:    defw 0              ; dino height above the ground, 8.8
vy:     defw 0              ; its upward speed, 8.8
air:    defb 0              ; 1 while jumping
endj:   defb 0              ; 1 once the jump has been cut short
duck:   defb 0              ; nonzero while ducking
kb:     defb 0              ; keys this step: bit 0 jump, bit 1 duck
tick:   defb 0
flags:  defb 0
dist:   defb 0              ; fraction of a pixel carried over
px:     defb 0              ; pixels moved this step
sdist:  defb 0              ; pixels towards the next point
gapc:   defw 0              ; pixels until the next obstacle may come
gscr:   defw 0              ; ground scroll, 0-511
cfrac:  defb 0
cpx:    defb 0
cgap:   defb 0              ; pixels (cloud speed) to the next cloud
objs:   defs NOBJ*6         ; type, count, x lo, x hi, y, frame
clouds: defs NCL*4          ; x lo, x hi, y (0 = free), spare
st1:
lastf:  defb 0
rng:    defb $5A
gbuilt: defb 0
dspr:   defw spr_stand      ; dino frame to draw
dy:     defb 0
savsp:  defw 0
ss:     defb 0              ; sprite shift
sw:     defb 0
sh:     defb 0
otype:  defb 0
ocnt:   defb 0
oy:     defb 0
ofr:    defb 0
owpx:   defb 0
obx:    defw 0
ospr:   defw 0
ry:     defb 0              ; the sprite just drawn: top line, height,
rh:     defb 0              ;   first and last buffer byte column
rc0:    defb 0
rc1:    defb 0
rowp:   defw 0
dgt:    defs 5
osz:    defw 0
msrc:   defw 0
ms:     defb 0
mrow:   defb 0
gtab:   defs 16

; obstacle types: frame 0, frame 1, width (group spacing), height
P_CS    equ PRE
P_CL    equ P_CS+8*SZ_cs
P_PT1   equ P_CL+8*SZ_cl
P_PT2   equ P_PT1+8*SZ_pt1
P_CLOUD equ P_PT2+8*SZ_pt2
P_END   equ P_CLOUD+8*SZ_cloud
SPT     equ P_END           ; the span records, 8 bytes a line
RAMEND  equ SPT+8*BH
typetab: defw P_CS, P_CS, SZ_cs     ; frame 0, frame 1 (8 shifts each), size of one
        defb 8, H_CS                ; group spacing, height
        defw P_CL, P_CL, SZ_cl
        defb 12, H_CL
        defw P_PT1, P_PT2, SZ_pt1
        defb 23, H_PT
pretab: defw spr_cs, P_CS, spr_cl, P_CL, spr_pt1, P_PT1, spr_pt2, P_PT2, spr_cloud, P_CLOUD
ptab:   defb GY+2-H_PT, GY+2-14-H_PT, GY+2-26-H_PT   ; pterodactyl tops

; -----------------------------------------------------------------------------
init:   call bldg
        ld hl,st0
        ld bc,st1-st0-1
        ld (hl),0
        ld d,h
        ld e,l
        inc de
        ldir
        ld hl,0
        ld (score),hl
        xor a
        ld (sptype),a
        ld (crash),a
        ld (rflags),a
        ld (live),a
        ld hl,250
        ld (gapc),hl
        ld a,12
        ld (cgap),a
        ld a,(FRAMES)
        ld (lastf),a
        or 1
        ld (rng),a
        ld hl,spr_stand
        ld (dspr),hl
        call clrbuf
        call mkspans
        call render
        call showspans
        jp drawscore

step:   call pace           ; A = updates due (1-4): one per 2 frames gone
body:   ld (nup),a
        call showspans      ; first show what the last step drew: straight after
shown:                            ; the interrupt the beam is still in the top border,
                            ; and the copy keeps ahead of it, so nothing tears
        xor a
        ld (flags),a
        ld a,(mode)
        or a
        jr nz,st_u
        ld hl,tick
        inc (hl)
        jr st_t
st_u:   call keys           ; if BASIC took longer than a step, catch up
        ld (kb),a
        ld hl,tick
        inc (hl)
        call phys
        call world
        ld hl,nup
        dec (hl)
        jr nz,st_u
st_t:   call seldino
        call render
        ld a,(crash)        ; the crash frame is shown at once (it is the last)
        or a
        call nz,showspans
st_end: ld a,(flags)
        ld hl,rflags
        or (hl)
        ld (hl),a
        ld a,(flags)
        ld c,a
        ld b,0
        ret

dead:   xor a
        ld (live),a
        im 1
        ld hl,SPT           ; show only the icon: the scene is on the screen
        ld b,BH             ; already (and the buffer was cleared after it)
        ld de,8
dd_l:   ld (hl),255
        inc hl
        ld (hl),0
        dec hl
        add hl,de
        djnz dd_l
        ld hl,spr_restart
        ld d,30
        ld bc,48+128-9
        call spr_or
        jp showspans

; ---- run the game from the frame interrupt (IM 2) ---------------------------------
; BASIC then runs freely between steps: choosing an obstacle takes it several
; frames, which would otherwise hold the game up. The handler calls the ROM's own
; ($0038: FRAMES and the keyboard, ending EI : RET) and then, every second frame,
; does a step; a step that overruns lets the next interrupt in, which only does
; the ROM's part. A crash, CALL 48006, or BREAK (CAPS SHIFT + SPACE) stops it and
; puts back IM 1.
golive: ld hl,IMTAB
        ld (hl),IMJP & 255
        ld de,IMTAB+1
        ld bc,256
        ldir
        ld a,$C3
        ld (IMJP),a
        ld hl,isr
        ld (IMJP+1),hl
        di
        ld a,(FRAMES)
        ld (lastf),a
        ld a,1
        ld (live),a
        ld a,IMTAB / 256
        ld i,a
        im 2
        ei
        ret
isr:    push af
        push bc
        push de
        push hl
        call $0038
        ld a,(live)
        or a
        jr z,is_x
        ld a,(busy)
        or a
        jr nz,is_x
        ld a,$FE            ; BREAK: CAPS SHIFT and SPACE
        in a,($FE)
        rra
        jr c,is_go
        ld a,$7F
        in a,($FE)
        rra
        jr c,is_go
        xor a
        ld (live),a
        im 1
        jr is_x
is_go:  ld a,(lastf)
        ld b,a
        ld a,(FRAMES)
        sub b
        cp 2
        jr c,is_x
        ld hl,busy
        ld (hl),1
        call pcalc
        call body
        xor a
        ld (busy),a
        ld a,(crash)
        or a
        jr z,is_x
        xor a
        ld (live),a
        im 1
is_x:   pop hl
        pop de
        pop bc
        pop af
        reti
busy:   defb 0

; ---- wait until 2 frames have passed since the last step --------------------
pace:   ld a,(lastf)
        ld b,a
pc_l:   ld a,(FRAMES)
        sub b
        cp 2
        jr nc,pc_ok
        halt
        jr pc_l
pcalc:
pc_ok:  cp 9                ; more than 8 frames behind: drop the rest
        jr c,pc_1
        ld a,(FRAMES)
        sub 8
        ld (lastf),a
        ld a,8
pc_1:   and $FE
        ld c,a              ; frames accounted for
        ld a,(lastf)
        add a,c
        ld (lastf),a
        ld a,c
        srl a               ; updates due (srl: the add may have set carry)
        ret
nup:    defb 0

; ---- 8-bit Galois LFSR --------------------------------------------------------
rnd:    ld a,(rng)
        srl a
        jr nc,rn1
        xor $B8
rn1:    ld (rng),a
        ret

; ---- keys: A bit 0 = jump (SPACE, Q, 7 / cursor up), bit 1 = duck (A, 6 / down)
keys:   ld e,0
        ld bc,$7FFE
        in a,(c)
        rra
        jr c,k1
        set 0,e
k1:     ld b,$FB
        in a,(c)
        rra
        jr c,k2
        set 0,e
k2:     ld b,$EF
        in a,(c)
        bit 3,a
        jr nz,k3
        set 0,e
k3:     bit 4,a
        jr nz,k4
        set 1,e
k4:     ld b,$FD
        in a,(c)
        rra
        jr c,k5
        set 1,e
k5:     ld a,e
        ret

; ---- the jump: 8.8 height and speed, Chrome-style variable height ------------
phys:   ld a,(air)
        or a
        jr nz,ph_air
        ld a,(kb)
        and 2
        ld (duck),a
        ret nz              ; ducking: no jump
        ld a,(kb)
        rra
        ret nc
        ld hl,V0            ; start a jump
        ld (vy),hl
        ld a,1
        ld (air),a
        xor a
        ld (endj),a
        ld a,(flags)
        or 8
        ld (flags),a
        jr ph_move
ph_air: ld a,(kb)
        bit 1,a
        jr z,ph_nsd
        ld hl,(vy)          ; duck in the air: drop fast
        ld de,-SDROP
        or a
        sbc hl,de
        jp m,ph_nsd
        ld hl,-SDROP
        ld (vy),hl
        ld a,1
        ld (endj),a
ph_nsd: ld a,(endj)
        or a
        jr nz,ph_move
        ld hl,(hgt)
        ld de,MAXH
        or a
        sbc hl,de
        jr nc,ph_end        ; as high as a held jump goes
        ld a,(kb)
        rra
        jr c,ph_move        ; still held
        ld hl,(hgt)
        ld de,MINH
        or a
        sbc hl,de
        jr c,ph_move        ; not yet at the lowest jump
ph_end: ld a,1
        ld (endj),a
        ld hl,(vy)
        ld de,DROPV
        or a
        sbc hl,de
        jp m,ph_move
        ld hl,DROPV
        ld (vy),hl
ph_move: ld hl,(hgt)
        ld de,(vy)
        add hl,de
        bit 7,h
        jr nz,ph_land
        ld (hgt),hl
        ld hl,(vy)
        ld de,-GRAV
        add hl,de
        ld (vy),hl
        ret
ph_land: ld hl,0
        ld (hgt),hl
        ld (vy),hl
        xor a
        ld (air),a
        ret

; ---- move the world -----------------------------------------------------------
world:  ld hl,(speed)
        ld a,(dist)
        add a,l
        ld (dist),a
        ld a,h
        adc a,0
        ld (px),a
        call updobjs
        ld hl,(gapc)
        ld a,(px)
        ld e,a
        ld d,0
        or a
        sbc hl,de
        ld (gapc),hl
        jp m,w_sp
        ld a,h
        or l
        jr z,w_sp
        ld de,LEAD          ; ask BASIC early, so its choice is ready in time
        or a
        sbc hl,de
        jp p,w_g
        jr w_req
w_sp:   call spawn          ; the gap is used up: the next one comes on
w_req:  ld a,(sptype)
        or a
        jr nz,w_g
        ld a,(flags)
        or 4
        ld (flags),a
w_g:    ld hl,(gscr)
        ld a,(px)
        ld e,a
        ld d,0
        add hl,de
        ld a,h
        and 1
        ld h,a
        ld (gscr),hl
        ld a,(px)
        ld b,a
        ld a,(sdist)
        add a,b
        cp 20
        jr c,w_s1
        sub 20
        ld (sdist),a
        ld hl,(score)
        inc hl
        ld a,h
        or l
        jr z,w_c
        ld (score),hl
        call drawscore
        ld a,(dgt+3)
        ld b,a
        ld a,(dgt+4)
        or b
        jr nz,w_c
        ld a,(flags)
        or 16
        ld (flags),a
        jr w_c
w_s1:   ld (sdist),a
w_c:    jp updclouds

updobjs: ld hl,objs
        ld b,NOBJ
uo_l:   ld a,(hl)
        or a
        jr z,uo_n
        push hl
        inc hl
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        push bc
        ld a,(px)
        ld c,a
        ld b,0
        or a
        sbc hl,bc
        pop bc
        ex de,hl
        ld (hl),d
        dec hl
        ld (hl),e
        push hl
        ld hl,40
        add hl,de
        bit 7,h
        pop hl
        jr z,uo_k
        dec hl
        dec hl
        ld (hl),0           ; gone off the left: free the slot
        inc hl
        inc hl
uo_k:   inc hl
        inc hl
        inc hl
        ld a,(tick)
        and 4
        ld (hl),a           ; wing frame, every 4 steps
        pop hl
uo_n:   ld de,6
        add hl,de
        djnz uo_l
        ret

; offset of field A (0-5) of type C's typetab entry -> HL
tfield: ld e,a
        ld a,c
        dec a
        add a,a
        add a,a
        add a,a
        add a,e
        ld e,a
        ld d,0
        ld hl,typetab
        add hl,de
        ret

spawn:  ld a,(sptype)
        or a
        ret z
        ld hl,objs
        ld b,NOBJ
sp_f:   ld a,(hl)
        or a
        jr z,sp_g
        ld de,6
        add hl,de
        djnz sp_f
        ret
sp_g:   ld a,(sptype)
        ld c,a
        ld (hl),a
        inc hl
        ld a,(spcnt)
        ld (hl),a
        ld (ocnt),a
        inc hl
        ld (hl),0           ; x = 256: just off the right edge
        inc hl
        ld (hl),1
        inc hl
        push hl
        ld a,c
        cp 3
        jr z,sp_pt
        ld a,7
        call tfield
        ld b,(hl)
        ld a,GY+2
        sub b
        jr sp_y
sp_pt:  ld a,(spy)
        ld e,a
        ld d,0
        ld hl,ptab
        add hl,de
        ld a,(hl)
sp_y:   pop hl
        ld (hl),a
        inc hl
        ld (hl),0
        ld a,6
        call tfield
        ld e,(hl)
        ld d,0
        ld hl,(spgap)
        ld a,(ocnt)
        ld b,a
sp_w:   add hl,de
        djnz sp_w
        ld (gapc),hl
        xor a
        ld (sptype),a
        ret

updclouds: ld hl,(speed)
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        ld a,(cfrac)
        add a,l
        ld (cfrac),a
        ld a,h
        adc a,0
        ld (cpx),a
        ld hl,clouds
        ld b,NCL
uc_l:   push hl
        inc hl
        inc hl
        ld a,(hl)
        or a
        pop hl
        jr z,uc_n
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        push bc
        ld a,(cpx)
        ld c,a
        ld b,0
        or a
        sbc hl,bc
        pop bc
        ex de,hl
        ld (hl),d
        dec hl
        ld (hl),e
        push hl
        ld hl,30
        add hl,de
        bit 7,h
        pop hl
        jr z,uc_n
        inc hl
        inc hl
        ld (hl),0
        dec hl
        dec hl
uc_n:   ld de,4
        add hl,de
        djnz uc_l
        ld a,(cpx)
        ld c,a
        ld a,(cgap)
        sub c
        jr c,uc_sp
        jr z,uc_sp
        ld (cgap),a
        ret
uc_sp:  ld hl,clouds+2
        ld b,NCL
uc_f:   ld a,(hl)
        or a
        jr z,uc_g
        inc hl
        inc hl
        inc hl
        inc hl
        djnz uc_f
        xor a
        ld (cgap),a
        ret
uc_g:   call rnd
        and 15
        add a,2
        ld (hl),a
        dec hl
        ld (hl),1
        dec hl
        ld (hl),0
        call rnd
        and 127
        add a,50
        ld (cgap),a
        ret

; ---- which dino frame ----------------------------------------------------------
seldino: ld a,(crash)
        or a
        ret nz
        ld a,(mode)
        or a
        jr nz,sd_p
        ld a,(tick)
        and 63
        cp 58
        ld hl,spr_stand
        jr c,sd_ok
        ld hl,spr_blink
        jr sd_ok
sd_p:   ld a,(air)
        or a
        ld hl,spr_stand
        jr nz,sd_ok
        ld a,(tick)
        and 2
        ld b,a
        ld a,(duck)
        or a
        jr z,sd_r
        ld hl,spr_duck1
        ld a,b
        or a
        jr z,sd_ok
        ld hl,spr_duck2
        jr sd_ok
sd_r:   ld hl,spr_run1
        ld a,b
        or a
        jr z,sd_ok
        ld hl,spr_run2
sd_ok:  ld (dspr),hl
        ret

; top line of the dino frame in dspr -> A
dinoy:  ld hl,(dspr)
        inc hl
        ld b,(hl)
        ld a,GY+2
        sub b
        ld b,a
        ld a,(hgt+1)
        ld c,a
        ld a,b
        sub c
        ret

; ---- draw a step ---------------------------------------------------------------
render: call drawground
        call drawobjs
        call dinoy
        ld (dy),a
        ld hl,(dspr)        ; its mask follows it: HL += 2 + w*h
        ld b,(hl)
        inc hl
        ld e,(hl)
        inc hl
        ld d,0
rd_m:   add hl,de
        djnz rd_m
        ld a,(dy)
        ld d,a
        ld bc,DINOBX
        call spr_tal
        or a
        jr z,rd_ok
        ld a,(mode)
        or a
        jr z,rd_ok
        ld a,1
        ld (crash),a
        ld a,(flags)
        or 1
        ld (flags),a
        ld hl,spr_dead
        ld (dspr),hl
        call dinoy
        ld (dy),a
rd_ok:  ld hl,(dspr)
        ld de,0             ; byte-aligned: spr_pre with one copy
        ld a,(dy)
        ld bc,DINOBX
        call spr_pre
        jp drawclouds       ; (shown at the start of the next step)

drawobjs: ld hl,objs
        ld b,NOBJ
do_l:   ld a,(hl)
        or a
        jr z,do_n
        push bc
        push hl
        ld (otype),a
        inc hl
        ld a,(hl)
        ld (ocnt),a
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)
        ld (oy),a
        inc hl
        ld a,(hl)
        ld (ofr),a
        ld hl,48
        add hl,de
        ld (obx),hl
        ld a,(otype)
        ld c,a
        xor a
        call tfield
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(ofr)
        or a
        jr z,do_f
        ld e,(hl)
        inc hl
        ld d,(hl)
        dec hl
do_f:   inc hl
        inc hl
        ld (ospr),de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (osz),de
        ld a,(hl)
        ld (owpx),a
do_k:   ld hl,(ospr)
        ld de,(osz)
        ld a,(oy)
        ld bc,(obx)
        call spr_pre
        ld hl,(obx)
        ld a,(owpx)
        ld e,a
        ld d,0
        add hl,de
        ld (obx),hl
        ld a,(ocnt)
        dec a
        ld (ocnt),a
        jr nz,do_k
        pop hl
        pop bc
do_n:   ld de,6
        add hl,de
        djnz do_l
        ret

drawclouds: ld hl,clouds
        ld b,NCL
dc_l:   push bc
        push hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)
        or a
        jr z,dc_n
        ld hl,48
        add hl,de
        ld b,h
        ld c,l
        ld hl,P_CLOUD
        ld de,SZ_cloud
        call spr_pre
dc_n:   pop hl
        ld de,4
        add hl,de
        pop bc
        djnz dc_l
        ret

drawground: ld a,GY-1
        ld (ry),a
        ld a,GROWS
        ld (rh),a
        ld a,6
        ld (rc0),a
        ld a,37
        ld (rc1),a
        call markrect
        ld hl,(gscr)
        ld a,l
        and 7
        add a,a
        ld e,a
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        push hl             ; byte offset 0-63
        ld d,0
        ld hl,gtab
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        pop hl
        add hl,de           ; source, row 0
        ld de,BUF+(GY-1)*BW+6
        ld b,GROWS
dg_r:   push bc
        call ldi32          ; written over, not ORed: drawn first, so these
        ld bc,96-32         ; lines never need clearing
        add hl,bc
        ex de,hl
        ld bc,BW-32
        add hl,bc
        ex de,hl
        pop bc
        djnz dg_r
        ret

; ---- buffer address: D = line, BC = bit x (0-351) -> HL, and the shift set ---
baddr:  ld a,d
        ld (ry),a
        ld a,c
        and 7
        ld (ss),a
        neg
        add a,7
        add a,a
        add a,a             ; jr offset: skip (7 - shift) shift pairs
        ld (sm1+1),a
        ld (sm2+1),a
        srl b
        rr c
        srl b
        rr c
        srl b
        rr c
        ld a,c
        ld (rc0),a
        ld l,d
        ld h,0
        add hl,hl
        add hl,hl
        ld d,h
        ld e,l              ; y*4
        add hl,hl
        push hl             ; y*8
        add hl,hl
        add hl,hl           ; y*32
        add hl,de
        pop de
        add hl,de           ; y*44
        add hl,bc
        ld de,BUF
        add hl,de
        ret

; ---- OR a sprite into the buffer: HL = sprite, D = top line, BC = bit x -------
spr_or: ld a,(hl)
        ld (sw),a
        inc hl
        ld a,(hl)
        ld (sh),a
        ld (rh),a
        inc hl
        push hl
        call baddr
        ex de,hl            ; DE = destination
        pop hl              ; HL = source
so_r:   push de
        ld a,(sw)
        ld b,a
so_b:   ld a,(hl)
        inc hl
        ld c,0
sm1:    jr so_s
so_s:   srl a
        rr c
        srl a
        rr c
        srl a
        rr c
        srl a
        rr c
        srl a
        rr c
        srl a
        rr c
        srl a
        rr c
        ex de,hl
        or (hl)
        ld (hl),a
        inc hl
        ld a,c
        or (hl)
        ld (hl),a
        ex de,hl
        djnz so_b
        pop de
        push hl
        ld hl,BW
        add hl,de
        ex de,hl
        pop hl
        ld a,(sh)
        dec a
        ld (sh),a
        jr nz,so_r
        ld a,(rc0)          ; w + 1 bytes were written on each line
        ld hl,sw
        add a,(hl)
        ld (rc1),a
        jp markrect

; ---- test a mask against the buffer: A = 0 clear, 1 = something there --------
spr_test: ld a,(hl)
        ld (sw),a
        inc hl
        ld a,(hl)
        ld (sh),a
        inc hl
        push hl
        call baddr
        ex de,hl
        pop hl
st_r:   push de
        ld a,(sw)
        ld b,a
st_b:   ld a,(hl)
        inc hl
        ld c,0
sm2:    jr st_s
st_s:   srl a
        rr c
        srl a
        rr c
        srl a
        rr c
        srl a
        rr c
        srl a
        rr c
        srl a
        rr c
        srl a
        rr c
        ex de,hl
        and (hl)
        jr nz,st_hit
        inc hl
        ld a,c
        and (hl)
        jr nz,st_hit
        ex de,hl
        djnz st_b
        pop de
        push hl
        ld hl,BW
        add hl,de
        ex de,hl
        pop hl
        ld a,(sh)
        dec a
        ld (sh),a
        jr nz,st_r
        xor a
        ret
st_hit: pop de
        ld a,1
        ret

; ---- test a byte-aligned mask: HL = mask, D = top line, BC = bit x; A = 0 or 1
spr_tal: ld a,(hl)
        ld (sw),a
        inc hl
        ld a,(hl)
        ld (sh),a
        inc hl
        push hl
        call baddr
        ex de,hl
        pop hl
ta_r:   ld a,(sw)
        ld b,a
ta_b:   ld a,(de)
        and (hl)
        jr nz,ta_hit
        inc hl
        inc de
        djnz ta_b
        ld a,(sw)
        cpl
        add a,BW+1
        add a,e
        ld e,a
        jr nc,ta_c
        inc d
ta_c:   ld a,(sh)
        dec a
        ld (sh),a
        jr nz,ta_r
        xor a
        ret
ta_hit: ld a,1
        ret

; ---- draw a pre-shifted sprite: HL = its 8 copies, DE = size of one, A = top
; line, BC = bit x. Picks copy (x AND 7) and ORs it in byte-aligned.
spr_pre: push af
        ld a,c
        and 7
        jr z,sp_0
sp_m:   add hl,de
        dec a
        jr nz,sp_m
sp_0:   pop af
        ld d,a
        ld a,(hl)
        ld (sw),a
        inc hl
        ld a,(hl)
        ld (sh),a
        ld (rh),a
        inc hl
        push hl
        call baddr
        ex de,hl
        pop hl
sa_r:   ld a,(sw)
        ld b,a
sa_b:   ld a,(de)
        or (hl)
        ld (de),a
        inc hl
        inc de
        djnz sa_b
        ld a,(sw)           ; DE += BW - w
        cpl
        add a,BW+1
        add a,e
        ld e,a
        jr nc,sa_c
        inc d
sa_c:   ld a,(sh)
        dec a
        ld (sh),a
        jr nz,sa_r
        ld a,(rc0)          ; w bytes on each line
        ld hl,sw
        add a,(hl)
        dec a
        ld (rc1),a
        jp markrect

; ---- make the 8 shifted copies of sprite HL at DE (each one byte wider) -----
mkshift: ld a,(hl)
        ld (sw),a
        inc hl
        ld a,(hl)
        ld (sh),a
        inc hl
        ld (msrc),hl
        xor a
        ld (ms),a
ms_s:   ld a,(sw)
        inc a
        ld (de),a
        inc de
        ld a,(sh)
        ld (de),a
        inc de
        ld (mrow),a
        ld hl,(msrc)
ms_r:   ld a,(sw)
        ld b,a
        ld c,0
ms_b:   ld a,(hl)
        inc hl
        push hl
        push bc
        ld h,a
        ld l,0
        ld a,(ms)
        or a
        jr z,ms_n
        ld b,a
ms_x:   srl h
        rr l
        djnz ms_x
ms_n:   pop bc
        ld a,h
        or c
        ld (de),a
        inc de
        ld c,l
        pop hl
        djnz ms_b
        ld a,c
        ld (de),a
        inc de
        ld a,(mrow)
        dec a
        ld (mrow),a
        jr nz,ms_r
        ld a,(ms)
        inc a
        ld (ms),a
        cp 8
        jr nz,ms_s
        ret

; ---- clear the buffer (stack pushes, interrupts off meanwhile) ----------------
clrbuf: ld (savsp),sp       ; interrupts stay on: one only writes below SP, into
                            ; bytes still to be cleared (or the spare RAM below BUF)
        ld sp,BUF+BW*BH
        ld hl,0
        ld a,BH
cb_l:   rept 22
        push hl
        endm
        dec a
        jr nz,cb_l
        ld sp,(savsp)
        ret

; ---- spans: per buffer line an 8-byte record at SPT --------------------------------
;   +0 +1  first and last column to show (this step's and last step's together)
;   +2 +3  first and last column drawn this step
;   +4 +5  the screen address of that line, column 0
;   +6 +7  the buffer address of that line
; widen this step's spans to cover lines ry..ry+rh-1, columns rc0..rc1
markrect: ld a,(ry)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,SPT
        add hl,de
        ld a,(rh)
        ld b,a
        ld de,5
        ld a,(rc0)
        ld c,a
mr_l:   ld a,c
        cp (hl)
        jr nc,mr_1
        ld (hl),a           ; show from
mr_1:   inc hl
        ld a,(rc1)
        cp (hl)
        jr c,mr_2
        ld (hl),a           ; show to
mr_2:   inc hl
        ld a,c
        cp (hl)
        jr nc,mr_3
        ld (hl),a           ; drawn from
mr_3:   inc hl
        ld a,(rc1)
        cp (hl)
        jr c,mr_4
        ld (hl),a           ; drawn to
mr_4:   add hl,de           ; next line's record
        djnz mr_l
        ret

; build the records: everything empty, addresses filled in
mkspans: ld hl,SPT
        ld de,BUF
        ld c,SCR0
        ld b,BH
mk_l:   ld (hl),255
        inc hl
        ld (hl),0
        inc hl
        ld (hl),255
        inc hl
        ld (hl),0
        inc hl
        push de
        ld a,c              ; screen address of line C
        ld e,a
        and 7
        or $40
        ld d,a
        ld a,e
        rra
        rra
        rra
        and $18
        or d
        ld d,a
        ld a,e
        rla
        rla
        and $E0
        ld (hl),a
        inc hl
        ld (hl),d
        inc hl
        pop de
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        push hl
        ld hl,BW
        add hl,de
        ex de,hl
        pop hl
        inc c
        djnz mk_l
        ret

; one pass over the lines: copy the show span (clipped to columns 6-37) to the
; screen, clear the buffer along it, and roll this step's span over to be the
; next step's show span
showspans: ld hl,SPT       ; pass 1, against the beam: copy each line's
        ld b,BH             ; show span (clipped to the screen), top down
sc_l:   ld a,(hl)           ; show from
        cp 255
        jr z,sc_n           ; nothing on this line, then or now
        cp 6                ; lo = max(from, 6)
        jr nc,sc_1
        ld a,6
sc_1:   ld c,a
        inc hl
        ld a,(hl)           ; hi = min(to, 37)
        cp 38
        jr c,sc_2
        ld a,37
sc_2:   sub c
        jr c,sc_off         ; all of it in the margins
        push bc
        inc a
        add a,a
        neg
        add a,ldi_end & 255
        ld (sc_jp+1),a
        ld a,ldi_end / 256 - 1   ; high byte: carry set means no borrow
        adc a,0
        ld (sc_jp+2),a
        inc hl
        inc hl
        inc hl
        ld a,c              ; DE = screen line + lo - 6
        sub 6
        or (hl)
        ld e,a
        inc hl
        ld d,(hl)
        inc hl
        ld a,c              ; HL = buffer line + lo
        add a,(hl)
        inc hl
        push hl
        ld h,(hl)
        ld l,a
        jr nc,sc_jp
        inc h
sc_jp:  call ldi_end
        pop hl
        pop bc
        inc hl
        djnz sc_l
        jr sc_clr
sc_off: ld de,7
        add hl,de
        djnz sc_l
        jr sc_clr
sc_n:   ld de,8
        add hl,de
        djnz sc_l
sc_clr: ld hl,SPT           ; pass 2, in its own time: clear what was shown
        ld b,BH             ; (unclipped), then show := drawn, drawn := empty
cl_l:   ld a,(hl)
        cp 255
        jr z,cl_e
        push bc
        push hl
        ld c,a
        inc hl
        ld b,(hl)
        ld de,5
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        add a,c
        ld l,a
        jr nc,cl_1
        inc h
cl_1:   ld a,b
        sub c
        inc a
        add a,a
        neg
        add a,clr_end & 255
        ld (cl_cj+1),a
        ld a,clr_end / 256 - 1
        adc a,0
        ld (cl_cj+2),a
        xor a
cl_cj:  call clr_end
        pop hl
        pop bc
cl_e:   inc hl
        inc hl
        ld a,(hl)           ; drawn from -> show from
        ld (hl),255
        dec hl
        dec hl
        ld (hl),a
        inc hl
        inc hl
        inc hl
        ld a,(hl)           ; drawn to -> show to
        ld (hl),0
        dec hl
        dec hl
        ld (hl),a
        ld de,7
        add hl,de
        djnz cl_l
        ret
ldi32:  rept 32             ; HL -> DE, 32 bytes; enter part way for fewer
        ldi
        endm
ldi_end: ret
clr_blk: rept 44
        ld (hl),a
        inc hl
        endm
clr_end: ret

; ---- the score, five digits at columns 58-62 of row 6, in the ROM's font -------
drawscore: ld hl,(score)
        ld de,dgt
        ld bc,10000
        call dg_1
        ld bc,1000
        call dg_1
        ld bc,100
        call dg_1
        ld bc,10
        call dg_1
        ld a,l
        ld (de),a
        ld c,0              ; glyph line 0-7
ds_l:   ld a,c
        add a,48            ; screen line (row 6) -> DE at byte 29 (column 58)
        ld e,a
        and 7
        or $40
        ld d,a
        ld a,e
        rra
        rra
        rra
        and $18
        or d
        ld d,a
        ld a,e
        rla
        rla
        and $E0
        or 29
        ld e,a
        ld hl,dgt
        call ds_g
        ld b,a
        call ds_g
        rrca
        rrca
        rrca
        rrca
        or b
        ld (de),a
        inc e
        call ds_g
        ld b,a
        call ds_g
        rrca
        rrca
        rrca
        rrca
        or b
        ld (de),a
        inc e
        call ds_g
        ld (de),a
        inc c
        ld a,c
        cp 8
        jr nz,ds_l
        ret
ds_g:   ld a,(hl)           ; line C of the glyph of digit (HL), HL++; top nibble
        inc hl
        push hl
        push de
        add a,a
        add a,a
        add a,a
        add a,c
        ld e,a
        ld d,0
        ld hl,digits
        add hl,de
        ld a,(hl)
        pop de
        pop hl
        ret
dg_1:   xor a               ; digit = HL DIV BC; HL = HL MOD BC
dg_2:   or a
        sbc hl,bc
        jr c,dg_3
        inc a
        jr dg_2
dg_3:   add hl,bc
        ld (de),a
        inc de
        ret

; ---- build the 8 pre-shifted ground strips (once) -----------------------------
bldg:   ld a,(gbuilt)
        or a
        ret nz
        inc a
        ld (gbuilt),a
        ld hl,gstrip
        ld de,GTMP
        ld bc,GROWS*64
        ldir
        ld hl,pretab
        ld b,5
bp_l:   push bc
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ex de,hl            ; HL = sprite, DE = where its copies go
        call mkshift
        pop hl
        inc hl
        inc hl
        pop bc
        djnz bp_l
        ld de,GSH
        ld hl,gtab
        ld b,8
bg_s:   ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        push bc
        push hl
        ld hl,GTMP
        ld b,GROWS
bg_r:   push bc
        push hl
        ld bc,64
        ldir
        pop hl
        push hl
        ld bc,32
        ldir
        pop hl
        push de             ; rotate this row left one pixel, round the loop
        ld d,h
        ld e,l
        ld bc,63
        add hl,bc           ; HL = last byte, DE = first
        ld a,(de)
        rla                 ; carry = the leftmost pixel
        ld b,64
bg_x:   rl (hl)
        dec hl
        djnz bg_x
        ld bc,65
        add hl,bc           ; next row
        pop de
        pop bc
        djnz bg_r
        pop hl
        pop bc
        djnz bg_s
        ret

        include "sprites.inc"
codeend:
        if RAMEND > IMJP
        .error "RAM areas run into the IM 2 table"
        endif
        if RAMEND > 65535
        .error "pre-shifted sprites do not fit"
        endif
        if codeend > BUF
        .error "code runs into the buffer"
        endif
