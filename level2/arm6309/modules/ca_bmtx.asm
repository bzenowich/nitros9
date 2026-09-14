********************************************************************
* ca_bmtx.asm - text in CoArm's windows, and the control codes
*
* The control codes move a window's cursor in cells, the same way on both
* kinds of screen; what differs is how a cell is drawn, erased, scrolled and
* shown under the cursor, and for that each routine here goes to the fast-
* text screen's (ca_text.asm) or does it on a bitmap window, below.
*
* On a bitmap window, as CoWin's GrfDrv does it: a character is an 8 x 8
* glyph from the window's font (the built-in one, or a GP buffer: glyph
* index = code, 8 bytes each) at the cursor's cell in the working area, in
* the window's colours, opaque or transparent (TCharSw), bold (each row
* ORed with itself shifted right) and underlined (the last row solid).  A
* character that would pass the working area's right edge wraps; a line
* feed on its bottom row scrolls the working area up 8 pixels and clears
* the new bottom row.  The cursor is the cell with every pixel XORed with
* $FF, drawn only on the displayed screen, in the window of the device that
* has the keyboard.
*
* A bitmap screen's scroll is VSCROLL += 8 in the next blank when the
* window is the screen's only one, fills it, and the screen is displayed
* (graphics.md 8); otherwise it is a copy, row by row.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P2.

* Cols, Rows - B := the current window's width or height in cells
Cols                lbsr      IsText
                    bne       b@
                    ldb       SC.Cols,x
                    rts
b@                  pshs      a
                    ldd       WT.AW,u
                    bra       Cells

Rows                lbsr      IsText
                    bne       b@
                    ldb       SC.Rows,x
                    rts
b@                  pshs      a
                    ldd       WT.AH,u

Cells               lsra
                    rorb
                    lsra
                    rorb
                    lsra
                    rorb
                    puls      a,pc

********************************************************************
* The shims: each goes to the fast-text routine or the bitmap one

PutCh               lbsr      IsText
                    lbeq      TxPut
                    lbra      BmPut

* CurHide - the cursor off the window, if it is drawn
CurHide             lbsr      IsTile    a tile screen has no cursor
                    beq       CSRts
                    lbsr      IsText
                    lbeq      TxCurOff
                    lbra      BmCurOff

* CurShowOK - the cursor back, and no error; CurShowQ - the same for the
* device's current window, whatever U is
CurShowQ            lbsr      CurQ
                    cmpx      #0
                    beq       CSOk

CurShowOK           bsr       CurShow

CSOk                clrb
CSRts               rts

CurShow             lbsr      IsTile
                    beq       CSRts
                    lbsr      IsText
                    lbeq      TxCurOn
                    lbra      BmCurOn

* ClrRow - text row A from column B, in the window's background
ClrRow              lbsr      IsText
                    lbeq      TxClrRow
                    lbra      BmClrRow

LF                  lbsr      IsText
                    lbeq      TxLF
                    lbra      BmLF

InsLn               lbsr      IsText
                    lbeq      TxInsLn
                    lbra      BmInsLn

DelLn               lbsr      IsText
                    lbeq      TxDelLn
                    lbra      BmDelLn

* CharAt - A := the character under the cursor: a bitmap window keeps no
* characters, and answers 0
CharAt              cmpx      #0
                    beq       z@
                    lbsr      IsText
                    lbeq      TxCharAt
z@                  clra
                    rts

********************************************************************
* The control codes: U = the current window, X = its screen

CtlHome             bsr       CurHide
                    clr       WT.CX,u
                    clr       WT.CY,u
                    bra       CurShowOK

CtlCR               bsr       CurHide
                    clr       WT.CX,u
                    bra       CurShowOK

CtlXY               lda       #2
                    leax      DoXY,pcr
                    lbra      Collect

DoXY                lbsr      NeedScr
                    bsr       CurHide
                    ldb       #0
                    lbsr      Prm
                    suba      #C$SPAC
                    bcs       y@
                    pshs      a
                    lbsr      Cols
                    cmpb      ,s+
                    bls       y@
                    sta       WT.CX,u
y@                  ldb       #1
                    lbsr      Prm
                    suba      #C$SPAC
                    bcs       z@
                    pshs      a
                    lbsr      Rows
                    cmpb      ,s+
                    bls       z@
                    sta       WT.CY,u
z@                  lbra      CurShowOK

CtlCur              lda       #1
                    leax      DoCur,pcr
                    lbra      Collect

DoCur               lbsr      NeedScr
                    ldb       #0
                    lbsr      Prm
                    cmpa      #$20
                    bne       on@
                    lbsr      CurHide
                    lda       WT.Attr,u
                    anda      #^WA.Cur
                    sta       WT.Attr,u
                    clrb
                    rts
on@                 cmpa      #$21
                    bne       x@
                    lda       WT.Attr,u
                    ora       #WA.Cur
                    sta       WT.Attr,u
                    lbra      CurShowOK
x@                  clrb
                    rts

CtlRight            lbsr      CurHide
                    lda       WT.CX,u
                    inca
                    pshs      a
                    lbsr      Cols
                    cmpb      ,s+
                    bhi       s@        the next column is in the window
                    lda       WT.CY,u
                    inca
                    pshs      a
                    lbsr      Rows
                    cmpb      ,s+
                    bls       k@        the last cell stays put
                    sta       WT.CY,u
                    clra
s@                  sta       WT.CX,u
k@                  lbra      CurShowOK

CtlLeft             lbsr      CurHide
                    lda       WT.CX,u
                    beq       up@
                    deca
                    sta       WT.CX,u
                    lbra      CurShowOK
up@                 lda       WT.CY,u   the first column goes to the end of the line above
                    beq       k@
                    deca
                    sta       WT.CY,u
                    lbsr      Cols
                    decb
                    stb       WT.CX,u
k@                  lbra      CurShowOK

CtlUp               lbsr      CurHide
                    lda       WT.CY,u
                    beq       k@
                    dec       WT.CY,u
k@                  lbra      CurShowOK

CtlDown             lbsr      CurHide
                    lbsr      LF
                    lbra      CurShowOK

CtlErLn             lbsr      CurHide
                    lda       WT.CY,u
                    clrb
                    lbsr      ClrRow
                    lbra      CurShowOK

CtlErEOL            lbsr      CurHide
                    lda       WT.CY,u
                    ldb       WT.CX,u
                    lbsr      ClrRow
                    lbra      CurShowOK

CtlErEOS            lbsr      CurHide
                    lda       WT.CY,u
                    ldb       WT.CX,u
e@                  lbsr      ClrRow
                    inca
                    pshs      a
                    lbsr      Rows
                    cmpb      ,s+
                    bls       k@
                    clrb
                    bra       e@
k@                  lbra      CurShowOK

CtlCls              lbsr      CurHide
                    clr       WT.CX,u
                    clr       WT.CY,u
                    clra
c@                  clrb
                    lbsr      ClrRow
                    inca
                    pshs      a
                    lbsr      Rows
                    cmpb      ,s+
                    bhi       c@
                    lbra      CurShowOK

* $1F xx: reverse, underline, blink; insert and delete line
DoAttr              lbsr      NeedScr
                    ldb       #0
                    lbsr      Prm
                    ldb       #WA.Rev
                    cmpa      #$20
                    beq       on@
                    cmpa      #$21
                    beq       off@
                    ldb       #WA.Undl
                    cmpa      #$22
                    beq       on@
                    cmpa      #$23
                    beq       off@
                    cmpa      #$30
                    bne       d@
                    lbsr      CurHide
                    lbsr      InsLn
                    lbra      CurShowOK
d@                  cmpa      #$31
                    bne       x@
                    lbsr      CurHide
                    lbsr      DelLn
                    lbra      CurShowOK
on@                 orb       WT.Attr,u
                    stb       WT.Attr,u
x@                  clrb                blink, and anything else: accepted, not drawn
                    rts
off@                comb
                    andb      WT.Attr,u
                    stb       WT.Attr,u
                    clrb
                    rts

* TCharSw, BoldSw
DoTChar             ldb       #WA.Trans
                    bra       Sw

DoBold              ldb       #WA.Bold

Sw                  lbsr      NeedScr
                    pshs      b
                    ldb       #0
                    lbsr      Prm
                    puls      b
                    tsta
                    beq       off@
                    orb       WT.Attr,u
                    stb       WT.Attr,u
                    clrb
                    rts
off@                comb
                    andb      WT.Attr,u
                    stb       WT.Attr,u
                    clrb
                    rts

********************************************************************
* Bitmap text

* BmCell - A = a text row, B = a column: CG.RX, CG.RY := the cell's corner;
* the target set for X's screen
BmCell              pshs      d
                    lbsr      Target
                    ldb       1,s
                    lda       #8
                    mul
                    addd      WT.AX,u
                    std       >CoG+CG.RX
                    ldb       ,s
                    lda       #8
                    mul
                    addd      WT.AY,u
                    std       >CoG+CG.RY
                    puls      d,pc

* BmPut - A = a printable byte, at the cursor, which then moves on
BmPut               pshs      a
                    lda       WT.Attr,u the cursor is in this cell: an opaque glyph covers
                    bita      #WA.CurOn it, a transparent one needs it taken off first
                    beq       g@
                    bita      #WA.Trans
                    beq       o@
                    lbsr      BmCurOff
                    bra       g@
o@                  anda      #^WA.CurOn
                    sta       WT.Attr,u
g@                  lda       ,s
                    lbsr      GlyphOf   CG.Buf := its 8 rows, bold and underlined as set
                    lda       WT.FG,u   the colours, reversed as set
                    ldb       WT.BG,u
                    pshs      a
                    lda       WT.Attr,u
                    bita      #WA.Rev
                    puls      a
                    beq       n@
                    exg       a,b
n@                  sta       >CoG+CG.MFg
                    stb       >CoG+CG.MBg
                    clr       >CoG+CG.MTr
                    lda       WT.Attr,u
                    bita      #WA.Trans
                    beq       t@
                    inc       >CoG+CG.MTr
t@                  lda       WT.CY,u
                    ldb       WT.CX,u
                    bsr       BmCell
                    ldx       #CoG+CG.Buf
                    lbsr      Glyph
                    ldx       >CoG+CG.CurS
                    leas      1,s
                    inc       WT.CX,u   the next cell, if a whole cell fits
                    lda       WT.CX,u
                    inca
                    ldb       #8
                    mul
                    cmpd      WT.AW,u
                    bls       k@
                    clr       WT.CX,u
                    lbsr      BmLF
k@                  lbra      CurShowOK

* GlyphOf - A = a character: CG.Buf := its eight rows in the window's font,
* then bold and underline
GlyphOf             pshs      d,x
                    ldb       WT.Font,u
                    beq       rom@
                    decb                a GP buffer: code * 8, if it holds that glyph
                    lbsr      GPRec
                    tfr       a,b
                    clra
                    lslb
                    rola
                    lslb
                    rola
                    lslb
                    rola
                    pshs      d
                    addd      #8
                    cmpd      GB.Size,x
                    puls      d
                    bls       gp@
                    lda       ,s        beyond it: the code without bit 7
                    anda      #$7F
                    tfr       a,b
                    clra
                    lslb
                    rola
                    lslb
                    rola
                    lslb
                    rola
                    pshs      d
                    addd      #8
                    cmpd      GB.Size,x
                    puls      d
                    bhi       blank@
gp@                 lbsr      GPSeek    X := the byte D of the buffer, mapped
                    ldu       #CoG+CG.Buf
                    ldb       #8
g@                  lda       ,x+
                    sta       ,u+
                    decb
                    bne       g@
                    ldu       >CoG+CG.WPtr
                    bra       fx@
blank@              ldx       #CoG+CG.Buf
                    ldb       #8
z@                  clr       ,x+
                    decb
                    bne       z@
                    bra       fx@
rom@                anda      #$7F      the built-in font: 128 glyphs
                    ldb       #8
                    mul
                    leax      ArmFont,pcr
                    leax      d,x
                    pshs      u
                    ldu       #CoG+CG.Buf
                    ldb       #8
r@                  lda       ,x+
                    sta       ,u+
                    decb
                    bne       r@
                    puls      u
fx@                 lda       WT.Attr,u
                    bita      #WA.Bold
                    beq       ul@
                    ldx       #CoG+CG.Buf
                    ldb       #8
b@                  lda       ,x
                    lsra
                    ora       ,x
                    sta       ,x+
                    decb
                    bne       b@
ul@                 lda       WT.Attr,u
                    bita      #WA.Undl
                    beq       x@
                    lda       #$FF
                    sta       >CoG+CG.Buf+7
x@                  puls      d,x,pc

* BmLF - down a row, or scroll the working area up by one
BmLF                lda       WT.CY,u
                    adda      #2
                    ldb       #8
                    mul
                    cmpd      WT.AH,u
                    bhi       BmScroll
                    inc       WT.CY,u
                    rts

* BmScroll - the working area up 8 pixels, and its bottom text row cleared
BmScroll            pshs      d
                    lbsr      Target
                    lbsr      IsDisp    the fast path: VSCROLL, for a displayed screen
                    bne       copy@     with this window alone on it, filling it
                    lda       SC.Wins,x
                    cmpa      #1
                    bne       copy@
                    ldd       WT.AX,u
                    bne       copy@
                    ldd       WT.AY,u
                    bne       copy@
                    ldd       WT.AW,u
                    cmpd      SC.W,x
                    bne       copy@
                    ldd       WT.AH,u
                    cmpd      SC.H,x
                    bne       copy@
                    lbsr      PtrOff    the pointer would scroll with the picture
                    inc       >CoG+CG.PtrHid
                    ldd       SC.Top,x
                    addd      #8
                    anda      #1
                    std       SC.Top,x
                    lbsr      VcQVScr
                    lbsr      Target
                    bra       clr@
copy@               ldd       WT.AX,u
                    std       >CoG+CG.RX
                    ldd       WT.AW,u
                    std       >CoG+CG.RN
                    ldd       WT.AY,u
                    addd      #8
                    std       >CoG+CG.RY
                    ldd       WT.AH,u
                    subd      #8
                    std       >CoG+CG.FH
c@                  ldd       >CoG+CG.FH
                    beq       clr@
                    subd      #1
                    std       >CoG+CG.FH
                    ldx       #CoG+CG.Row
                    lbsr      RowGet
                    ldd       >CoG+CG.RY
                    subd      #8
                    std       >CoG+CG.RY
                    ldx       #CoG+CG.Row
                    lbsr      RowPut
                    ldd       >CoG+CG.RY
                    addd      #9
                    std       >CoG+CG.RY
                    bra       c@
clr@                ldx       >CoG+CG.CurS
                    lbsr      Rows
                    tfr       b,a
                    deca
                    clrb
                    bsr       BmClrRow
                    puls      d,pc

* BmClrRow - text row A from column B, in the background.  A, B are kept.
BmClrRow            pshs      d
                    lbsr      BmCell
                    lda       1,s
                    ldb       #8
                    mul
                    pshs      d
                    ldd       WT.AW,u
                    subd      ,s++
                    std       >CoG+CG.RN
                    ldd       #8
                    std       >CoG+CG.FH
                    lda       WT.BG,u
                    lbsr      FillRect
                    puls      d,pc

* BmRowMove - text row A := text row B (8 pixel rows, the working area's
* width).  A, B are kept.
BmRowMove           pshs      d
                    lbsr      Target
                    ldd       WT.AX,u
                    std       >CoG+CG.RX
                    ldd       WT.AW,u
                    std       >CoG+CG.RN
                    lda       #8
                    sta       >CoG+CG.Tmp
m@                  ldb       1,s       the source row's pixel row
                    lda       #8
                    mul
                    addd      WT.AY,u
                    addb      #8
                    adca      #0
                    subb      >CoG+CG.Tmp
                    sbca      #0
                    std       >CoG+CG.RY
                    ldx       #CoG+CG.Row
                    lbsr      RowGet
                    ldb       ,s        the destination's
                    lda       #8
                    mul
                    addd      WT.AY,u
                    addb      #8
                    adca      #0
                    subb      >CoG+CG.Tmp
                    sbca      #0
                    std       >CoG+CG.RY
                    ldx       #CoG+CG.Row
                    lbsr      RowPut
                    dec       >CoG+CG.Tmp
                    bne       m@
                    ldx       >CoG+CG.CurS
                    puls      d,pc

* BmInsLn - a blank row at the cursor; the rows below move down
BmInsLn             lbsr      Rows
                    tfr       b,a
                    deca
i@                  cmpa      WT.CY,u
                    bls       c@
                    tfr       a,b
                    decb
                    bsr       BmRowMove
                    deca
                    bra       i@
c@                  lda       WT.CY,u
                    clrb
                    lbra      BmClrRow

* BmDelLn - the cursor's row goes; the rows below move up
BmDelLn             lda       WT.CY,u
d@                  inca
                    pshs      a
                    lbsr      Rows
                    cmpb      ,s+
                    bls       c@
                    tfr       a,b
                    deca
                    bsr       BmRowMove
                    inca
                    bra       d@
c@                  lbsr      Rows
                    tfr       b,a
                    deca
                    clrb
                    lbra      BmClrRow

* BmCurOff, BmCurOn - the cursor's cell XORed with $FF: off if drawn; on if
* enabled, not drawn, the screen displayed and the device the keyboard's
BmCurOff            pshs      d,x
                    lda       WT.Attr,u
                    bita      #WA.CurOn
                    beq       x@
                    anda      #^WA.CurOn
                    sta       WT.Attr,u
                    bsr       CurXor
x@                  puls      d,x,pc

BmCurOn             pshs      d,x
                    lda       WT.Attr,u
                    bita      #WA.Cur
                    beq       x@
                    bita      #WA.CurOn
                    bne       x@
                    lbsr      IsDisp
                    bne       x@
                    pshs      u
                    ldu       >CoG+CG.Dev
                    lbsr      WIdx
                    puls      u
                    cmpb      VG.CSel,y
                    bne       x@
                    lda       WT.Attr,u
                    ora       #WA.CurOn
                    sta       WT.Attr,u
                    bsr       CurXor
x@                  puls      d,x,pc

* CurXor - the cursor's cell, every pixel XORed with $FF
CurXor              lda       WT.CY,u
                    ldb       WT.CX,u
                    lbsr      BmCell
                    ldd       #8
                    std       >CoG+CG.RN
                    lda       #8
                    sta       >CoG+CG.Tmp
r@                  ldx       #CoG+CG.Row
                    lbsr      RowGet
                    ldx       #CoG+CG.Row
                    ldb       #8
e@                  lda       ,x
                    coma
                    sta       ,x+
                    decb
                    bne       e@
                    ldx       #CoG+CG.Row
                    lbsr      RowPut
                    ldd       >CoG+CG.RY
                    addd      #1
                    std       >CoG+CG.RY
                    dec       >CoG+CG.Tmp
                    bne       r@
                    ldx       >CoG+CG.CurS
                    rts
