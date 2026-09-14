********************************************************************
* ca_tile.asm - tile screens, the exclusive screen, and the palette
* extensions
*
* A tile screen ($1C 640 x 200, $1D 640 x 240) is cell mode with nothing of
* CoArm's in it: the owner loads a tile bank and writes the map, through
* ArmIO's SS.TileLd and SS.MapWr or directly with libvid (vidxcl.asm).
* Displayed, TILEBASE is TL.TBank and MAPBASE TL.MBase.  CoArm keeps no copy
* of it, so a Select away and back shows whatever VRAM then holds: it is
* for programs that own the screen.  Text and drawing on it do nothing.
*
* SS.Excl claims the displayed screen for the calling process (plan 3.5):
* CoArm stops drawing on it and takes the pointer off, no Select happens
* until it is given back, and the VBL service keeps the tick, the batch and
* SS.Batch.  It is given back by SS.Excl Y = 0, by the screen going, or by
* the owner's death (ArmIO's XCheck).
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P3.

********************************************************************
* TlNew - A = $1C or $1D, X = a free screen record: the screen, and the
* device's window on all of it
TlNew               sta       SC.Type,x
                    suba      #STY.Tile25
                    sta       SC.VMode,x
                    ldb       #25
                    tsta
                    beq       r@
                    ldb       #30
r@                  stb       SC.Rows,x
                    lda       #80
                    sta       SC.Cols,x
                    ldd       #640
                    std       SC.W,x
                    lda       SC.Rows,x
                    ldb       #8
                    mul
                    std       SC.H,x
                    clra
                    clrb
                    std       SC.Top,x
                    clr       SC.StN,x
                    clr       SC.TTop,x
                    inc       SC.Used,x
                    lbsr      PalDef
                    lda       #1
                    sta       SC.Wins,x
                    ldu       >CoG+CG.Dev
                    lbsr      SIdx
                    stb       WT.Scr,u
                    lbsr      WIdx
                    stb       WT.Cur,u
                    lda       #$FF
                    sta       WT.Par,u
                    clra
                    clrb
                    std       WT.X,u
                    std       WT.Y,u
                    ldd       SC.W,x
                    std       WT.W,u
                    ldd       SC.H,x
                    std       WT.H,u
                    ldb       #5
                    lbsr      Prm
                    sta       WT.FG,u
                    ldb       #6
                    lbsr      Prm
                    sta       WT.BG,u
                    lbsr      WinInit
                    tst       >CoG+CG.Disp
                    bne       ok@
                    lbsr      Select
ok@                 clrb
                    rts

* TlShow - X = a tile screen being displayed (Select has turned the display
* off): the palette, the bases and scrolls, cell mode, and the display on
TlShow              pshs      d
                    lbsr      PalShow
                    lda       #TL.TBank
                    ldb       #TL.MBase
                    lbsr      VcQBank
                    ldd       #0
                    lbsr      VcQVScr
                    lbsr      VcQHScr
                    lda       SC.VMode,x
                    lbsr      VcVMode   a family change, written after VBLANK falls
                    ora       #CT.VIRQ+CT.Cell
                    pshs      a
                    lbsr      VcQCtrl
                    lbsr      CoYield   the palette takes sixteen blanks
                    puls      a
                    ora       #CT.Disp
                    lbsr      VcQCtrl
                    puls      d,pc

* Mute - X = a screen: Z set if CoArm draws nothing on it - a tile screen,
* or the exclusive screen.  A and B are kept.
Mute                pshs      d
                    lbsr      IsTile
                    beq       x@
                    lbsr      SIdx
                    incb
                    cmpb      VG.XScr,y
x@                  puls      d,pc

********************************************************************
* SS.Excl - VG.CY = 1: the displayed screen is the caller's (VG.CPID), and
* VG.CX := the card's base; 0: given back
DoExcl              ldd       VG.CY,y
                    beq       rel@
                    tst       VG.XScr,y
                    beq       c@
                    comb
                    ldb       #E$DevBsy
                    rts
c@                  lbsr      IsDisp
                    beq       d@
                    comb
                    ldb       #E$NotRdy
                    rts
d@                  lbsr      PtrOff
                    lda       VG.PtrOn,y
                    sta       VG.XPtr,y
                    clr       VG.PtrOn,y
                    lda       VG.CPID,y
                    sta       VG.XPID,y
                    lbsr      SIdx
                    incb
                    stb       VG.XScr,y
                    ldd       VG.Base,y
                    std       VG.CX,y
                    clrb
                    rts
rel@                tst       VG.XScr,y
                    beq       ok@
                    lda       VG.CPID,y
                    cmpa      VG.XPID,y
                    beq       r@
                    comb
                    ldb       #E$DevBsy
                    rts
r@                  bsr       XRelease
ok@                 clrb
                    rts

* XRelease - the exclusive screen given back: the pointer as it was.  B is
* kept.
XRelease            clr       VG.XScr,y
                    lda       VG.XPtr,y
                    sta       VG.PtrOn,y
                    inc       >CoG+CG.PtrHid drawn when the call ends, if there is one
                    rts

********************************************************************
* Pal565 PRN HI LO: an entry in RGB565
DoPal565            lbsr      NeedScr
                    ldb       #1
                    lbsr      PrmW
                    std       >CoG+CG.Tmp
                    ldb       #0
                    lbsr      Prm
                    tfr       a,b
                    bsr       PalSet
                    lbsr      IsDisp
                    bne       x@
                    lda       #1
                    lbsr      VcQPal
x@                  clrb
                    rts

* PalRange FIRST COUNT (HI LO) x COUNT: COUNT entries from FIRST, 0 is 256.
* The words follow as data: WT.Parms+2 is the next entry, +3 the bytes to
* come, +5 a high byte waiting for its low.
DoPalRng            lbsr      NeedScr
                    ldu       >CoG+CG.Dev
                    ldb       #0
                    lbsr      Prm
                    sta       WT.Parms+2,u
                    ldb       #1
                    lbsr      Prm
                    tfr       a,b
                    clra
                    tstb
                    bne       c@
                    inca
c@                  lslb
                    rola
                    std       WT.Parms+3,u
                    leax      PalData,pcr
                    stx       WT.EscVct,u
                    clrb
                    rts

* PalData - A = a byte of PalRange's words, U = the device window
PalData             pshs      a
                    ldd       WT.Parms+3,u an even count to come: a high byte
                    bitb      #1
                    puls      a
                    bne       lo@
                    sta       WT.Parms+5,u
                    bra       n@
lo@                 tfr       a,b
                    lda       WT.Parms+5,u
                    std       >CoG+CG.Tmp
                    pshs      u
                    lbsr      CurQ
                    cmpx      #0
                    beq       q@
                    ldu       >CoG+CG.Dev
                    ldb       WT.Parms+2,u
                    inc       WT.Parms+2,u
                    bsr       PalSet
                    lbsr      IsDisp
                    bne       q@
                    lda       #1
                    lbsr      VcQPal
q@                  puls      u
n@                  ldd       WT.Parms+3,u
                    subd      #1
                    std       WT.Parms+3,u
                    bne       x@
                    clr       WT.EscVct,u
                    clr       WT.EscVct+1,u
x@                  clrb
                    rts

* PalSet - X = a screen, B = an entry, CG.Tmp = its RGB565: the screen's
* palette, and the displayed one if it is displayed.  D is kept.
PalSet              pshs      d,u
                    clra
                    lslb
                    rola
                    leau      d,x
                    ldd       >CoG+CG.Tmp
                    std       SC.Pal,u
                    lbsr      IsDisp
                    bne       x@
                    clra
                    ldb       1,s
                    lslb
                    rola
                    leau      d,y
                    ldd       >CoG+CG.Tmp
                    std       VG.Pal,u
x@                  puls      d,u,pc
