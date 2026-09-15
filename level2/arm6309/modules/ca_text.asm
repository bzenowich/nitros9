********************************************************************
* ca_text.asm - CoArm's fast-text screens (types $18, $19)
*
* Cell mode (graphics.md 6.4.8): one map write a character.  The font is
* baked into tile bank TX.TBank in the screen's one colour pair - codes
* $00-$7F are the glyphs, $80-$FF the same glyphs inverted, for reverse
* video and the cursor - and a line feed at the bottom row is VSCROLL += 8
* in the next blank.  The screen keeps a shadow of its codes, by ring row,
* in one block of its own mapped at Co.WinA; a screen that is not displayed
* is drawn in the shadow only, and Select repaints the map from it.
*
* A fast-text screen has one window, its device's, covering it.  These
* routines take X = the screen, and the window from CG.WPtr (ca_bmtx.asm's
* shims set it); U is theirs to use.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P1; P2 moved the shadow into a block and the cursor into the
* window.

* TxNew - X = a free screen record, A = STY ($18 or $19)
TxNew               sta       SC.Type,x
                    suba      #STY.Txt25
                    sta       SC.VMode,x
                    ldb       #25
                    tsta
                    beq       r@
                    ldb       #30
r@                  stb       SC.Rows,x
                    lda       #SH.Cols
                    sta       SC.Cols,x
                    ldd       #640
                    std       SC.W,x
                    lda       SC.Rows,x
                    ldb       #8
                    mul
                    std       SC.H,x
                    clr       SC.TTop,x
                    ldb       #1        the shadow's block
                    stb       SC.StN,x
                    lbsr      CoAlloc
                    lbcs      x@
                    std       SC.StBlk,x
                    lbsr      MapA
                    ldu       #Co.WinA  all spaces
                    ldd       #SH.Rows*SH.Cols
                    pshs      d
s@                  lda       #C$SPAC
                    sta       ,u+
                    ldd       ,s
                    subd      #1
                    std       ,s
                    bne       s@
                    leas      2,s
                    inc       SC.Used,x
                    lbsr      PalDef
                    ldb       #5
                    lbsr      Prm
                    sta       SC.TFG,x
                    ldb       #6
                    lbsr      Prm
                    sta       SC.TBG,x
                    lda       #1
                    sta       SC.Wins,x
                    ldu       >CoG+CG.Dev the device's window is the whole screen
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
                    lda       SC.TFG,x
                    sta       WT.FG,u
                    lda       SC.TBG,x
                    sta       WT.BG,u
                    lbsr      WinInit
                    tst       >CoG+CG.Disp
                    bne       ok@
                    lbsr      Select
ok@                 clrb
x@                  rts

* TxRing - A = a screen row: A := its ring row, (TTop + A) mod 32
TxRing              adda      SC.TTop,x
                    anda      #SH.Rows-1
                    rts

* TxShad - A = ring row, B = column: U := that cell in the shadow (mapped).
* D is lost.
TxShad              pshs      b
                    pshs      a
                    ldd       SC.StBlk,x
                    lbsr      MapA
                    puls      a
                    ldb       #SH.Cols
                    mul
                    addb      ,s+
                    adca      #0
                    addd      #Co.WinA
                    tfr       d,u
                    rts

* TxWr - the card only, and only if the screen is displayed: CG.TxN codes
* from U to ring row A, column B.  A, B, X and U are kept.
TxWr                lbsr      IsDisp
                    bne       x@
                    pshs      d,x,u
                    pshs      cc
                    orcc      #IRQMask
                    lbsr      VcWait
                    bcs       e@
                    lda       #WM.Direct
                    lbsr      VcMode
                    clra
                    lbsr      VcAdv
                    lda       1,s       the ring row
                    clrb                the map is TX.MBase: row * 128 + column
                    lsra
                    rorb
                    addb      2,s
                    tfr       d,x
                    clrb
                    lbsr      VcPtr
                    puls      cc
                    ldx       4,s       the codes
                    clra
                    ldb       >CoG+CG.TxN
                    lbsr      VcPutN
                    puls      d,x,u,pc
e@                  puls      cc
                    puls      d,x,u
x@                  rts

* TxCells - screen row A from column B to the end of the row: shadow to the
* card.  A, B and X are kept.
TxCells             pshs      d,u
                    bsr       TxRing
                    pshs      a         the ring row, over the screen row and column
                    ldb       2,s
                    lbsr      TxShad
                    lda       SC.Cols,x
                    suba      2,s
                    sta       >CoG+CG.TxN
                    lda       ,s+
                    ldb       1,s
                    bsr       TxWr
                    puls      d,u,pc

* TxClrRow - screen row A from column B: spaces, in the shadow and on the
* card.  A, B and X are kept.
TxClrRow            pshs      d,u
                    bsr       TxRing
                    lbsr      TxShad
                    lda       SC.Cols,x
                    suba      1,s
                    beq       n@
                    pshs      a
                    lda       #C$SPAC
c@                  sta       ,u+
                    dec       ,s
                    bne       c@
                    leas      1,s
n@                  ldd       ,s
                    bsr       TxCells
                    puls      d,u,pc

* TxRowCopy - screen row A := screen row B, in the shadow and on the card.
* The shadow is one block, so both rows are in the window at once.
TxRowCopy           pshs      d,u
                    lda       1,s       the source
                    lbsr      TxRing
                    clrb
                    lbsr      TxShad
                    pshs      u
                    lda       2,s       the destination
                    lbsr      TxRing
                    clrb
                    lbsr      TxShad
                    puls      d         D = the source's cells
                    pshs      x
                    tfr       d,x
                    ldb       #SH.Cols
c@                  lda       ,x+
                    sta       ,u+
                    decb
                    bne       c@
                    puls      x
                    ldd       ,s
                    clrb
                    bsr       TxCells
                    puls      d,u,pc

* TxPut - A = a printable byte, at the cursor, which then moves on
TxPut               anda      #$7F      128 glyphs: $80-$FF are their inverses
                    ldu       >CoG+CG.WPtr
                    ldb       WT.Attr,u
                    bitb      #WA.Rev
                    beq       n@
                    ora       #$80
n@                  pshs      a
                    lda       WT.Attr,u the cursor's cell is being written over
                    anda      #^WA.CurOn
                    sta       WT.Attr,u
                    lda       WT.CY,u
                    lbsr      TxRing
                    ldb       WT.CX,u
                    pshs      d
                    lbsr      TxShad
                    lda       2,s
                    sta       ,u
                    lda       #1
                    sta       >CoG+CG.TxN
                    puls      d
                    lbsr      TxWr
                    leas      1,s
                    ldu       >CoG+CG.WPtr
                    inc       WT.CX,u
                    lda       WT.CX,u
                    cmpa      SC.Cols,x
                    blo       k@
                    clr       WT.CX,u
                    bsr       TxLF
k@                  lbra      TxShowOK

* TxLF - down a row, or scroll the screen up by one
TxLF                ldu       >CoG+CG.WPtr
                    lda       WT.CY,u
                    inca
                    cmpa      SC.Rows,x
                    bhs       TxScroll
                    sta       WT.CY,u
                    rts

* TxScroll - graphics.md 6.4.8: the ring's next row becomes the bottom
* line, cleared, and VSCROLL moves down a cell in the next blank
TxScroll            lda       SC.TTop,x
                    inca
                    anda      #SH.Rows-1
                    sta       SC.TTop,x
                    lda       SC.Rows,x
                    deca
                    clrb
                    lbsr      TxClrRow
                    lbsr      IsDisp
                    bne       x@
                    lda       SC.TTop,x VSCROLL = TTop * 8
                    ldb       #8
                    mul
                    lbsr      VcQVScr
x@                  rts

* TxInsLn - a blank line at the cursor's row; the rows below move down
TxInsLn             ldu       >CoG+CG.WPtr
                    lda       SC.Rows,x
                    deca
i@                  cmpa      WT.CY,u
                    bls       c@
                    tfr       a,b
                    decb
                    pshs      u
                    lbsr      TxRowCopy
                    puls      u
                    deca
                    bra       i@
c@                  lda       WT.CY,u
                    clrb
                    lbra      TxClrRow

* TxDelLn - the cursor's row goes; the rows below move up
TxDelLn             ldu       >CoG+CG.WPtr
                    lda       WT.CY,u
d@                  inca
                    cmpa      SC.Rows,x
                    bhs       c@
                    tfr       a,b
                    deca
                    lbsr      TxRowCopy
                    inca
                    bra       d@
c@                  lda       SC.Rows,x
                    deca
                    clrb
                    lbra      TxClrRow

* TxCurOff - take the cursor off the card, if it is on it
TxCurOff            pshs      d,u
                    ldu       >CoG+CG.WPtr
                    lda       WT.Attr,u
                    bita      #WA.CurOn
                    beq       x@
                    anda      #^WA.CurOn
                    sta       WT.Attr,u
                    lda       WT.CY,u
                    lbsr      TxRing
                    ldb       WT.CX,u
                    pshs      d
                    lbsr      TxShad
                    lda       #1
                    sta       >CoG+CG.TxN
                    puls      d
                    lbsr      TxWr
x@                  puls      d,u,pc

* TxShowOK - the cursor back on, and no error
TxShowOK            bsr       TxCurOn
                    clrb
                    rts

* TxCurOn - the cursor's cell, inverted, if the cursor is enabled, the
* screen displayed, and its device the one with the keyboard
TxCurOn             pshs      d,u
                    ldu       >CoG+CG.WPtr
                    lda       WT.Attr,u
                    bita      #WA.Cur
                    beq       x@
                    bita      #WA.CurOn
                    bne       x@
                    lbsr      IsDisp
                    bne       x@
                    ora       #WA.CurOn
                    sta       WT.Attr,u
                    lda       WT.CY,u
                    lbsr      TxRing
                    ldb       WT.CX,u
                    pshs      d
                    lbsr      TxShad
                    lda       ,u        the cell, inverted: CG.Buf holds it
                    eora      #$80
                    sta       >CoG+CG.Buf
                    ldu       #CoG+CG.Buf
                    lda       #1
                    sta       >CoG+CG.TxN
                    puls      d
                    lbsr      TxWr
x@                  puls      d,u,pc

* TxShow - X = a fast-text screen being displayed (Select has turned the
* display off): the font bank, every row from the shadow, the palette, the
* bases and scrolls, the mode, and the display on
TxShow              pshs      d,u
                    lbsr      TxFont
                    clra
p@                  clrb
                    lbsr      TxCells
                    inca
                    cmpa      SC.Rows,x
                    blo       p@
                    lbsr      PalShow
                    lda       #TX.TBank
                    ldb       #TX.MBase
                    lbsr      VcQBank
                    lda       SC.TTop,x
                    ldb       #8
                    mul
                    lbsr      VcQVScr
                    ldd       #0
                    lbsr      VcQHScr
                    lda       SC.VMode,x the card changes family at a frame's end (H8)
                    ora       #CT.VIRQ+CT.Cell
                    pshs      a
                    lbsr      VcQCtrl
                    lbsr      CoYield   the palette takes sixteen blanks
                    puls      a
                    ora       #CT.Disp
                    lbsr      VcQCtrl
                    puls      d,u,pc

* TxFont - bake the font into tile bank TX.TBank in the screen's colours.
* A glyph is 64 bytes at TILEBASE * 16K + code * 64, its rows eight bytes
* apart, so span-mask with WADV 00 writes a glyph as eight mask bytes in a
* row, and 16 glyphs fill a ring row.  Codes $80-$FF are $00-$7F with the
* mask complemented.  2,048 writes, ~15 ms.
TxFont              pshs      d,x,u
                    lda       SC.TFG,x
                    ldb       SC.TBG,x
                    std       >CoG+CG.FontFG
                    pshs      cc
                    orcc      #IRQMask
                    lbsr      VcWait
                    bcs       e@
                    lda       #WM.Mask
                    lbsr      VcMode
                    clra
                    lbsr      VcAdv
                    lda       >CoG+CG.FontFG
                    lbsr      VcFG
                    lda       >CoG+CG.FontBG
                    lbsr      VcBG
                    puls      cc
                    clr       >CoG+CG.Tmp the ring row of the bank, 0-15
r@                  pshs      cc
                    orcc      #IRQMask
                    lbsr      VcWait
                    bcs       e@
                    lda       >CoG+CG.Tmp WPTR := TX.TBank * $4000 + row * $400
                    lsla
                    lsla
                    adda      #TX.TBank*$40
                    clrb
                    tfr       d,x
                    clrb
                    lbsr      VcPtr
                    puls      cc
                    lda       >CoG+CG.Tmp 128 mask bytes: the glyphs of ring row r
                    anda      #7
                    ldb       #128
                    mul
                    leax      ArmFont,pcr
                    leax      d,x
                    lda       >CoG+CG.Tmp
                    cmpa      #8
                    blo       put@
                    ldu       #CoG+CG.Buf rows 8-15: the inverse
                    ldb       #128
c@                  lda       ,x+
                    coma
                    sta       ,u+
                    decb
                    bne       c@
                    ldx       #CoG+CG.Buf
put@                ldd       #128
                    lbsr      VcPutN
                    inc       >CoG+CG.Tmp
                    lda       >CoG+CG.Tmp
                    cmpa      #16
                    blo       r@
                    puls      d,x,u,pc
e@                  puls      cc
                    puls      d,x,u,pc

* TxCharAt - A := the code under the window's cursor, without its reverse bit
TxCharAt            pshs      b,u
                    ldu       >CoG+CG.WPtr
                    lda       WT.CY,u
                    lbsr      TxRing
                    ldb       WT.CX,u
                    lbsr      TxShad
                    lda       ,u
                    anda      #$7F
                    puls      b,u,pc
