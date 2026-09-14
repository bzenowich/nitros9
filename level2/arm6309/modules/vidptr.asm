********************************************************************
* vidptr.asm - the graphics pointer, on the displayed bitmap screen
*
* `use`d by CoArm and by ArmIO: both draw it, with the card's rules
* (vidcore.asm), from VG, which both maps see.  The card has no sprites, so
* the pointer is drawn into VRAM: the 16 x 16 pixels under it are read
* back and kept (graphics.md 11), and the arrow is two 1bpp layers in sprite
* mode (features.md 8.4) - the outline in colour 0 and the fill in colour 1,
* which are black and white in the demo desktop's palette.  Moving it puts
* the pixels back and draws it again.
*
*   CoArm moves it for PutGC and takes it off while its drawing covers it
*   (ca_row.asm's PtrGuard, CG.PtrHid), putting it back when the call ends.
*   ArmIO moves it for the mouse: KbdArm's /IRQ service only records where
*   it is to be, and the kernel's idle loop calls ArmIO's PtrIdle, which
*   moves it with IRQs enabled - unless a CoArm call is in progress
*   (VG.CBusy), whose end does it.  A move is ~15 ms of VDATA traffic, and
*   the 16C550's FIFO covers ~1.4 ms at 115.2 kbaud.
*
* GCSet chooses whether there is a pointer.  Which one is not modelled: any
* group but 0 is the arrow.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P2.

* The arrow (the demo's: software/demo/tools/show.py cursor_masks), each
* layer as two columns of 16 rows, MSB leftmost
PtrOl               fcb       $80,$C0,$A0,$90,$88,$84,$82,$81,$80,$80,$83,$92,$A9,$C9,$84,$07
                    fcb       $00,$00,$00,$00,$00,$00,$00,$00,$80,$40,$E0,$00,$00,$00,$80,$00

PtrFl               fcb       $00,$00,$40,$60,$70,$78,$7C,$7E,$7F,$7F,$7C,$6C,$46,$06,$03,$00
                    fcb       $00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$00,$00,$00

* PtrRow - A = a row of the pointer: WPTR := the ring row DTop + DY + A,
* at column PtrCX.  (masked)
PtrRow              pshs      d,x
                    tfr       a,b
                    clra
                    addd      VG.PtrDY,y
                    addd      VG.DTop,y
                    anda      #1
                    lslb
                    rola
                    lslb
                    rola
                    orb       VG.PtrCX,y
                    pshs      a
                    tfr       b,a
                    ldb       VG.PtrCX+1,y
                    tfr       d,x
                    puls      b
                    lbsr      VcPtr
                    puls      d,x,pc

* PtrErase - the pixels under the pointer back, if it is drawn
PtrErase            tst       VG.PtrVis,y
                    beq       x@
                    pshs      d,x,u
                    clr       VG.PtrVis,y
                    ldd       VG.PtrDX,y
                    std       VG.PtrCX,y
                    leau      VG.PtrSave,y
                    clr       VG.PtrI,y the row
r@                  lda       VG.PtrI,y
                    cmpa      VG.PtrH,y
                    bhs       d@
                    pshs      cc
                    orcc      #IRQMask
                    lbsr      VcWait
                    lda       #WM.Direct
                    lbsr      VcMode
                    clra
                    lbsr      VcAdv
                    lda       VG.PtrI,y
                    bsr       PtrRow
                    puls      cc
                    tfr       u,x
                    ldd       #16
                    lbsr      VcPutN
                    leau      16,u
                    inc       VG.PtrI,y
                    bra       r@
d@                  puls      d,x,u
x@                  rts

* PtrDraw - the pointer at (PtrX, PtrY), if there is one, a bitmap screen
* is displayed, and it is not drawn already
PtrDraw             tst       VG.PtrOn,y
                    lbeq      x@
                    tst       VG.DBit,y
                    beq       x@
                    tst       VG.PtrVis,y
                    bne       x@
                    pshs      d,x,u
                    ldd       VG.PtrX,y
                    std       VG.PtrDX,y
                    std       VG.PtrCX,y
                    ldd       VG.PtrY,y
                    std       VG.PtrDY,y
                    ldd       VG.DH,y   the rows on the screen: up to 16
                    subd      VG.PtrDY,y
                    lbls      n@
                    cmpd      #16
                    bls       h@
                    ldb       #16
h@                  stb       VG.PtrH,y
                    leau      VG.PtrSave,y what is under it
                    clr       VG.PtrI,y
r@                  lda       VG.PtrI,y
                    cmpa      VG.PtrH,y
                    bhs       a@
                    pshs      cc
                    orcc      #IRQMask
                    lbsr      VcWait
                    lda       VG.PtrI,y
                    lbsr      PtrRow
                    puls      cc
                    tfr       u,x
                    ldd       #16
                    lbsr      VcGetN
                    leau      16,u
                    inc       VG.PtrI,y
                    bra       r@
a@                  leax      PtrOl,pcr the outline, then the fill: two columns each
                    clra                colour 0
                    bsr       Layer
                    leax      PtrFl,pcr
                    lda       #1
                    bsr       Layer
                    inc       VG.PtrVis,y
n@                  puls      d,x,u
x@                  rts

* Layer - X = a layer's two columns, A = its colour: sprite mode, one WPTR
* load a column and a write a row (WADV 01)
Layer               pshs      d,x
                    ldd       VG.PtrDX,y
                    std       VG.PtrCX,y
                    clr       VG.PtrI,y the column
c@                  pshs      cc
                    orcc      #IRQMask
                    lbsr      VcWait
                    lda       #WM.Sprite
                    lbsr      VcMode
                    lda       #1
                    lbsr      VcAdv
                    lda       1,s       the colour
                    lbsr      VcFG
                    clra
                    lbsr      PtrRow
                    puls      cc
                    ldx       2,s       this column's bytes
                    clra
                    ldb       VG.PtrH,y
                    lbsr      VcPutN
                    ldx       2,s       the next column's
                    leax      16,x
                    stx       2,s
                    ldd       VG.PtrCX,y
                    addd      #8
                    std       VG.PtrCX,y
                    inc       VG.PtrI,y
                    lda       VG.PtrI,y
                    cmpa      #2
                    blo       c@
                    puls      d,x,pc

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
