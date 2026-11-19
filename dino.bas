' =============================================================
' DINO RUN - a T-Rex runner for OpticOS (ROM v1.0.3)
' After the Chrome browser's offline dinosaur game.
' OpticBASIC runs the game: the title, which obstacle comes
' next and how far away, the speed, the score and HI score,
' sounds, game over and restart. The machine-code block
' "dinocode" (46900 on, source dino.asm) does the work of each
' step: the jump and duck, moving and drawing the cacti, birds,
' clouds and ground, the collision test, the score and its
' blink, the speed ramp, and night with its moon and stars.
'
'   CALL 48000      new game: the dino standing on the ground
'   r% = USR 48003  one step (2 frames): 0, or bits 1 crashed,
'                   4 ready for the next obstacle, 8 a jump
'                   began, 16 the score reached a hundred.
'                   The title screen uses this.
'   CALL 48022      play: from now on the frame interrupt
'                   does the steps itself (IM 2), and ORs
'                   those bits into 48021 for BASIC to read
'                   The code draws the score; BASIC the HI.
'   CALL 48006      game over: GAME OVER and the restart icon
'   CALL 48027      wait for a restart key (after 0.75 s)
'   Event bits also: 32 night fell or day broke (border)
' Bytes BASIC POKEs:
'   48009 1 = play, 0 = title     48010-48011 "DR": loaded
'   48012-48013 speed, 1/256 pixel a step (DPOKE)
'   48014-48015 the score (DPEEK)
'   48016 next obstacle: 1 small cacti, 2 large, 3 bird
'   48017 cacti in the group (1-3)   48018 bird height (0-2)
'   48019-48020 the gap after it, in pixels (DPOKE)
'   48021 events not yet seen   48025 1 while it runs
'   48026 1 once the dino has crashed   48030 1 at night
' =============================================================
CLEAR 46899
IF PEEK(48010) <> 68 OR PEEK(48011) <> 82 THEN LOAD "dinocode" CODE
RANDOMIZE
hi = 0
title
REPEAT
  play
  game_over
UNTIL FALSE
'
DEF PROC start
  ' Saved with AUTO start: RUN begins at the top, where CLEAR
  ' can be used (not inside a PROC).
  RUN
ENDPROC
'
DEF FN five$(n) = RIGHT$("0000" + STR$(n), 5)
'
DEF PROC scores
  ' HI in the top right once there is one (the code draws the
  ' score itself, beside it)
  IF hi > 0 THEN PRINT AT 6, 49; "HI "; five$(hi);
ENDPROC
'
DEF PROC title
  LOCAL r%
  BORDER 7: PAPER 7: INK 0: BRIGHT 1: CLS
  POKE 48009, 0
  CALL 48000
  PRINT AT 1, 24; "D I N O    R U N";
  PRINT AT 3, 17; "After the Chrome offline dinosaur game";
  PRINT AT 20, 22; "Press SPACE to start";
  PRINT AT 21, 9; "SPACE, Q or 7 (cursor up) jump    A or 6 (down) duck";
  PRINT AT 23, 15; "(c) 2026 Optica Technology Design";
  scores
  REPEAT
    r% = USR 48003
  UNTIL KEY(" ") OR KEY("q") OR KEY("7")
ENDPROC
'
DEF PROC play
  ' One game. CALL 48022 hands the steps to the frame
  ' interrupt: the code moves and draws everything 25 times a
  ' second by itself, and leaves what happened in 48021. BASIC
  ' answers in its own time: a beep for a jump or a hundred
  ' points, and the choice of each obstacle (the code asks
  ' early, so the answer is always ready when it is due).
  LOCAL r%, sp%, last%, same%
  BORDER 7: PAPER 7: INK 0: CLS
  DPOKE 48012, 1843
  POKE 48009, 1
  CALL 48000
  scores
  last% = 0: same% = 0
  CALL 48022
  REPEAT
    r% = PEEK(48021)
    IF r%
      POKE 48021, 0
      IF r% AND 8 THEN BEEP 0.012, 45
      IF r% AND 16 THEN BEEP 0.02, 57: BEEP 0.03, 57
      IF r% AND 4
        IF PEEK(48016) = 0 THEN obstacle
      ENDIF
      IF r% AND 32
        IF PEEK(48030) THEN BORDER 0 ELSE BORDER 7
      ENDIF
    ENDIF
  UNTIL PEEK(48026)
ENDPROC
'
DEF PROC obstacle
  ' Choose the next obstacle as the original does: any type the
  ' speed allows, but never three of a kind in a row. Speed
  ' rises with the score, from 7.2 to 15.6 pixels a step (the
  ' code keeps it up to date from its table).
  ' Groups of large cacti only above 8.4, birds above 10.2.
  ' The gap to the next one grows with the speed.
  LOCAL t%, n%, w%, g%
  sp% = DPEEK(48012)
  REPEAT
    t% = RND(3)
  UNTIL (t% < 3 OR sp% >= 2611) AND NOT (t% = last% AND same% >= 2)
  IF t% = last% THEN same% = same% + 1 ELSE same% = 1
  last% = t%
  n% = 1
  IF t% = 1 THEN n% = RND(3)
  IF t% = 2 AND sp% > 2150 THEN n% = RND(3)
  CASE t% OF
    WHEN 1: w% = 8 * n%: g% = 36
    WHEN 2: w% = 12 * n%: g% = 36
    OTHERWISE: w% = 23: g% = 45
  ENDCASE
  g% = w% * (sp% >> 5) DIV 10 + g%
  DPOKE 48019, g% + RND(g% >> 1)
  POKE 48017, n%
  POKE 48018, RND(3) - 1
  POKE 48016, t%
ENDPROC
'
DEF PROC game_over
  ' The code draws GAME OVER and the restart icon over the
  ' scene; BASIC adds the HI score, in night colours if it is
  ' night, and waits for a key.
  LOCAL s
  CALL 48006
  BEEP 0.03, 7: BEEP 0.07, 0
  s = DPEEK(48014)
  IF s > hi THEN hi = s
  IF PEEK(48030) THEN INK 7: PAPER 0 ELSE INK 0: PAPER 7
  scores
  INK 0: PAPER 7
  CALL 48027
ENDPROC
