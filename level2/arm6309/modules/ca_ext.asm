********************************************************************
* ca_ext.asm - CoArm's escape extensions (plan 5.2): PatDef, PatBar,
* PutMask, Poly, PolyPat, Image, Icon and AnsiSw.  Pal565 and PalRange are
* ca_tile.asm's.
*
*   $62 PatDef P B*8          8x8 1bpp pattern P (0-31), and the window's
*                             current pattern.  Its rows are screen rows
*                             mod 8 and its bits screen columns mod 8, so
*                             neighbouring fills line up
*   $63 PatBar X1 Y1 X2 Y2    a rectangle in the pattern: 1 the foreground,
*                             0 the background
*   $64 PutMask GRP BUF X Y   a 1bpp buffer (GPLoad style 5): 1 the
*                             foreground, 0 left as it is
*   $65 Poly NL NR (X Y)*     a filled polygon, as software/demo/tools/show.py
*                             states the rule: a left and a right chain of
*                             vertices from the top vertex to the bottom one,
*                             NL and NR of them (2-15, 16 in all); each edge
*                             steps x in 16.8 from (x0 << 8) + 128 by
*                             sign(dx) * ((|dx| << 8) / dy) a line, and line y
*                             covers [xl, xr).  In the window's foreground, and
*                             its PSet pattern and LSet logic, as Bar is
*   $66 PolyPat NL NR (X Y)*  the same in the current PatDef pattern
*   $67 Image GRP BUF X Y     an 8bpp buffer, clipped: PutBlk
*   $68 Icon GRP BUF X Y SEL  a buffer holding show.py's Icon blob - NCOL H
*                             NL, then per layer C0 C1 PRESENT and the present
*                             columns' H bytes each - every layer's 1 bits in
*                             C0, or C1 with SEL set
*   $69 AnsiSw F              F = 1: the device's bytes are an ANSI terminal's
*                             (show.py's Model.t_bytes): CR, LF, BS, and
*                             CSI m J H f K C D A B.  ESC $69 0 turns it off
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P3.

********************************************************************
* PatDef P B*8
DoPatDef            ldb       #0
                    lbsr      Prm
                    anda      #31
                    pshs      a
                    inca
                    ldx       >CoG+CG.CurS
                    cmpx      #0
                    beq       n@
                    sta       WT.P8,u   the current window's pattern
n@                  puls      a
                    ldb       #8
                    mul
                    ldx       #CoG+CG.Pats
                    leax      d,x
                    ldb       #1
c@                  lbsr      Prm
                    sta       ,x+
                    incb
                    cmpb      #9
                    bne       c@
                    clrb
                    rts

* PatBar X1 Y1 X2 Y2
DoPatBar            lbsr      DrawOn
                    ldb       #0
                    lbsr      PrmX
                    std       >CoG+CG.SX0
                    ldb       #4
                    lbsr      PrmX
                    std       >CoG+CG.SX1
                    cmpd      >CoG+CG.SX0
                    bge       a@
                    ldx       >CoG+CG.SX0
                    std       >CoG+CG.SX0
                    stx       >CoG+CG.SX1
a@                  ldb       #2
                    lbsr      PrmY
                    std       >CoG+CG.SY
                    ldb       #6
                    lbsr      PrmY
                    std       >CoG+CG.PYE
                    cmpd      >CoG+CG.SY
                    bge       r@
                    ldx       >CoG+CG.SY
                    std       >CoG+CG.SY
                    stx       >CoG+CG.PYE
r@                  lbsr      PatSpan
                    ldd       >CoG+CG.SY
                    cmpd      >CoG+CG.PYE
                    bge       x@
                    addd      #1
                    std       >CoG+CG.SY
                    bra       r@
x@                  lbra      DrawOff

* PatSpan - Span's row, in the window's PatDef pattern and its colours
PatSpan             pshs      d,x
                    ldd       >CoG+CG.SY
                    cmpd      >CoG+CG.CY0
                    lblt      x@
                    cmpd      >CoG+CG.CY1
                    lbgt      x@
                    std       >CoG+CG.RY
                    ldd       >CoG+CG.SX0
                    cmpd      >CoG+CG.CX0
                    bge       l@
                    ldd       >CoG+CG.CX0
l@                  std       >CoG+CG.RX
                    ldd       >CoG+CG.SX1
                    cmpd      >CoG+CG.CX1
                    ble       r@
                    ldd       >CoG+CG.CX1
r@                  subd      >CoG+CG.RX
                    lblt      x@
                    addd      #1
                    std       >CoG+CG.RN
                    clr       >CoG+CG.Tmp the row's byte: no pattern is all background
                    ldb       WT.P8,u
                    beq       m@
                    decb
                    lda       #8
                    mul
                    ldx       #CoG+CG.Pats
                    leax      d,x
                    lda       >CoG+CG.RY+1
                    anda      #7
                    lda       a,x
                    sta       >CoG+CG.Tmp
m@                  lda       >CoG+CG.RX+1 the first pixel's bit
                    anda      #7
                    ldb       #$80
s@                  tsta
                    beq       b@
                    lsrb
                    deca
                    bra       s@
b@                  stb       >CoG+CG.Tmp+1
                    ldx       #CoG+CG.Row
                    ldd       >CoG+CG.RN
                    pshs      d
p@                  lda       >CoG+CG.Tmp
                    bita      >CoG+CG.Tmp+1
                    beq       g@
                    lda       WT.FG,u
                    bra       o@
g@                  lda       WT.BG,u
o@                  sta       ,x+
                    lsr       >CoG+CG.Tmp+1
                    bne       k@
                    lda       #$80
                    sta       >CoG+CG.Tmp+1
k@                  ldd       ,s
                    subd      #1
                    std       ,s
                    bne       p@
                    leas      2,s
                    ldx       #CoG+CG.Row
                    lbsr      RowPut
x@                  puls      d,x,pc

********************************************************************
* Poly NL NR, PolyPat NL NR: the vertices follow as data, into the device
* window's WT.Poly; WT.Parms+2 says which
DoPoly              clra
                    bra       p@
DoPolyP             lda       #1
p@                  ldu       >CoG+CG.Dev
                    sta       WT.Parms+2,u
                    ldb       #0
                    lbsr      Prm
                    tfr       a,b
                    ldb       #1
                    lbsr      Prm
                    pshs      a
                    ldb       #0
                    lbsr      Prm
                    adda      ,s+       NL + NR
                    tfr       a,b
                    clra
                    lslb                four bytes a vertex
                    rola
                    lslb
                    rola
                    std       WT.Skip,u
                    ldb       #0        each chain two vertices at least, sixteen in all
                    lbsr      Prm
                    cmpa      #2
                    blo       bad@
                    ldb       #1
                    lbsr      Prm
                    cmpa      #2
                    blo       bad@
                    ldd       WT.Skip,u
                    cmpd      #4*16
                    bhi       bad@
                    leax      WT.Poly,u
                    stx       WT.PrmPtr,u
                    leax      PolyData,pcr
                    stx       WT.EscVct,u
                    clrb
                    rts
bad@                ldd       WT.Skip,u the vertices still arrive: swallow them
                    std       >CoG+CG.Cnt
                    ldb       #E$IllArg
                    lbra      Swallow

* PolyData - A = a vertex byte, U = the device window
PolyData            ldx       WT.PrmPtr,u
                    sta       ,x+
                    stx       WT.PrmPtr,u
                    ldd       WT.Skip,u
                    subd      #1
                    std       WT.Skip,u
                    beq       go@
                    clrb
                    rts
go@                 clr       WT.EscVct,u
                    clr       WT.EscVct+1,u
                    lbsr      CurQ
                    lbsr      DrawOn

* PolyFill - the vertices are in: every line from the top vertex to the
* bottom one, each side stepping along its chain's edges
                    ldx       >CoG+CG.Dev
                    leax      WT.Poly,x
                    stx       >CoG+CG.PLE+PE.P the left chain: NL vertices from WT.Poly
                    ldx       >CoG+CG.Dev
                    clra
                    ldb       WT.Parms,x
                    std       >CoG+CG.PLE+PE.N
                    lslb
                    rola
                    lslb
                    rola
                    addd      >CoG+CG.PLE+PE.P
                    std       >CoG+CG.PRE+PE.P the right chain after it
                    clra
                    ldb       WT.Parms+1,x
                    std       >CoG+CG.PRE+PE.N
                    ldx       >CoG+CG.PLE+PE.P the top: the left chain's first y,
                    ldd       2,x       and the bottom its last
                    addd      >CoG+CG.OY
                    std       >CoG+CG.SY
                    std       >CoG+CG.PLE+PE.YB
                    std       >CoG+CG.PRE+PE.YB
                    ldd       >CoG+CG.PLE+PE.N
                    subd      #1
                    lslb
                    rola
                    lslb
                    rola
                    leax      d,x
                    ldd       2,x
                    addd      >CoG+CG.OY
                    std       >CoG+CG.PYE
l@                  ldd       >CoG+CG.SY
                    cmpd      >CoG+CG.PYE
                    lbge      x@
                    cmpd      >CoG+CG.PLE+PE.YB an edge ends here: the next
                    bne       r@
                    ldx       #CoG+CG.PLE
                    lbsr      PEdge
                    lbcs      x@
r@                  ldd       >CoG+CG.SY
                    cmpd      >CoG+CG.PRE+PE.YB
                    bne       s@
                    ldx       #CoG+CG.PRE
                    lbsr      PEdge
                    lbcs      x@
s@                  ldd       >CoG+CG.PRE+PE.X8 [xl, xr)
                    cmpd      >CoG+CG.PLE+PE.X8
                    ble       n@
                    subd      #1
                    std       >CoG+CG.SX1
                    ldd       >CoG+CG.PLE+PE.X8
                    std       >CoG+CG.SX0
                    ldx       >CoG+CG.Dev
                    tst       WT.Parms+2,x
                    bne       pp@
                    lbsr      Span
                    bra       n@
pp@                 lbsr      PatSpan
n@                  ldx       #CoG+CG.PLE both sides a line on
                    bsr       PStep
                    ldx       #CoG+CG.PRE
                    bsr       PStep
                    ldd       >CoG+CG.SY
                    addd      #1
                    std       >CoG+CG.SY
                    bra       l@
x@                  lbra      DrawOff

* PStep - X = a side: x8 += step, 24 bits
PStep               ldd       PE.X8+1,x
                    addd      PE.St+1,x
                    std       PE.X8+1,x
                    lda       PE.X8,x
                    adca      PE.St,x
                    sta       PE.X8,x
                    rts

* PEdge - X = a side: its next edge that goes down, from vertex P; carry
* set if the chain has none
PEdge               pshs      u
n@                  ldd       PE.N,x
                    cmpd      #2
                    blo       none@
                    ldu       PE.P,x    U = the edge's first vertex, 4,u its second
                    ldd       6,u
                    cmpd      2,u
                    ble       skip@
                    subd      2,u       dy
                    std       >CoG+CG.Dv
                    addd      2,u       the edge ends at yb
                    addd      >CoG+CG.OY
                    std       PE.YB,x
                    clr       >CoG+CG.Neg
                    ldd       4,u       dx
                    subd      ,u
                    bpl       a@
                    com       >CoG+CG.Neg
                    coma
                    comb
                    addd      #1
a@                  clr       >CoG+CG.Q |dx| << 8
                    std       >CoG+CG.Q+1
                    clr       >CoG+CG.Q+3
                    lbsr      UDiv32
                    lda       >CoG+CG.Q+1 the step, 24 bits, signed
                    ldb       >CoG+CG.Q+2
                    std       PE.St,x
                    lda       >CoG+CG.Q+3
                    sta       PE.St+2,x
                    tst       >CoG+CG.Neg
                    beq       p@
                    com       PE.St,x
                    com       PE.St+1,x
                    com       PE.St+2,x
                    inc       PE.St+2,x
                    bne       p@
                    inc       PE.St+1,x
                    bne       p@
                    inc       PE.St,x
p@                  ldd       ,u        x8 := ((xa + OX) << 8) + 128
                    addd      >CoG+CG.OX
                    std       PE.X8,x
                    lda       #$80
                    sta       PE.X8+2,x
                    bsr       adv@
                    puls      u
                    andcc     #^Carry
                    rts
skip@               bsr       adv@
                    bra       n@
none@               puls      u
                    orcc      #Carry
                    rts
adv@                ldd       PE.P,x
                    addd      #4
                    std       PE.P,x
                    ldd       PE.N,x
                    subd      #1
                    std       PE.N,x
                    rts

********************************************************************
* PutMask GRP BUF X Y: DoPutBlk's walk, but each row read, its 1 bits set
DoPutMsk            lbsr      DrawOn
                    ldb       #0
                    lbsr      Prm
                    pshs      a
                    ldb       #1
                    lbsr      Prm
                    tfr       a,b
                    puls      a
                    lbsr      GPFind
                    lbcs      DrawOffE
                    lda       GB.Sty,x
                    cmpa      #5
                    beq       k@
                    ldb       #E$BadBuf
                    lbra      DrawOffE
k@                  stx       >CoG+CG.GP
                    ldd       #0
                    std       >CoG+CG.EDy
                    ldb       #2
                    lbsr      PrmX
                    std       >CoG+CG.ECx
                    ldb       #4
                    lbsr      PrmY
                    std       >CoG+CG.ECy
r@                  ldx       >CoG+CG.GP
                    ldd       >CoG+CG.EDy
                    cmpd      GB.YS,x
                    lbhs      x@
                    addd      >CoG+CG.ECy
                    std       >CoG+CG.RY
                    cmpd      >CoG+CG.CY0
                    lblt      n@
                    cmpd      >CoG+CG.CY1
                    lbgt      x@
                    ldd       >CoG+CG.ECx the part inside the clip: EX its first
                    std       >CoG+CG.RX
                    clra
                    clrb
                    std       >CoG+CG.EX
                    ldd       >CoG+CG.RX
                    cmpd      >CoG+CG.CX0
                    bge       l@
                    ldd       >CoG+CG.CX0
                    subd      >CoG+CG.RX
                    std       >CoG+CG.EX
                    ldd       >CoG+CG.CX0
                    std       >CoG+CG.RX
l@                  ldx       >CoG+CG.GP
                    ldd       >CoG+CG.ECx
                    addd      GB.XS,x
                    subd      #1
                    cmpd      >CoG+CG.CX1
                    ble       rr@
                    ldd       >CoG+CG.CX1
rr@                 subd      >CoG+CG.RX
                    lblt      n@
                    addd      #1
                    std       >CoG+CG.RN
                    ldx       #CoG+CG.Row what is there
                    lbsr      RowGet
                    lbsr      MaskBits  CG.Buf := the row's bits
                    ldx       #CoG+CG.Row
                    ldd       >CoG+CG.RN
                    pshs      d
                    ldd       >CoG+CG.EX the bit: column EX + i
                    std       >CoG+CG.EX1
p@                  ldd       >CoG+CG.EX1
                    pshs      b
                    lsra                its byte, (EX + i) >> 3
                    rorb
                    lsra
                    rorb
                    lsra
                    rorb
                    pshs      x
                    ldx       #CoG+CG.Buf
                    abx
                    lda       ,x
                    puls      x
                    puls      b
                    andb      #7
                    beq       t@
s@                  lsla
                    decb
                    bne       s@
t@                  tsta
                    bpl       o@
                    ldb       WT.FG,u
                    stb       ,x
o@                  leax      1,x
                    ldd       >CoG+CG.EX1
                    addd      #1
                    std       >CoG+CG.EX1
                    ldd       ,s
                    subd      #1
                    std       ,s
                    bne       p@
                    leas      2,s
                    ldx       #CoG+CG.Row
                    lbsr      RowPut
n@                  ldd       >CoG+CG.EDy
                    addd      #1
                    std       >CoG+CG.EDy
                    lbra      r@
x@                  lbra      DrawOff

* MaskBits - CG.Buf := row CG.EDy of the 1bpp buffer CG.GP, up to 80 bytes
MaskBits            ldx       >CoG+CG.GP
                    ldd       GB.XS,x
                    addd      #7
                    lsra
                    rorb
                    lsra
                    rorb
                    lsra
                    rorb
                    std       >CoG+CG.Ma
                    std       >CoG+CG.PatW
                    ldd       >CoG+CG.EDy
                    std       >CoG+CG.Mb
                    lbsr      UMul16
                    ldd       >CoG+CG.Q+2
                    lbsr      GPSeek
                    ldx       #CoG+CG.Buf
                    ldd       >CoG+CG.PatW
                    cmpd      #80
                    bls       b@
                    ldd       #80
b@                  lbra      BRead

********************************************************************
* Icon GRP BUF X Y SEL: the blob into CG.LBuf, then row by row: what is
* there, each layer's bits over it, and back
DoIcon              lbsr      DrawOn
                    ldb       #0
                    lbsr      Prm
                    pshs      a
                    ldb       #1
                    lbsr      Prm
                    tfr       a,b
                    puls      a
                    lbsr      GPFind
                    lbcs      DrawOffE
                    stx       >CoG+CG.GP
                    ldd       #0
                    lbsr      GPSeek
                    ldx       >CoG+CG.GP
                    ldd       GB.Size,x
                    cmpd      #1024
                    bls       s@
                    ldd       #1024
s@                  ldx       #CoG+CG.LBuf
                    lbsr      BRead
                    ldb       #6        SEL
                    lbsr      Prm
                    sta       >CoG+CG.EK
                    ldb       #2
                    lbsr      PrmX
                    std       >CoG+CG.ECx
                    ldb       #4
                    lbsr      PrmY
                    std       >CoG+CG.ECy
                    clra
                    clrb
                    std       >CoG+CG.EDy the icon's row
r@                  ldd       >CoG+CG.EDy
                    cmpb      >CoG+CG.LBuf+1 its height
                    lbhs      x@
                    addd      >CoG+CG.ECy
                    std       >CoG+CG.RY
                    cmpd      >CoG+CG.CY0
                    lblt      n@
                    cmpd      >CoG+CG.CY1
                    lbgt      x@
                    ldd       >CoG+CG.ECx the clip, as PutMask's
                    std       >CoG+CG.RX
                    clra
                    clrb
                    std       >CoG+CG.EX
                    ldd       >CoG+CG.RX
                    cmpd      >CoG+CG.CX0
                    bge       l@
                    ldd       >CoG+CG.CX0
                    subd      >CoG+CG.RX
                    std       >CoG+CG.EX
                    ldd       >CoG+CG.CX0
                    std       >CoG+CG.RX
l@                  clra                the width: NCOL * 8
                    ldb       >CoG+CG.LBuf
                    lslb
                    rola
                    lslb
                    rola
                    lslb
                    rola
                    addd      >CoG+CG.ECx
                    subd      #1
                    cmpd      >CoG+CG.CX1
                    ble       rr@
                    ldd       >CoG+CG.CX1
rr@                 subd      >CoG+CG.RX
                    lblt      n@
                    addd      #1
                    std       >CoG+CG.RN
                    ldx       #CoG+CG.Row
                    lbsr      RowGet
                    ldx       #CoG+CG.LBuf+3 the layers
                    lda       >CoG+CG.LBuf+2
                    sta       >CoG+CG.Cnt
                    lbeq      put@
ly@                 lda       ,x        this layer's colour
                    tst       >CoG+CG.EK
                    beq       c0@
                    lda       1,x
c0@                 sta       >CoG+CG.Colour
                    lda       2,x       its columns
                    sta       >CoG+CG.Cnt+1
                    leax      3,x
                    clr       >CoG+CG.Tmp the icon's column
col@                lsr       >CoG+CG.Cnt+1 present?
                    bcc       nc@
                    pshs      x         its byte in this row: X + EDy
                    ldd       >CoG+CG.EDy
                    leax      d,x
                    lda       ,x
                    lbsr      IconByte
                    puls      x
                    clra                past the column's H bytes
                    ldb       >CoG+CG.LBuf+1
                    leax      d,x
nc@                 inc       >CoG+CG.Tmp
                    lda       >CoG+CG.Tmp
                    cmpa      >CoG+CG.LBuf
                    blo       col@
                    dec       >CoG+CG.Cnt
                    bne       ly@
put@                ldx       #CoG+CG.Row
                    lbsr      RowPut
n@                  ldd       >CoG+CG.EDy
                    addd      #1
                    std       >CoG+CG.EDy
                    lbra      r@
x@                  lbra      DrawOff

* IconByte - A = a layer's byte for icon column CG.Tmp: its 1 bits in
* CG.Colour, into CG.Row (which holds columns EX .. EX + RN - 1)
IconByte            pshs      d,x
                    clra                the column's first pixel's place in CG.Row:
                    ldb       >CoG+CG.Tmp Tmp * 8 - EX
                    lslb
                    rola
                    lslb
                    rola
                    lslb
                    rola
                    subd      >CoG+CG.EX
                    tfr       d,x
                    ldb       #8
                    pshs      b         bits to go 0,s; the byte 1,s
b@                  lsl       1,s
                    bcc       z@
                    cmpx      #0
                    blt       z@
                    cmpx      >CoG+CG.RN
                    bge       z@
                    pshs      x
                    tfr       x,d
                    addd      #CoG+CG.Row
                    tfr       d,x
                    lda       >CoG+CG.Colour
                    sta       ,x
                    puls      x
z@                  leax      1,x
                    dec       ,s
                    bne       b@
                    leas      1,s
                    puls      d,x,pc

********************************************************************
* AnsiSw F: the device's bytes as an ANSI terminal's, or CoWin's again
DoAnsiSw            ldb       #0
                    lbsr      Prm
                    ldx       >CoG+CG.CurS
                    cmpx      #0
                    lbeq      wu@
                    lbsr      IsBmp
                    lbne      it@
                    pshs      a
                    lbsr      CurHide
                    puls      a
                    ldx       >CoG+CG.Dev
                    clr       WT.AnSt,x
                    sta       WT.Ansi,x
                    tsta
                    beq       off@
                    clr       WT.AnFg,x SGR 0: 7 on 0, not bold
                    lda       #7
                    sta       WT.AnFg,x
                    clr       WT.AnBg,x
                    clr       WT.AnBold,x
                    lda       WT.Attr,u no cursor on the terminal
                    anda      #^(WA.Cur+WA.CurOn)
                    sta       WT.Attr,u
                    clrb
                    rts
off@                lda       WT.Attr,u
                    ora       #WA.Cur
                    sta       WT.Attr,u
                    ldx       >CoG+CG.CurS
                    lbra      CurShowOK
wu@                 comb
                    ldb       #E$WUndef
                    rts
it@                 comb
                    ldb       #E$IWTyp
                    rts

* AnsiByte - A = a byte for a device in ANSI mode, U = the device window
AnsiByte            ldb       WT.AnSt,u
                    lbeq      txt@
                    decb
                    bne       csi@
* after ESC: [ is CSI, $69 is CoWin's AnsiSw, anything else ends it
                    clr       WT.AnSt,u
                    cmpa      #'[
                    bne       e1@
                    lda       #2
                    sta       WT.AnSt,u
                    clr       WT.AnN,u
                    clr       WT.AnP,u
                    clr       WT.AnP+1,u
                    clr       WT.AnP+2,u
                    clr       WT.AnP+3,u
                    clrb
                    rts
e1@                 cmpa      #$69
                    lbeq      EscCode   (U is the device, as CoWrite's EscVct has it)
                    clrb
                    rts
* in CSI: digits, ';', and the final byte
csi@                cmpa      #';
                    bne       d1@
                    lda       WT.AnN,u
                    cmpa      #3
                    bhs       k@
                    inc       WT.AnN,u
k@                  clrb
                    rts
d1@                 cmpa      #'0
                    blo       f@
                    cmpa      #'9
                    bhi       f@
                    suba      #'0
                    pshs      a
                    leax      WT.AnP,u
                    ldb       WT.AnN,u
                    abx
                    lda       ,x        p := p * 10 + digit, up to 255
                    ldb       #10
                    mul
                    addb      ,s+
                    adca      #0
                    beq       s@
                    ldb       #255
s@                  stb       ,x
                    clrb
                    rts
f@                  cmpa      #'@
                    blo       k@        an intermediate byte: ignored
                    clr       WT.AnSt,u
                    inc       WT.AnN,u  the parameters there are
                    pshs      a
                    lbsr      CurQ
                    cmpx      #0
                    puls      a
                    beq       k@
                    lbsr      IsBmp
                    bne       k@
                    cmpa      #'m
                    lbeq      AnSGR
                    cmpa      #'J
                    lbeq      AnJ
                    cmpa      #'H
                    lbeq      AnH
                    cmpa      #'f
                    lbeq      AnH
                    cmpa      #'K
                    lbeq      AnK
                    cmpa      #'C
                    lbeq      AnC
                    cmpa      #'D
                    lbeq      AnD
                    cmpa      #'A
                    lbeq      AnA
                    cmpa      #'B
                    lbeq      AnB
                    clrb
                    rts
* text
txt@                cmpa      #$1B
                    bne       t1@
                    inc       WT.AnSt,u
                    clrb
                    rts
t1@                 pshs      a
                    lbsr      CurQ      U := the window, X := its screen
                    cmpx      #0
                    puls      a
                    beq       k2@
                    lbsr      IsBmp
                    bne       k2@
                    cmpa      #$0D
                    bne       t2@
                    clr       WT.CX,u
                    bra       k2@
t2@                 cmpa      #$0A
                    bne       t3@
                    lbra      AnLF
t3@                 cmpa      #$08
                    bne       t4@
                    tst       WT.CX,u
                    beq       k2@
                    dec       WT.CX,u
                    bra       k2@
t4@                 cmpa      #7
                    beq       k2@
                    tsta
                    beq       k2@
                    lbra      AnGlyph
k2@                 clrb
                    rts

* AnGlyph - A = a character, U = the window: at the cursor, in the terminal's
* colours; a line full wraps before the next glyph, not after this one
AnGlyph             pshs      a
                    lbsr      Cols
                    cmpb      WT.CX,u
                    bhi       d@
                    clr       WT.CX,u
                    lbsr      AnLF0
d@                  lbsr      AnCol
                    lda       ,s
                    lbsr      GlyphOf
                    lda       WT.FG,u
                    ldb       WT.BG,u
                    sta       >CoG+CG.MFg
                    stb       >CoG+CG.MBg
                    clr       >CoG+CG.MTr
                    lda       WT.CY,u
                    ldb       WT.CX,u
                    lbsr      BmCell
                    ldx       #CoG+CG.Buf
                    lbsr      Glyph
                    inc       WT.CX,u
                    puls      a
                    clrb
                    rts

* AnCol - the window's colours from the terminal's: fg (+ 8 if bold) on bg
AnCol               pshs      a,x
                    ldx       >CoG+CG.Dev
                    lda       WT.AnFg,x
                    tst       WT.AnBold,x
                    beq       n@
                    adda      #8
n@                  sta       WT.FG,u
                    lda       WT.AnBg,x
                    sta       WT.BG,u
                    puls      a,x,pc

* AnLF - a line feed: the next row, or a scroll whose new row is colour 0
AnLF                bsr       AnLF0
                    clrb
                    rts
AnLF0               pshs      d
                    clr       WT.BG,u
                    lbsr      BmLF
                    bsr       AnCol
                    puls      d,pc

* The CSI finals: U = the window, X = its screen; the device window's WT.AnP
* holds the parameters and WT.AnN how many
AnSGR               ldx       >CoG+CG.Dev
                    leax      WT.AnP,x
                    ldb       -WT.AnP+WT.AnN,x
                    bne       l@
                    clr       ,x        no parameters: 0
                    incb
l@                  pshs      b
p@                  lda       ,x+
                    pshs      x
                    ldx       >CoG+CG.Dev
                    tsta
                    bne       a1@
                    lda       #7        0: 7 on 0, not bold
                    sta       WT.AnFg,x
                    clr       WT.AnBg,x
                    clr       WT.AnBold,x
                    bra       nx@
a1@                 cmpa      #1
                    bne       a2@
                    sta       WT.AnBold,x
                    bra       nx@
a2@                 cmpa      #22
                    bne       a3@
                    clr       WT.AnBold,x
                    bra       nx@
a3@                 cmpa      #39
                    bne       a4@
                    lda       #7
                    sta       WT.AnFg,x
                    bra       nx@
a4@                 cmpa      #49
                    bne       a5@
                    clr       WT.AnBg,x
                    bra       nx@
a5@                 cmpa      #30
                    blo       nx@
                    cmpa      #37
                    bhi       a6@
                    suba      #30
                    sta       WT.AnFg,x
                    bra       nx@
a6@                 cmpa      #40
                    blo       nx@
                    cmpa      #47
                    bhi       nx@
                    suba      #40
                    sta       WT.AnBg,x
nx@                 puls      x
                    dec       ,s
                    bne       p@
                    leas      1,s
                    lbsr      AnCol
                    clrb
                    rts

* J: 2 clears the window in colour 0 and homes the cursor
AnJ                 ldx       >CoG+CG.Dev
                    lda       WT.AnP,x
                    ldx       >CoG+CG.CurS
                    cmpa      #2
                    bne       x@
                    clr       WT.BG,u
                    lbsr      Target
                    lbsr      RectW
                    clra
                    lbsr      FillRect
                    clr       WT.CX,u
                    clr       WT.CY,u
                    lbsr      AnCol
x@                  clrb
                    rts

* H, f: row;col, 1-based, clamped
AnH                 ldx       >CoG+CG.Dev
                    lda       WT.AnP,x
                    ldx       >CoG+CG.CurS
                    tsta
                    beq       r@
                    deca
r@                  pshs      a
                    lbsr      Rows
                    decb
                    cmpb      ,s
                    bhs       c@
                    stb       ,s
c@                  ldx       >CoG+CG.Dev
                    lda       WT.AnP+1,x
                    ldx       >CoG+CG.CurS
                    tsta
                    beq       k@
                    deca
k@                  pshs      a
                    lbsr      Cols
                    decb
                    cmpb      ,s
                    bhs       s@
                    stb       ,s
s@                  puls      a
                    sta       WT.CX,u
                    puls      a
                    sta       WT.CY,u
                    clrb
                    rts

* K: the cursor to the line's end, in the background
AnK                 lbsr      Cols
                    cmpb      WT.CX,u
                    bls       x@
                    lda       WT.CY,u
                    ldb       WT.CX,u
                    lbsr      ClrRow
x@                  clrb
                    rts

* C, D, A, B: the cursor, by the parameter (0 is 1), clamped
AnC                 lbsr      AnCnt
                    adda      WT.CX,u
                    bcs       m@
                    pshs      a
                    lbsr      Cols
                    decb
                    cmpb      ,s+
                    bhs       s@
m@                  lbsr      Cols
                    decb
                    tfr       b,a
s@                  sta       WT.CX,u
                    clrb
                    rts

AnD                 lbsr      AnCnt
                    pshs      a
                    lda       WT.CX,u
                    suba      ,s+
                    bcc       s@
                    clra
s@                  sta       WT.CX,u
                    clrb
                    rts

AnA                 lbsr      AnCnt
                    pshs      a
                    lda       WT.CY,u
                    suba      ,s+
                    bcc       s@
                    clra
s@                  sta       WT.CY,u
                    clrb
                    rts

AnB                 lbsr      AnCnt
                    adda      WT.CY,u
                    bcs       m@
                    pshs      a
                    lbsr      Rows
                    decb
                    cmpb      ,s+
                    bhs       s@
m@                  lbsr      Rows
                    decb
                    tfr       b,a
s@                  sta       WT.CY,u
                    clrb
                    rts

* AnCnt - A := the device window's first parameter, 0 as 1
AnCnt               pshs      x
                    ldx       >CoG+CG.Dev
                    lda       WT.AnP,x
                    bne       x@
                    inca
x@                  puls      x,pc
