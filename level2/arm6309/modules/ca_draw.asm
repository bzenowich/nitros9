********************************************************************
* ca_draw.asm - CoArm's graphics: the draw pointer, Point, Line, Box, Bar,
* Circle, Ellipse, Arc, FFill, PSet and LSet
*
* The shapes are arm6309's software/nitros9/tools/vgshapes.py's, whose
* docstring defines each as a set of pixels; this is that definition in
* 6809 code, written from it, and run-vid.sh compares the two pictures.
*
* Coordinates are the window's working area's, in pixels: the new screen
* types are not scaled (ScaleSw is accepted and ignored).  Everything is
* clipped to the working area, where CoWin answers E$ICoord for some shapes.
* The draw pointer moves for SetDPtr, RSetDPtr, LineM and RLineM only.
* Circle, Ellipse and Arc are centred on it; a circle's radii are equal, and
* each radius is clamped to 255.
*
* Every shape is spans on rows, and Span paints one: clipped, then in the
* foreground colour, or the pattern (PSet: an 8bpp GP buffer, tiled from the
* working area's origin), combined with what is there by LSet's AND, OR or
* XOR.  Each shape paints each of its pixels once, so XOR is exact.  FFill
* is solid: a pattern holding the colour it fills would never end.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P2.

* DrawOn - an escape routine that draws: a bitmap window, its cursor off,
* the target and the clip set, and the colour its foreground.  Returns to
* CoWrite's caller with an error otherwise.
DrawOn              cmpx      #0
                    beq       wu@
                    lbsr      IsText
                    beq       it@
                    lbsr      CurHide
                    lbsr      Target
                    lbsr      Clip
                    lda       WT.FG,u
                    sta       >CoG+CG.Colour
                    rts
wu@                 leas      2,s
                    comb
                    ldb       #E$WUndef
                    rts
it@                 leas      2,s
                    comb
                    ldb       #E$IWTyp
                    rts

* DrawOff - the cursor back, and no error
DrawOff             ldx       >CoG+CG.CurS
                    lbra      CurShowOK

* XYw - D := working-area X (parameter bytes B, B+1) plus the origin; the
* word at B+2 is left for XYh
PrmX                lbsr      PrmW
                    addd      >CoG+CG.OX
                    rts

PrmY                lbsr      PrmW
                    addd      >CoG+CG.OY
                    rts

* PenX, PenY - D := the draw pointer on the screen
PenX                ldd       WT.PX,u
                    addd      >CoG+CG.OX
                    rts

PenY                ldd       WT.PY,u
                    addd      >CoG+CG.OY
                    rts

********************************************************************
* Span - CG.SY, CG.SX0 to CG.SX1 inclusive, screen pixels: clipped and
* painted in the colour, the pattern and the logic of the window U
Span                pshs      d,x
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
                    tst       WT.Pat,u
                    bne       row@
                    tst       WT.Logic,u
                    bne       row@
                    lda       >CoG+CG.Colour
                    lbsr      RowFill
                    lbra      x@
* the row, built: what is there (for the logic), then the pixels
row@                tst       WT.Logic,u
                    beq       p@
                    ldx       #CoG+CG.Row
                    lbsr      RowGet
p@                  tst       WT.Pat,u
                    lbeq      solid@
                    ldb       WT.Pat,u  the pattern: its row (RY - OY) mod YS ...
                    decb
                    lbsr      GPRec
                    stx       >CoG+CG.SPtr
                    ldd       >CoG+CG.RY
                    subd      >CoG+CG.OY
m1@                 cmpd      GB.YS,x
                    blo       m2@
                    subd      GB.YS,x
                    bra       m1@
m2@                 std       >CoG+CG.Cnt ... at offset row * XS
                    ldd       #0
m3@                 pshs      d
                    ldd       >CoG+CG.Cnt
                    beq       m4@
                    subd      #1
                    std       >CoG+CG.Cnt
                    puls      d
                    ldx       >CoG+CG.SPtr
                    addd      GB.XS,x
                    bra       m3@
m4@                 puls      d
                    ldx       >CoG+CG.SPtr
                    lbsr      GPSeek    the stream at that row
                    ldx       >CoG+CG.SPtr its first 128 bytes into CG.Buf
                    ldd       GB.XS,x
                    cmpd      #128
                    bls       c1@
                    ldd       #128
c1@                 std       >CoG+CG.PatW
                    ldx       #CoG+CG.Buf
                    lbsr      BRead
                    ldd       >CoG+CG.RX the column: (RX - OX) mod the width
                    subd      >CoG+CG.OX
m5@                 cmpd      >CoG+CG.PatW
                    blo       m6@
                    subd      >CoG+CG.PatW
                    bra       m5@
m6@                 std       >CoG+CG.Tmp
                    ldd       >CoG+CG.RN
                    std       >CoG+CG.Cnt
                    ldx       #CoG+CG.Row
k@                  pshs      x
                    ldx       >CoG+CG.Tmp
                    lda       CoG+CG.Buf,x the pattern's pixel
                    leax      1,x
                    cmpx      >CoG+CG.PatW
                    blo       w@
                    ldx       #0
w@                  stx       >CoG+CG.Tmp
                    puls      x
                    lbsr      Logic
                    sta       ,x+
                    ldd       >CoG+CG.Cnt
                    subd      #1
                    std       >CoG+CG.Cnt
                    bne       k@
                    bra       put@
solid@              ldx       #CoG+CG.Row
                    ldd       >CoG+CG.RN
                    pshs      d
s@                  lda       >CoG+CG.Colour
                    lbsr      Logic
                    sta       ,x+
                    ldd       ,s
                    subd      #1
                    std       ,s
                    bne       s@
                    leas      2,s
put@                ldx       #CoG+CG.Row
                    lbsr      RowPut
x@                  puls      d,x,pc

* Logic - A = the new pixel, X = the old one: A := LSet's combination
Logic               pshs      b
                    ldb       WT.Logic,u
                    beq       x@
                    cmpb      #1
                    bne       o@
                    anda      ,x
                    puls      b,pc
o@                  cmpb      #2
                    bne       e@
                    ora       ,x
                    puls      b,pc
e@                  eora      ,x
x@                  puls      b,pc

* Plot - a pixel at (CG.PlX, CG.PlY), merged into the run CG.Run*: a
* line's pixels on one row become one span
Plot                pshs      d
                    tst       >CoG+CG.RunOn
                    beq       new@
                    ldd       >CoG+CG.PlY
                    cmpd      >CoG+CG.SY
                    bne       fl@
                    ldd       >CoG+CG.PlX
                    subd      #1
                    cmpd      >CoG+CG.SX1
                    bne       le@
                    ldd       >CoG+CG.PlX
                    std       >CoG+CG.SX1
                    puls      d,pc
le@                 ldd       >CoG+CG.PlX
                    addd      #1
                    cmpd      >CoG+CG.SX0
                    bne       fl@
                    ldd       >CoG+CG.PlX
                    std       >CoG+CG.SX0
                    puls      d,pc
fl@                 lbsr      Span
new@                ldd       >CoG+CG.PlY
                    std       >CoG+CG.SY
                    ldd       >CoG+CG.PlX
                    std       >CoG+CG.SX0
                    std       >CoG+CG.SX1
                    lda       #1
                    sta       >CoG+CG.RunOn
                    puls      d,pc

* Flush - the run, painted
Flush               tst       >CoG+CG.RunOn
                    beq       x@
                    clr       >CoG+CG.RunOn
                    lbsr      Span
x@                  rts

********************************************************************
* The draw pointer
DoSetDP             lbsr      NeedScr
                    ldb       #0
                    lbsr      PrmW
                    std       WT.PX,u
                    ldb       #2
                    lbsr      PrmW
                    std       WT.PY,u
                    clrb
                    rts

DoRSetDP            lbsr      NeedScr
                    ldb       #0
                    lbsr      PrmW
                    addd      WT.PX,u
                    std       WT.PX,u
                    ldb       #2
                    lbsr      PrmW
                    addd      WT.PY,u
                    std       WT.PY,u
                    clrb
                    rts

* Point x y, RPoint dx dy: the pointer stays
DoPoint             lbsr      DrawOn
                    ldb       #0
                    lbsr      PrmX
                    std       >CoG+CG.SX0
                    std       >CoG+CG.SX1
                    ldb       #2
                    lbsr      PrmY
                    std       >CoG+CG.SY
                    lbsr      Span
                    lbra      DrawOff

DoRPoint            lbsr      DrawOn
                    ldb       #0
                    lbsr      PrmW
                    pshs      d
                    lbsr      PenX
                    addd      ,s++
                    std       >CoG+CG.SX0
                    std       >CoG+CG.SX1
                    ldb       #2
                    lbsr      PrmW
                    pshs      d
                    lbsr      PenY
                    addd      ,s++
                    std       >CoG+CG.SY
                    lbsr      Span
                    lbra      DrawOff

* Line x y (from the pointer; it stays), RLine dx dy, LineM, RLineM (the
* pointer moves to the end)
DoLine              clr       >CoG+CG.Move
                    clr       >CoG+CG.Rel
                    bra       LineG

DoRLine             clr       >CoG+CG.Move
                    lda       #1
                    sta       >CoG+CG.Rel
                    bra       LineG

DoLineM             lda       #1
                    sta       >CoG+CG.Move
                    clr       >CoG+CG.Rel
                    bra       LineG

DoRLineM            lda       #1
                    sta       >CoG+CG.Move
                    sta       >CoG+CG.Rel
LineG               lbsr      DrawOn
                    lbsr      EndPt     CG.L+4, +6 := the end, working-area pixels
                    ldd       WT.PX,u
                    std       >CoG+CG.L
                    ldd       WT.PY,u
                    std       >CoG+CG.L+2
                    lbsr      LineL
                    tst       >CoG+CG.Move
                    beq       x@
                    ldd       >CoG+CG.L+4
                    std       WT.PX,u
                    ldd       >CoG+CG.L+6
                    std       WT.PY,u
x@                  lbra      DrawOff

* EndPt - the parameters' point, relative to the pointer if CG.Rel: CG.L+4
* (x) and CG.L+6 (y), in working-area pixels
EndPt               ldb       #0
                    lbsr      PrmW
                    tst       >CoG+CG.Rel
                    beq       a@
                    addd      WT.PX,u
a@                  std       >CoG+CG.L+4
                    ldb       #2
                    lbsr      PrmW
                    tst       >CoG+CG.Rel
                    beq       b@
                    addd      WT.PY,u
b@                  std       >CoG+CG.L+6
                    rts

* LineL - from (CG.L, CG.L+2) to (CG.L+4, CG.L+6), working-area pixels:
* vgshapes.line, Bresenham
LineL               ldd       >CoG+CG.L+4 dx = |x1 - x0|, sx
                    subd      >CoG+CG.L
                    bmi       n1@
                    ldx       #1
                    bra       s1@
n1@                 ldx       #-1
                    coma
                    comb
                    addd      #1
s1@                 std       >CoG+CG.LDx
                    stx       >CoG+CG.LSx
                    ldd       >CoG+CG.L+6 dy = -|y1 - y0|, sy
                    subd      >CoG+CG.L+2
                    bmi       n2@
                    ldx       #1        positive: negated
                    coma
                    comb
                    addd      #1
                    bra       s2@
n2@                 ldx       #-1       negative already
s2@                 std       >CoG+CG.LDy
                    stx       >CoG+CG.LSy
                    ldd       >CoG+CG.LDx err = dx + dy
                    addd      >CoG+CG.LDy
                    std       >CoG+CG.LErr
                    clr       >CoG+CG.RunOn
l@                  ldd       >CoG+CG.L plot
                    addd      >CoG+CG.OX
                    std       >CoG+CG.PlX
                    ldd       >CoG+CG.L+2
                    addd      >CoG+CG.OY
                    std       >CoG+CG.PlY
                    lbsr      Plot
                    ldd       >CoG+CG.L the end?
                    cmpd      >CoG+CG.L+4
                    bne       m@
                    ldd       >CoG+CG.L+2
                    cmpd      >CoG+CG.L+6
                    lbeq      Flush
m@                  ldd       >CoG+CG.LErr e2 = 2 err
                    lslb
                    rola
                    std       >CoG+CG.LE2
                    cmpd      >CoG+CG.LDy if e2 >= dy: err += dy, x += sx
                    blt       y@
                    ldd       >CoG+CG.LErr
                    addd      >CoG+CG.LDy
                    std       >CoG+CG.LErr
                    ldd       >CoG+CG.L
                    addd      >CoG+CG.LSx
                    std       >CoG+CG.L
y@                  ldd       >CoG+CG.LE2 if e2 <= dx: err += dx, y += sy
                    cmpd      >CoG+CG.LDx
                    bgt       l@
                    ldd       >CoG+CG.LErr
                    addd      >CoG+CG.LDx
                    std       >CoG+CG.LErr
                    ldd       >CoG+CG.L+2
                    addd      >CoG+CG.LSy
                    std       >CoG+CG.L+2
                    bra       l@

* Box x y, RBox, Bar x y, RBar: from the pointer's corner; the pointer stays
DoBox               clr       >CoG+CG.Rel
                    bra       BoxG

DoRBox              lda       #1
                    sta       >CoG+CG.Rel
BoxG                lbsr      DrawOn
                    lbsr      Corners   CG.L = xa, +2 ya, +4 xb, +6 yb: screen, sorted
                    ldd       >CoG+CG.L+2 the top row, whole
                    std       >CoG+CG.SY
                    ldd       >CoG+CG.L
                    std       >CoG+CG.SX0
                    ldd       >CoG+CG.L+4
                    std       >CoG+CG.SX1
                    lbsr      Span
                    ldd       >CoG+CG.L+6 the bottom row, if it is another
                    cmpd      >CoG+CG.L+2
                    beq       sides@
                    std       >CoG+CG.SY
                    lbsr      Span
sides@              ldd       >CoG+CG.L+2 the sides, between
                    addd      #1
                    std       >CoG+CG.SY
s@                  ldd       >CoG+CG.SY
                    cmpd      >CoG+CG.L+6
                    bge       x@
                    ldd       >CoG+CG.L
                    std       >CoG+CG.SX0
                    std       >CoG+CG.SX1
                    lbsr      Span
                    ldd       >CoG+CG.L+4
                    cmpd      >CoG+CG.L
                    beq       n@
                    std       >CoG+CG.SX0
                    std       >CoG+CG.SX1
                    lbsr      Span
n@                  ldd       >CoG+CG.SY
                    addd      #1
                    std       >CoG+CG.SY
                    bra       s@
x@                  lbra      DrawOff

DoBar               clr       >CoG+CG.Rel
                    bra       BarG

DoRBar              lda       #1
                    sta       >CoG+CG.Rel
BarG                lbsr      DrawOn
                    bsr       Corners
                    ldd       >CoG+CG.L
                    std       >CoG+CG.SX0
                    ldd       >CoG+CG.L+4
                    std       >CoG+CG.SX1
                    ldd       >CoG+CG.L+2
                    std       >CoG+CG.SY
b@                  lbsr      Span
                    ldd       >CoG+CG.SY
                    cmpd      >CoG+CG.L+6
                    bge       x@
                    addd      #1
                    std       >CoG+CG.SY
                    bra       b@
x@                  lbra      DrawOff

* Corners - the pointer and the parameters' point (relative if CG.Rel),
* sorted, on the screen: CG.L xa, +2 ya, +4 xb, +6 yb
Corners             lbsr      EndPt
                    ldd       WT.PX,u
                    cmpd      >CoG+CG.L+4
                    ble       x1@
                    ldx       >CoG+CG.L+4
                    std       >CoG+CG.L+4
                    tfr       x,d
x1@                 addd      >CoG+CG.OX
                    std       >CoG+CG.L
                    ldd       >CoG+CG.L+4
                    addd      >CoG+CG.OX
                    std       >CoG+CG.L+4
                    ldd       WT.PY,u
                    cmpd      >CoG+CG.L+6
                    ble       y1@
                    ldx       >CoG+CG.L+6
                    std       >CoG+CG.L+6
                    tfr       x,d
y1@                 addd      >CoG+CG.OY
                    std       >CoG+CG.L+2
                    ldd       >CoG+CG.L+6
                    addd      >CoG+CG.OY
                    std       >CoG+CG.L+6
                    rts

********************************************************************
* Ellipses: vgshapes.ellipse_spans

DoCircle            ldb       #0
                    lbsr      PrmW
                    tfr       d,x
                    clr       >CoG+CG.Fill
                    bra       CircG

DoFCircle           ldb       #0
                    lbsr      PrmW
                    tfr       d,x
                    lda       #1
                    sta       >CoG+CG.Fill
CircG               stx       >CoG+CG.ERx
                    stx       >CoG+CG.ERy
                    clr       >CoG+CG.Arc
                    bra       EllG

DoEllipse           clr       >CoG+CG.Fill
                    bra       Ell1G

DoFEllipse          lda       #1
                    sta       >CoG+CG.Fill
Ell1G               ldb       #0
                    lbsr      PrmW
                    std       >CoG+CG.ERx
                    ldb       #2
                    lbsr      PrmW
                    std       >CoG+CG.ERy
                    clr       >CoG+CG.Arc
EllG                lbsr      CurQ
                    lbsr      DrawOn
                    lbsr      Ellipse
                    lbra      DrawOff

* Arc rx ry x1 y1 x2 y2: the outline's pixels on the positive side of the
* line through (x1, y1) and (x2, y2), offsets from the centre
DoArc               ldb       #0
                    lbsr      PrmW
                    std       >CoG+CG.ERx
                    ldb       #2
                    lbsr      PrmW
                    std       >CoG+CG.ERy
                    clr       >CoG+CG.Fill
                    lda       #1
                    sta       >CoG+CG.Arc
                    lbra      EllG

* Ellipse - centre the pointer, radii CG.ERx, CG.ERy (clamped to 0-255);
* CG.Fill: spans; else the outline, filtered by the arc's line if CG.Arc
Ellipse             ldd       >CoG+CG.ERx
                    lbsr      Clamp
                    std       >CoG+CG.ERx
                    ldd       >CoG+CG.ERy
                    lbsr      Clamp
                    std       >CoG+CG.ERy
                    lbsr      PenX
                    std       >CoG+CG.ECx
                    lbsr      PenY
                    std       >CoG+CG.ECy
                    ldd       >CoG+CG.ERy dy from -ry to ry
                    coma
                    comb
                    addd      #1
                    std       >CoG+CG.EDy
r@                  ldd       >CoG+CG.EDy
                    cmpd      >CoG+CG.ERy
                    lbgt      x@
                    addd      >CoG+CG.ECy
                    std       >CoG+CG.SY
                    ldd       >CoG+CG.EDy |dy|
                    bpl       a@
                    coma
                    comb
                    addd      #1
a@                  std       >CoG+CG.EAdy
                    lbsr      HalfW     D := w(|dy|)
                    std       >CoG+CG.EW
                    tst       >CoG+CG.Fill
                    beq       out@
                    lbsr      Whole     [cx - w, cx + w]
                    lbra      n@
out@                ldd       >CoG+CG.EAdy the outline: k = min(max(wn + 1, 0), w)
                    cmpd      >CoG+CG.ERy
                    blo       wn@
                    ldd       #0        at |dy| = ry, wn = -1: k = 0
                    bra       k@
wn@                 addd      #1
                    std       >CoG+CG.EAdy
                    lbsr      HalfW
                    addd      #1
                    pshs      d
                    ldd       >CoG+CG.EAdy
                    subd      #1
                    std       >CoG+CG.EAdy
                    puls      d
k@                  cmpd      >CoG+CG.EW
                    bls       kk@
                    ldd       >CoG+CG.EW
kk@                 std       >CoG+CG.EK
                    bne       two@
                    lbsr      Whole
                    lbra      n@
two@                ldd       >CoG+CG.ECx [cx - w, cx - k]
                    subd      >CoG+CG.EW
                    std       >CoG+CG.SX0
                    ldd       >CoG+CG.ECx
                    subd      >CoG+CG.EK
                    std       >CoG+CG.SX1
                    lbsr      Part
                    ldd       >CoG+CG.ECx [cx + k, cx + w]
                    addd      >CoG+CG.EK
                    std       >CoG+CG.SX0
                    ldd       >CoG+CG.ECx
                    addd      >CoG+CG.EW
                    std       >CoG+CG.SX1
                    lbsr      Part
n@                  ldd       >CoG+CG.EDy
                    addd      #1
                    std       >CoG+CG.EDy
                    lbra      r@
x@                  rts

* Clamp - D := D clamped to 0-255
Clamp               tsta
                    bmi       z@
                    beq       x@
                    ldd       #255
x@                  rts
z@                  clra
                    clrb
                    rts

* Whole - the span [cx - w, cx + w] on CG.SY
Whole               ldd       >CoG+CG.ECx
                    subd      >CoG+CG.EW
                    std       >CoG+CG.SX0
                    ldd       >CoG+CG.ECx
                    addd      >CoG+CG.EW
                    std       >CoG+CG.SX1

* Part - the span CG.SX0-SX1 on CG.SY: painted, or for an arc, its pixels
* on the line's positive side, in runs
Part                tst       >CoG+CG.Arc
                    lbeq      Span
                    clr       >CoG+CG.RunOn
                    ldd       >CoG+CG.SX0
                    std       >CoG+CG.EX
                    ldd       >CoG+CG.SX1
                    std       >CoG+CG.EX1
p@                  ldd       >CoG+CG.EX
                    cmpd      >CoG+CG.EX1
                    lbgt      Flush
                    lbsr      ArcSide
                    bmi       s@
                    ldd       >CoG+CG.EX
                    std       >CoG+CG.PlX
                    ldd       >CoG+CG.SY
                    std       >CoG+CG.PlY
                    pshs      d
                    ldd       >CoG+CG.SY
                    std       >CoG+CG.ESy
                    puls      d
                    lbsr      Plot
                    ldd       >CoG+CG.ESy
                    std       >CoG+CG.SY
s@                  ldd       >CoG+CG.EX
                    addd      #1
                    std       >CoG+CG.EX
                    bra       p@

* ArcSide - N set if (CG.EX, CG.SY) is on the negative side:
* (x2 - x1)(dy - y1) - (y2 - y1)(dx - x1), dx and dy from the centre
ArcSide             ldb       #8        x2 - x1
                    lbsr      PrmW
                    pshs      d
                    ldb       #4
                    lbsr      PrmW
                    pshs      d
                    ldd       2,s
                    subd      ,s++
                    std       >CoG+CG.Ma
                    leas      2,s
                    ldd       >CoG+CG.SY dy - y1
                    subd      >CoG+CG.ECy
                    pshs      d
                    ldb       #6
                    lbsr      PrmW
                    pshs      d
                    ldd       2,s
                    subd      ,s++
                    std       >CoG+CG.Mb
                    leas      2,s
                    lbsr      SMul16    CG.Q := (x2 - x1)(dy - y1)
                    ldd       >CoG+CG.Q
                    std       >CoG+CG.Q3
                    ldd       >CoG+CG.Q+2
                    std       >CoG+CG.Q3+2
                    ldb       #10       y2 - y1
                    lbsr      PrmW
                    pshs      d
                    ldb       #6
                    lbsr      PrmW
                    pshs      d
                    ldd       2,s
                    subd      ,s++
                    std       >CoG+CG.Ma
                    leas      2,s
                    ldd       >CoG+CG.EX dx - x1
                    subd      >CoG+CG.ECx
                    pshs      d
                    ldb       #4
                    lbsr      PrmW
                    pshs      d
                    ldd       2,s
                    subd      ,s++
                    std       >CoG+CG.Mb
                    leas      2,s
                    lbsr      SMul16    CG.Q := (y2 - y1)(dx - x1)
                    ldd       >CoG+CG.Q3+2 Q3 - Q, 32 bits: N is the answer
                    subd      >CoG+CG.Q+2
                    ldd       >CoG+CG.Q3
                    sbcb      >CoG+CG.Q+1
                    sbca      >CoG+CG.Q
                    rts

* HalfW - D := w(CG.EAdy) = isqrt(floor(rx^2 (ry^2 - dy^2) / ry^2) + rx)
HalfW               ldd       >CoG+CG.ERy
                    bne       n@
                    ldd       >CoG+CG.ERx ry = 0: w = rx
                    rts
n@                  lda       >CoG+CG.ERx+1 rx^2
                    tfr       a,b
                    mul
                    std       >CoG+CG.Ma
                    lda       >CoG+CG.ERy+1 ry^2 - dy^2
                    tfr       a,b
                    mul
                    std       >CoG+CG.Dv
                    pshs      d
                    lda       >CoG+CG.EAdy+1
                    tfr       a,b
                    mul
                    pshs      d
                    ldd       2,s
                    subd      ,s++
                    leas      2,s
                    std       >CoG+CG.Mb
                    lbsr      UMul16    CG.Q := rx^2 (ry^2 - dy^2)
                    lbsr      UDiv32    CG.Q := CG.Q / ry^2
                    ldd       >CoG+CG.Q+2
                    addd      >CoG+CG.ERx
                    lbra      ISqrt

********************************************************************
* Arithmetic

* UMul16 - CG.Q := CG.Ma * CG.Mb, unsigned 16 x 16
UMul16              pshs      d,x
                    clra
                    clrb
                    std       >CoG+CG.Q
                    std       >CoG+CG.Q+2
                    std       >CoG+CG.Q2  (the multiplicand, shifted, 32 bits)
                    ldd       >CoG+CG.Ma
                    std       >CoG+CG.Q2+2
                    ldx       >CoG+CG.Mb
                    stx       >CoG+CG.Tmp
                    ldb       #16
                    pshs      b
l@                  lsr       >CoG+CG.Tmp
                    ror       >CoG+CG.Tmp+1
                    bcc       s@
                    ldd       >CoG+CG.Q+2
                    addd      >CoG+CG.Q2+2
                    std       >CoG+CG.Q+2
                    ldd       >CoG+CG.Q
                    adcb      >CoG+CG.Q2+1
                    adca      >CoG+CG.Q2
                    std       >CoG+CG.Q
s@                  lsl       >CoG+CG.Q2+3
                    rol       >CoG+CG.Q2+2
                    rol       >CoG+CG.Q2+1
                    rol       >CoG+CG.Q2
                    dec       ,s
                    bne       l@
                    leas      1,s
                    puls      d,x,pc

* SMul16 - CG.Q := CG.Ma * CG.Mb, signed
SMul16              pshs      d
                    clr       >CoG+CG.Neg
                    ldd       >CoG+CG.Ma
                    bpl       a@
                    com       >CoG+CG.Neg
                    coma
                    comb
                    addd      #1
                    std       >CoG+CG.Ma
a@                  ldd       >CoG+CG.Mb
                    bpl       b@
                    com       >CoG+CG.Neg
                    coma
                    comb
                    addd      #1
                    std       >CoG+CG.Mb
b@                  bsr       UMul16
                    tst       >CoG+CG.Neg
                    beq       x@
                    com       >CoG+CG.Q
                    com       >CoG+CG.Q+1
                    com       >CoG+CG.Q+2
                    com       >CoG+CG.Q+3
                    ldd       >CoG+CG.Q+2
                    addd      #1
                    std       >CoG+CG.Q+2
                    bcc       x@
                    ldd       >CoG+CG.Q
                    addd      #1
                    std       >CoG+CG.Q
x@                  puls      d,pc

* UDiv32 - CG.Q := CG.Q / CG.Dv, unsigned 32 / 16 (the quotient fits 16)
UDiv32              pshs      d,x
                    clra
                    clrb
                    std       >CoG+CG.Rm
                    ldb       #32
                    pshs      b
l@                  lsl       >CoG+CG.Q+3
                    rol       >CoG+CG.Q+2
                    rol       >CoG+CG.Q+1
                    rol       >CoG+CG.Q
                    rol       >CoG+CG.Rm+1
                    rol       >CoG+CG.Rm
                    bcs       sub@      a 17th bit: bigger than any divisor
                    ldd       >CoG+CG.Rm
                    cmpd      >CoG+CG.Dv
                    blo       n@
sub@                ldd       >CoG+CG.Rm
                    subd      >CoG+CG.Dv
                    std       >CoG+CG.Rm
                    inc       >CoG+CG.Q+3
n@                  dec       ,s
                    bne       l@
                    leas      1,s
                    puls      d,x,pc

* ISqrt - D := floor(sqrt(D)), unsigned
ISqrt               pshs      x
                    std       >CoG+CG.Rm the number
                    clra
                    clrb
                    std       >CoG+CG.Tmp the result
                    ldx       #$4000    the bit: down to one not above the number
b@                  cmpx      >CoG+CG.Rm
                    bls       l@
                    tfr       x,d
                    lsra
                    rorb
                    lsra
                    rorb
                    tfr       d,x
                    bne       b@
l@                  cmpx      #0
                    beq       x@
                    tfr       x,d       res + bit
                    addd      >CoG+CG.Tmp
                    cmpd      >CoG+CG.Rm
                    bhi       sm@
                    pshs      d         number -= res + bit; res = res >> 1 + bit
                    ldd       >CoG+CG.Rm
                    subd      ,s++
                    std       >CoG+CG.Rm
                    ldd       >CoG+CG.Tmp
                    lsra
                    rorb
                    pshs      x
                    addd      ,s++
                    std       >CoG+CG.Tmp
                    bra       nx@
sm@                 ldd       >CoG+CG.Tmp res = res >> 1
                    lsra
                    rorb
                    std       >CoG+CG.Tmp
nx@                 tfr       x,d
                    lsra
                    rorb
                    lsra
                    rorb
                    tfr       d,x
                    bra       l@
x@                  ldd       >CoG+CG.Tmp
                    puls      x,pc

********************************************************************
* FFill: from the pointer, the region 4-connected through its colour
* becomes the foreground colour.  Solid, whatever the pattern.
DoFFill             lbsr      DrawOn
                    lbsr      PenX
                    std       >CoG+CG.EX
                    cmpd      >CoG+CG.CX0
                    lblt      x@
                    cmpd      >CoG+CG.CX1
                    lbgt      x@
                    lbsr      PenY
                    std       >CoG+CG.SY
                    cmpd      >CoG+CG.CY0
                    lblt      x@
                    cmpd      >CoG+CG.CY1
                    lbgt      x@
                    lbsr      ReadRow   the colour there
                    lbsr      RowAt
                    cmpa      >CoG+CG.Colour
                    lbeq      x@
                    sta       >CoG+CG.FTgt
                    ldx       #CoG+CG.FSt the seed
                    stx       >CoG+CG.FStk
                    lbsr      Push
p@                  ldx       >CoG+CG.FStk
                    cmpx      #CoG+CG.FSt
                    lbls      x@
                    lbsr      Pop       (CG.EX, CG.SY)
                    lbsr      ReadRow
                    lbsr      RowAt
                    cmpa      >CoG+CG.FTgt
                    bne       p@
                    ldd       >CoG+CG.EX the run of the colour through it: left ...
                    std       >CoG+CG.SX0
l@                  ldd       >CoG+CG.SX0
                    cmpd      >CoG+CG.CX0
                    ble       r0@
                    subd      #1
                    lbsr      RowAtD
                    cmpa      >CoG+CG.FTgt
                    bne       r0@
                    ldd       >CoG+CG.SX0
                    subd      #1
                    std       >CoG+CG.SX0
                    bra       l@
r0@                 ldd       >CoG+CG.EX ... and right
                    std       >CoG+CG.SX1
r@                  ldd       >CoG+CG.SX1
                    cmpd      >CoG+CG.CX1
                    bge       fill@
                    addd      #1
                    lbsr      RowAtD
                    cmpa      >CoG+CG.FTgt
                    bne       fill@
                    ldd       >CoG+CG.SX1
                    addd      #1
                    std       >CoG+CG.SX1
                    bra       r@
fill@               lda       WT.Pat,u  painted solid: no pattern, no logic
                    ldb       WT.Logic,u
                    pshs      d
                    clr       WT.Pat,u
                    clr       WT.Logic,u
                    lbsr      Span
                    puls      d
                    sta       WT.Pat,u
                    stb       WT.Logic,u
                    ldd       >CoG+CG.SY the rows above and below: a seed for each run
                    std       >CoG+CG.ESy
                    subd      #1
                    lbsr      Seeds
                    ldd       >CoG+CG.ESy
                    addd      #1
                    lbsr      Seeds
                    lbra      p@
x@                  lbra      DrawOff

* Seeds - D = a row: a seed at the start of each run of the target colour
* in CG.SX0-SX1 on it, if it is inside the clip
Seeds               cmpd      >CoG+CG.CY0
                    blt       x@
                    cmpd      >CoG+CG.CY1
                    bgt       x@
                    std       >CoG+CG.SY
                    ldd       >CoG+CG.SX0
                    std       >CoG+CG.EX
                    lbsr      ReadRow
                    clr       >CoG+CG.FIn
s@                  ldd       >CoG+CG.EX
                    cmpd      >CoG+CG.SX1
                    bgt       x@
                    lbsr      RowAtD
                    cmpa      >CoG+CG.FTgt
                    bne       o@
                    tst       >CoG+CG.FIn
                    bne       n@
                    inc       >CoG+CG.FIn
                    bsr       Push
                    bra       n@
o@                  clr       >CoG+CG.FIn
n@                  ldd       >CoG+CG.EX
                    addd      #1
                    std       >CoG+CG.EX
                    bra       s@
x@                  ldd       >CoG+CG.ESy
                    std       >CoG+CG.SY
                    rts

* Push, Pop - (CG.EX, CG.SY) on FFill's stack; a full stack drops the seed
Push                ldx       >CoG+CG.FStk
                    cmpx      #CoG+CG.FSt+600
                    bhs       x@
                    ldd       >CoG+CG.EX
                    std       ,x++
                    ldd       >CoG+CG.SY
                    std       ,x++
                    stx       >CoG+CG.FStk
x@                  rts

Pop                 ldx       >CoG+CG.FStk
                    ldd       ,--x
                    std       >CoG+CG.SY
                    ldd       ,--x
                    std       >CoG+CG.EX
                    stx       >CoG+CG.FStk
                    rts

* ReadRow - row CG.SY, the clip's width, into CG.Row
ReadRow             pshs      d,x
                    ldd       >CoG+CG.SY
                    std       >CoG+CG.RY
                    ldd       >CoG+CG.CX0
                    std       >CoG+CG.RX
                    ldd       >CoG+CG.CX1
                    subd      >CoG+CG.CX0
                    addd      #1
                    std       >CoG+CG.RN
                    ldx       #CoG+CG.Row
                    lbsr      RowGet
                    puls      d,x,pc

* RowAt - A := CG.Row's pixel at column CG.EX; RowAtD - at column D
RowAt               ldd       >CoG+CG.EX

RowAtD              pshs      x
                    subd      >CoG+CG.CX0
                    addd      #CoG+CG.Row
                    tfr       d,x
                    lda       ,x
                    puls      x,pc

* PSet grp buf: the pattern, an 8bpp GP buffer; group 0 is none
DoPSet              lbsr      NeedScr
                    ldb       #0
                    lbsr      Prm
                    tsta
                    bne       f@
                    clr       WT.Pat,u
                    clrb
                    rts
f@                  pshs      a
                    ldb       #1
                    lbsr      Prm
                    tfr       a,b
                    puls      a
                    lbsr      GPFind
                    bcs       x@
                    incb
                    stb       WT.Pat,u
                    clrb
x@                  rts

* LSet n: 0 none, 1 AND, 2 OR, 3 XOR
DoLSet              lbsr      NeedScr
                    ldb       #0
                    lbsr      Prm
                    cmpa      #3
                    bls       ok@
                    comb
                    ldb       #E$IllArg
                    rts
ok@                 sta       WT.Logic,u
                    clrb
                    rts
