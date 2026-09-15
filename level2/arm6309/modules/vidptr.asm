********************************************************************
* vidptr.asm - the graphics pointer, on the displayed bitmap screen
*
* `use`d by CoArm and by ArmIO: both draw it, with the card's rules
* (vidcore.asm), from VG, which both maps see.  The card has no sprites, so
* the pointer is drawn into VRAM: the pixels under the arrow's row runs are
* read back and kept (graphics.md 11), and the arrow is written over the
* same run in direct mode, a row at a time with /IRQ masked.  Moving it
* puts the runs back and draws it again.
*
*   CoArm moves it for PutGC and takes it off while its drawing covers it
*   (ca_row.asm's PtrGuard, CG.PtrHid), putting it back when the call ends.
*   ArmIO moves it for the mouse: KbdArm's /IRQ service only records where
*   it is to be, and the kernel's idle loop calls ArmIO's PtrIdle, which
*   moves it with IRQs enabled - unless a CoArm call is in progress
*   (VG.CBusy), whose end does it.
*
* GCSet chooses whether there is a pointer.  Which one is not modelled: any
* group but 0 is the arrow.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P2.  The runs, and the arrow composed in the stream, after
* P3: a move was 15.6 ms of VDATA traffic with the whole box and sprite layers.

* The arrow (the demo's: software/demo/tools/show.py cursor_masks) as the
* pixels of each row's run from its left edge: $00 the outline in colour 0,
* $01 the fill in colour 1, $FF what is under it.  Only the runs are saved
* and put back - 106 pixels of the 256 in the box - and the arrow is written
* over the saved run in the same stream, direct, a row a masked stretch.
PtrRun              fcb       1,2,3,4,5,6,7,8,9,10,11,7,8,8,9,8

PtrArt              fcb       $00
                    fcb       $00,$00
                    fcb       $00,$01,$00
                    fcb       $00,$01,$01,$00
                    fcb       $00,$01,$01,$01,$00
                    fcb       $00,$01,$01,$01,$01,$00
                    fcb       $00,$01,$01,$01,$01,$01,$00
                    fcb       $00,$01,$01,$01,$01,$01,$01,$00
                    fcb       $00,$01,$01,$01,$01,$01,$01,$01,$00
                    fcb       $00,$01,$01,$01,$01,$01,$01,$01,$01,$00
                    fcb       $00,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00
                    fcb       $00,$01,$01,$00,$01,$01,$00
                    fcb       $00,$01,$00,$FF,$00,$01,$01,$00
                    fcb       $00,$00,$FF,$FF,$00,$01,$01,$00
                    fcb       $00,$FF,$FF,$FF,$FF,$00,$01,$01,$00
                    fcb       $FF,$FF,$FF,$FF,$FF,$00,$00,$00

* PtrStart - direct mode and WADV 00 (with /IRQ masked a moment), and D := the
* WPTR bytes of the pointer's first row: A bits 18-16, B bits 15-8.  U := the
* card.
PtrStart            pshs      cc
                    orcc      #IRQMask
                    lbsr      VcWait
                    lda       #WM.Direct
                    lbsr      VcMode
                    clra
                    lbsr      VcAdv
                    puls      cc
                    ldu       VG.Base,y
                    ldd       VG.PtrDY,y the ring row << 10 ...
                    addd      VG.DTop,y
                    anda      #1
                    lslb
                    rola
                    lslb
                    rola
                    orb       VG.PtrDX,y ... and the column's bits 9-8
                    rts

* PtrLoad (masked) - WPTR := this row: the caller's run count at 3,s and the
* row's bits 18-16 and 15-8 at 4,s and 5,s (under the return).  A card busy
* with a span or a list is waited out, and the modes set again after.
PtrLoad             lda       VR.VSTAT,u
                    bita      #VSTAT.Busy+VSTAT.LRun
                    bne       s@
                    tst       VG.LArm,y a list armed in the blank owns WPTR too
                    beq       k@
s@                  lbsr      VcWait
                    lda       #WM.Direct
                    lbsr      VcMode
                    clra
                    lbsr      VcAdv
k@                  lda       VG.PtrDX+1,y
                    sta       VR.WPTR0,u little-endian (V3)
                    lda       5,s
                    sta       VR.WPTR1,u
                    lda       4,s
                    sta       VR.WPTR2,u
                    rts

* PtrRunB - B := the run of row VG.PtrI, or 0 past the last row
PtrRunB             lda       VG.PtrI,y
                    cmpa      VG.PtrH,y
                    bhs       n@
                    pshs      x
                    leax      PtrRun,pcr
                    ldb       a,x
                    puls      x,pc
n@                  clrb
                    rts

* PtrErase - the pixels under the pointer back, if it is drawn
PtrErase            tst       VG.PtrVis,y
                    beq       x@
                    pshs      d,x,u
                    clr       VG.PtrVis,y
                    bsr       PtrStart
                    pshs      d         the row 0,s
                    leax      VG.PtrSave,y
                    clr       VG.PtrI,y
r@                  bsr       PtrRunB
                    tstb
                    beq       d@
                    pshs      cc,b      cc 0,s  run 1,s  row 2,s
                    orcc      #IRQMask
                    bsr       PtrLoad
                    ldb       1,s
w@                  lda       ,x+
                    sta       VR.VDATA,u
                    decb
                    bne       w@
                    puls      cc,b
                    inc       VG.PtrI,y
                    ldd       ,s        the next ring row: + 1024
                    addb      #4
                    adca      #0
                    anda      #7
                    std       ,s
                    bra       r@
d@                  leas      2,s
                    puls      d,x,u
x@                  rts

* PtrDraw - the pointer at (PtrX, PtrY), if there is one, a bitmap screen
* is displayed, and it is not drawn already
PtrDraw             tst       VG.PtrOn,y
                    lbeq      x@
                    tst       VG.DBit,y
                    lbeq      x@
                    tst       VG.PtrVis,y
                    lbne      x@
                    pshs      d,x,u
                    ldd       VG.PtrX,y
                    std       VG.PtrDX,y
                    ldd       VG.PtrY,y
                    std       VG.PtrDY,y
                    ldd       VG.DH,y   the rows on the screen: up to 16
                    subd      VG.PtrDY,y
                    lbls      n@
                    cmpd      #16
                    bls       h@
                    ldb       #16
h@                  stb       VG.PtrH,y
                    lbsr      PtrStart
                    pshs      d         the row 0,s
                    leax      PtrArt,pcr the art, in VG.PtrCX
                    stx       VG.PtrCX,y
                    leax      VG.PtrSave,y
                    clr       VG.PtrI,y
r@                  lbsr      PtrRunB
                    tstb
                    beq       a@
                    pshs      cc,b      cc 0,s  run 1,s  row 2,s
                    orcc      #IRQMask
                    lbsr      PtrLoad
                    ldb       1,s
g@                  lda       VR.VDATA,u what is there, saved (a read steps WPTR, V10)
                    sta       ,x+
                    decb
                    bne       g@
                    lbsr      PtrLoad   and the arrow over it
                    ldd       VG.PtrCX,y
                    pshs      d,y       art 0,s  VG 2,s  cc 4,s  run 5,s
                    tfr       x,d       Y := the run's first saved byte
                    subb      5,s
                    sbca      #0
                    tfr       d,y
                    puls      x
                    ldb       3,s
p@                  lda       ,x+
                    cmpa      #$FF
                    bne       o@
                    lda       ,y
o@                  leay      1,y
                    sta       VR.VDATA,u
                    decb
                    bne       p@
                    tfr       x,d       the art moves on; X := past the saved run
                    tfr       y,x
                    puls      y
                    std       VG.PtrCX,y
                    puls      cc,b
                    inc       VG.PtrI,y
                    ldd       ,s
                    addb      #4
                    adca      #0
                    anda      #7
                    std       ,s
                    bra       r@
a@                  leas      2,s
                    inc       VG.PtrVis,y
n@                  puls      d,x,u
x@                  rts

* PtrMove - the pointer to (PtrX, PtrY): taken off where it was, and drawn
PtrMove             tst       VG.PtrVis,y
                    beq       d@
                    pshs      d
                    ldd       VG.PtrX,y
                    cmpd      VG.PtrDX,y
                    bne       m@
                    ldd       VG.PtrY,y
                    cmpd      VG.PtrDY,y
                    beq       s@
m@                  puls      d
                    lbsr      PtrErase
d@                  lbra      PtrDraw
s@                  puls      d,pc
