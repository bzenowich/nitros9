********************************************************************
* ca_scr.asm - CoArm's screens and windows: DWSet, Select, DWEnd, OWSet,
* OWEnd, CWArea, and the colours
*
* A screen is fast text ($18, $19: ca_text.asm) or a bitmap ($10-$13): 640
* pixels wide, 200, 240, 400 or 480 high, 8bpp, with a store in DRAM - 640
* x H bytes in F$AllRAM blocks - that holds its pixels while it is not
* displayed.  Select moves the displayed bitmap's pixels from the card into
* its store and the new one's from its store onto the card, with the
* display off between.  So drawing on a screen that is not displayed is
* drawing in its store (ca_row.asm's DRAM back-end), and costs no VRAM.
*
* Windows follow CoWin (cowin.asm, grfdrv.asm): sizes and positions in 8 x
* 8 cells; DWSet clears its window to the background and homes the cursor;
* an overlay's position is relative to its device window's working area and
* checked against the device window's own size; OWSet with SVS saves what
* it covers and OWEnd puts it back; CWArea is relative to the window and
* homes the cursor without clearing.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P2.

* IsDisp - X = a screen: Z set if it is the displayed one
IsDisp              pshs      b
                    lbsr      SIdx
                    incb
                    cmpb      >CoG+CG.Disp
                    puls      b,pc

* Target - X = a screen: the row layer's target, the card or its store
Target              pshs      d
                    bsr       IsDisp
                    bne       st@
                    clra
                    clrb
                    std       >CoG+CG.TStr
                    ldd       SC.Top,x
                    std       >CoG+CG.TTop
                    puls      d,pc
st@                 ldd       SC.StBlk,x
                    std       >CoG+CG.TStr
                    puls      d,pc

* Clip - U = a window: CG.CX0-CY1 := its working area, inclusive, and
* CG.OX, CG.OY := its origin
Clip                pshs      d
                    ldd       WT.AX,u
                    std       >CoG+CG.CX0
                    std       >CoG+CG.OX
                    addd      WT.AW,u
                    subd      #1
                    std       >CoG+CG.CX1
                    ldd       WT.AY,u
                    std       >CoG+CG.CY0
                    std       >CoG+CG.OY
                    addd      WT.AH,u
                    subd      #1
                    std       >CoG+CG.CY1
                    puls      d,pc

* FillRect - A = the colour: CG.RN x CG.FH pixels from (CG.RX, CG.RY), in
* the current target, unclipped.  CG.RY is kept.
FillRect            pshs      d,x
                    ldx       >CoG+CG.RY
                    pshs      x
                    ldx       >CoG+CG.FH
                    pshs      x         the rows left, over RY, D, X
r@                  ldx       ,s
                    beq       x@
                    leax      -1,x
                    stx       ,s
                    lda       4,s       the colour
                    lbsr      RowFill
                    ldd       >CoG+CG.RY
                    addd      #1
                    std       >CoG+CG.RY
                    bra       r@
x@                  leas      2,s
                    puls      x
                    stx       >CoG+CG.RY
                    puls      d,x,pc

* RectW - U = a window: CG.RX, RY, RN, FH := its whole rectangle
RectW               pshs      d
                    ldd       WT.X,u
                    std       >CoG+CG.RX
                    ldd       WT.Y,u
                    std       >CoG+CG.RY
                    ldd       WT.W,u
                    std       >CoG+CG.RN
                    ldd       WT.H,u
                    std       >CoG+CG.FH
                    puls      d,pc

********************************************************************
* DWSet STY CPX CPY SZX SZY PRN1 PRN2, and PRN3 for a new screen
DoDWSet0            ldb       #0
                    lbsr      Prm
                    cmpa      #$FF
                    lbeq      DoDWSet
                    pshs      u
                    ldu       >CoG+CG.Dev
                    lda       #1        PRN3 follows, after the seven already in
                    sta       WT.PrmCnt,u
                    leax      DoDWSet,pcr
                    stx       WT.PrmFn,u
                    leax      WT.Parms+7,u
                    stx       WT.PrmPtr,u
                    leax      Collect1,pcr
                    stx       WT.EscVct,u
                    puls      u
                    clrb
                    rts

* DoDWSet - the device's parameters are in
DoDWSet             ldu       >CoG+CG.Dev
                    lda       WT.Scr,u
                    cmpa      #$FF
                    beq       n@
                    comb
                    ldb       #E$WADef
                    rts
n@                  ldb       #0
                    lbsr      Prm
                    cmpa      #$FF
                    bne       new@
* STY $FF: a window on the displayed screen, which must be a bitmap
                    ldb       >CoG+CG.Disp
                    lbeq      wu@
                    decb
                    lbsr      SRec
                    lbsr      IsBmp
                    lbne      it@
                    lbra      win@
new@                ldx       #CoG+CG.Scr a free screen record
                    clrb
f@                  tst       SC.Used,x
                    beq       got@
                    leax      SC.Size,x
                    incb
                    cmpb      #ScrMax
                    blo       f@
                    comb
                    ldb       #E$TblFul
                    rts
got@                cmpa      #STY.Tile25
                    lbeq      TlNew
                    cmpa      #STY.Tile30
                    lbeq      TlNew
                    cmpa      #STY.Txt25
                    lbeq      TxNew
                    cmpa      #STY.Txt30
                    lbeq      TxNew
                    suba      #$10      $10-$13: VMODE 00-11
                    cmpa      #3
                    lbhi      it@
                    sta       SC.VMode,x
                    adda      #$10
                    sta       SC.Type,x
                    ldd       #640
                    std       SC.W,x
                    ldb       SC.VMode,x
                    lslb
                    leau      BmH,pcr
                    ldd       b,u
                    std       SC.H,x
                    lda       #80
                    sta       SC.Cols,x
                    ldd       SC.H,x
                    lsra
                    rorb
                    lsra
                    rorb
                    lsra
                    rorb
                    stb       SC.Rows,x
                    clra
                    clrb
                    std       SC.Top,x
                    clr       SC.Wins,x
                    ldb       SC.VMode,x the store: 640 x H, rounded up to blocks
                    leau      BmBlk,pcr
                    ldb       b,u
                    stb       SC.StN,x
                    lbsr      CoAlloc
                    lbcs      e@
                    std       SC.StBlk,x
                    inc       SC.Used,x
                    lbsr      PalDef
                    lbsr      Target    all of it in PRN2
                    clra
                    clrb
                    std       >CoG+CG.RX
                    std       >CoG+CG.RY
                    ldd       SC.W,x
                    std       >CoG+CG.RN
                    ldd       SC.H,x
                    std       >CoG+CG.FH
                    ldb       #6
                    lbsr      Prm
                    lbsr      FillRect
* the window, on the screen X
win@                ldu       >CoG+CG.Dev
                    ldb       #1        CPX CPY SZX SZY, in cells
                    lbsr      Prm
                    ldb       #8
                    mul
                    std       WT.X,u
                    ldb       #2
                    lbsr      Prm
                    ldb       #8
                    mul
                    std       WT.Y,u
                    ldb       #3
                    lbsr      Prm
                    tsta
                    beq       id@
                    ldb       #8
                    mul
                    std       WT.W,u
                    addd      WT.X,u
                    cmpd      SC.W,x
                    bhi       id@
                    ldb       #4
                    lbsr      Prm
                    tsta
                    beq       id@
                    ldb       #8
                    mul
                    std       WT.H,u
                    addd      WT.Y,u
                    cmpd      SC.H,x
                    bhi       id@
                    lbsr      SIdx
                    stb       WT.Scr,u
                    inc       SC.Wins,x
                    lbsr      WIdx
                    stb       WT.Cur,u
                    lda       #$FF
                    sta       WT.Par,u
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
id@                 comb
                    ldb       #E$IWDef
                    rts
it@                 comb
                    ldb       #E$IWTyp
                    rts
wu@                 comb
                    ldb       #E$WUndef
                    rts
e@                  rts

BmH                 fdb       200,240,400,480

BmBlk               fcb       16,19,32,38 640 x H / 8192, rounded up

* WinInit - U = a window whose rectangle, screen and colours are set, X its
* screen: the working area is the rectangle, the cursor and the pen are
* home, everything else is its default, and a bitmap window is cleared to
* its background
WinInit             pshs      d
                    ldd       WT.X,u
                    std       WT.AX,u
                    ldd       WT.Y,u
                    std       WT.AY,u
                    ldd       WT.W,u
                    std       WT.AW,u
                    ldd       WT.H,u
                    std       WT.AH,u
                    clr       WT.CX,u
                    clr       WT.CY,u
                    lda       #WA.Cur
                    sta       WT.Attr,u
                    clra
                    clrb
                    std       WT.PX,u
                    std       WT.PY,u
                    clr       WT.Pat,u
                    clr       WT.Logic,u
                    clr       WT.Font,u
                    lbsr      IsBmp
                    bne       x@
                    lbsr      Target
                    lbsr      RectW
                    lda       WT.BG,u
                    lbsr      FillRect
x@                  puls      d,pc

********************************************************************
* Select: the current window's screen is displayed, and its device takes
* the keyboard
DoSelect            lbsr      NeedScr
                    tst       VG.XScr,y an exclusive screen keeps the card
                    beq       s@
                    comb
                    ldb       #E$DevBsy
                    rts
s@                  lbsr      CurHide
                    bsr       Select
                    lbra      CurShowOK

* Select - X = a screen to display; CG.Dev's device takes the keyboard
Select              pshs      d,x,u
                    ldu       >CoG+CG.Dev
                    lbsr      WIdx
                    stb       VG.CSel,y
                    lbsr      IsDisp
                    lbeq      x@
                    lbsr      PtrOff    the pointer comes off the old picture
                    clr       VG.DScr,y and the old screen's list is not started again
                    lda       VG.Ctrl,y display off from the next blank, in the mode it is in
                    anda      #^CT.Disp
                    lbsr      VcQCtrl
                    lbsr      CoYield
                    ldb       >CoG+CG.Disp the old screen's pixels to its store
                    beq       new@
                    decb
                    lbsr      SRec
                    lbsr      IsBmp
                    bne       new@
                    lbsr      CardToStore
new@                ldx       2,s       the new screen
                    lbsr      SIdx
                    incb
                    stb       >CoG+CG.Disp
                    stb       VG.DScr,y its list, if it has one, from the next blank
                    lbsr      IsTile
                    bne       t@
                    lbsr      TlShow    tiles: the bases, the palette, cell mode
                    bra       ptr@
t@                  lbsr      IsText
                    bne       bm@
                    lbsr      TxShow    fast text: the font bank, the map, the palette, CTRL
                    bra       ptr@
bm@                 lbsr      StoreToCard
                    lda       SC.VMode,x the card changes family at a frame's end (H8)
                    ora       #CT.VIRQ
                    pshs      a
                    lbsr      VcQCtrl
                    ldd       #0
                    lbsr      VcQVScr
                    lbsr      VcQHScr
                    lbsr      PalShow
                    lbsr      CoYield   the palette takes sixteen blanks
                    puls      a
                    ora       #CT.Disp
                    lbsr      VcQCtrl
ptr@                lbsr      PtrScreen the pointer's view of the new picture
x@                  puls      d,x,u,pc

* CardToStore - X = the displayed bitmap screen: every row to its store
CardToStore         stx       >CoG+CG.SPtr
                    clra
                    clrb
                    std       >CoG+CG.RX
                    std       >CoG+CG.RY
                    ldd       SC.W,x
                    std       >CoG+CG.RN
c@                  ldx       >CoG+CG.SPtr
                    ldd       >CoG+CG.RY
                    cmpd      SC.H,x
                    bhs       x@
                    clra
                    clrb
                    std       >CoG+CG.TStr the card ...
                    ldd       SC.Top,x
                    std       >CoG+CG.TTop
                    ldx       #CoG+CG.Row
                    lbsr      RowGet
                    ldx       >CoG+CG.SPtr ... to the store
                    ldd       SC.StBlk,x
                    std       >CoG+CG.TStr
                    ldx       #CoG+CG.Row
                    lbsr      RowPut
                    ldd       >CoG+CG.RY
                    addd      #1
                    std       >CoG+CG.RY
                    bra       c@
x@                  ldx       >CoG+CG.SPtr
                    rts

* StoreToCard - X = the bitmap screen being displayed: every row from its
* store to ring rows 0 up, and its top is ring row 0
StoreToCard         stx       >CoG+CG.SPtr
                    clra
                    clrb
                    std       SC.Top,x
                    std       >CoG+CG.RX
                    std       >CoG+CG.RY
                    ldd       SC.W,x
                    std       >CoG+CG.RN
c@                  ldx       >CoG+CG.SPtr
                    ldd       >CoG+CG.RY
                    cmpd      SC.H,x
                    bhs       x@
                    ldd       SC.StBlk,x the store ...
                    std       >CoG+CG.TStr
                    ldx       #CoG+CG.Row
                    lbsr      RowGet
                    clra                ... to the card
                    clrb
                    std       >CoG+CG.TStr
                    std       >CoG+CG.TTop
                    ldx       #CoG+CG.Row
                    lbsr      RowPut
                    ldd       #640      and the ring's columns past the screen in colour 0,
                    std       >CoG+CG.RX so an HSCROLL list shows something defined there
                    ldd       #1024-640
                    std       >CoG+CG.RN
                    clra
                    lbsr      RowFill
                    clra
                    clrb
                    std       >CoG+CG.RX
                    ldx       >CoG+CG.SPtr
                    ldd       SC.W,x
                    std       >CoG+CG.RN
                    ldd       >CoG+CG.RY
                    addd      #1
                    std       >CoG+CG.RY
                    bra       c@
x@                  ldx       >CoG+CG.SPtr
                    rts

********************************************************************
* DWEnd: the device's windows go - its overlays first, their pixels put
* back - and a screen left with no window goes too.  A displayed picture
* stays on the card.
DoDWEnd             lbsr      NeedScr
                    lbsr      CurHide
                    bsr       DevEnd
                    clrb
                    rts

* DevEnd - CG.Dev's windows, all of them
DevEnd              ldu       >CoG+CG.Dev
                    lda       WT.Scr,u
                    cmpa      #$FF
                    beq       x@
o@                  ldb       WT.Cur,u  its overlays, top first
                    pshs      b
                    lbsr      WIdx
                    cmpb      ,s+
                    beq       dev@
                    ldb       WT.Cur,u
                    pshs      u
                    lbsr      WRec
                    lbsr      OvlEnd
                    puls      u
                    bra       o@
dev@                ldb       WT.Scr,u
                    lbsr      SRec
                    lda       #$FF
                    sta       WT.Scr,u
                    dec       SC.Wins,x
                    bne       x@
                    lbsr      ScrFree
x@                  rts

* ScrFree - X = a screen with no windows: its memory goes
ScrFree             pshs      d,x
                    lbsr      IsDisp
                    bne       m@
                    lbsr      PtrOff
                    clr       >CoG+CG.Disp
                    clr       VG.DScr,y
                    clr       VG.CSel,y
m@                  lbsr      SIdx      its list goes with it, and its claim
                    incb
                    cmpb      VG.XScr,y
                    bne       c@
                    lbsr      XRelease
c@                  cmpb      VG.LScr,y
                    bne       l@
                    clr       VG.LOn,y
                    clr       VG.MkPh,y
                    clr       VG.MkPh+1,y
l@                  ldb       SC.StN,x
                    beq       f@
                    pshs      x
                    ldx       SC.StBlk,x
                    lbsr      CoFree
                    puls      x
f@                  clr       SC.Used,x
                    clr       SC.StN,x
                    puls      d,x,pc

********************************************************************
* OWSet SVS CPX CPY SZX SZY PRN1 PRN2: an overlay on the device window's
* working area, cells, within the device window's size
DoOWSet             lbsr      NeedScr
                    lbsr      IsBmp
                    beq       bm@
                    comb
                    ldb       #E$IWTyp
                    rts
bm@                 lbsr      CurHide   the window it covers loses its cursor
                    ldx       #CoG+CG.Win+WinDev*WT.Size a free overlay record
                    ldb       #WinDev
f@                  tst       WT.Used,x
                    beq       got@
                    leax      WT.Size,x
                    incb
                    cmpb      #WinDev+WinOvl
                    blo       f@
                    comb
                    ldb       #E$TblFul
                    rts
got@                stx       >CoG+CG.WPtr
                    ldu       >CoG+CG.Dev the device window: position and size
                    ldb       #1
                    lbsr      Prm
                    ldb       #8
                    mul
                    pshs      d
                    addd      WT.AX,u
                    std       WT.X,x
                    ldb       #2
                    lbsr      Prm
                    ldb       #8
                    mul
                    pshs      d
                    addd      WT.AY,u
                    std       WT.Y,x
                    ldb       #3
                    lbsr      Prm
                    tsta
                    beq       id@
                    ldb       #8
                    mul
                    std       WT.W,x
                    addd      2,s       CPX * 8 + SZX * 8 within the device's width
                    cmpd      WT.W,u
                    bhi       id@
                    ldb       #4
                    lbsr      Prm
                    tsta
                    beq       id@
                    ldb       #8
                    mul
                    std       WT.H,x
                    addd      ,s
                    cmpd      WT.H,u
                    bhi       id@
                    leas      4,s
                    lda       WT.Scr,u
                    sta       WT.Scr,x
                    lda       WT.Cur,u  it covers the device's current window
                    sta       WT.Par,x
                    ldb       #5
                    lbsr      Prm
                    sta       WT.FG,x
                    ldb       #6
                    lbsr      Prm
                    sta       WT.BG,x
                    clr       WT.SvN,x
                    lda       #1
                    sta       WT.Used,x
                    ldu       >CoG+CG.WPtr
                    ldb       WT.Scr,u
                    lbsr      SRec
                    inc       SC.Wins,x
                    lbsr      Target
                    ldb       #0        SVS: what it covers, saved first
                    lbsr      Prm
                    tsta
                    beq       ini@
                    lbsr      SaveRect
                    bcs       e@
ini@                lbsr      WinInit
                    lbsr      WIdx
                    ldu       >CoG+CG.Dev
                    stb       WT.Cur,u
                    lbra      CurShowQ  (the overlay is now the current window)
id@                 leas      4,s
                    comb
                    ldb       #E$IWDef
                    rts
e@                  rts

* OWEnd: the current window must be an overlay
DoOWEnd             lbsr      NeedScr
                    lda       WT.Par,u
                    cmpa      #$FF
                    bne       o@
                    comb
                    ldb       #E$WUndef
                    rts
o@                  lbsr      CurHide
                    bsr       OvlEnd
                    lbra      CurShowQ

* OvlEnd - U = an overlay (CG.Dev's current window): its pixels back, its
* memory freed, and the device's current window is the one it covered
OvlEnd              pshs      d,x
                    ldb       WT.Scr,u
                    lbsr      SRec
                    lbsr      Target
                    tst       WT.SvN,u
                    beq       n@
                    lbsr      RestRect
n@                  dec       SC.Wins,x
                    clr       WT.Used,u
                    lda       WT.Par,u
                    ldu       >CoG+CG.Dev
                    sta       WT.Cur,u
                    puls      d,x,pc

* SaveRect - U = an overlay whose rectangle is set, X its screen, the target
* set: the rectangle's pixels into blocks (WT.SvBlk, WT.SvN)
SaveRect            pshs      d,x
                    lbsr      RectW
                    ldd       >CoG+CG.RN  the size: W * H, in blocks of 8192
                    lbsr      RectBlks
                    stb       WT.SvN,u
                    lbsr      CoAlloc
                    bcs       e@
                    std       WT.SvBlk,u
                    std       >CoG+CG.BBlk
                    ldd       #Co.WinA
                    std       >CoG+CG.BPtr
                    lbsr      BMapA
r@                  ldd       >CoG+CG.FH
                    beq       x@
                    subd      #1
                    std       >CoG+CG.FH
                    ldx       #CoG+CG.Row
                    lbsr      RowGet
                    ldx       #CoG+CG.Row
                    ldd       >CoG+CG.RN
                    lbsr      BWrite
                    ldd       >CoG+CG.RY
                    addd      #1
                    std       >CoG+CG.RY
                    bra       r@
x@                  clrb
                    puls      d,x,pc
e@                  clr       WT.SvN,u
                    puls      d,x
                    orcc      #Carry
                    rts

* RestRect - U = an overlay with a save-behind, the target set: back, and
* the blocks freed
RestRect            pshs      d,x
                    lbsr      RectW
                    ldd       WT.SvBlk,u
                    std       >CoG+CG.BBlk
                    ldd       #Co.WinA
                    std       >CoG+CG.BPtr
                    lbsr      BMapA
r@                  ldd       >CoG+CG.FH
                    beq       f@
                    subd      #1
                    std       >CoG+CG.FH
                    ldx       #CoG+CG.Row
                    ldd       >CoG+CG.RN
                    lbsr      BRead
                    ldx       #CoG+CG.Row
                    lbsr      RowPut
                    ldd       >CoG+CG.RY
                    addd      #1
                    std       >CoG+CG.RY
                    bra       r@
f@                  ldx       WT.SvBlk,u
                    ldb       WT.SvN,u
                    lbsr      CoFree
                    clr       WT.SvN,u
                    puls      d,x,pc

* RectBlks - D = a width, CG.FH = a height: B := ceil(W x H / 8192)
RectBlks            pshs      x
                    std       >CoG+CG.Tmp
                    ldx       >CoG+CG.FH
                    clr       >CoG+CG.Off
                    clr       >CoG+CG.Off+1
                    clr       >CoG+CG.Off+2
a@                  cmpx      #0
                    beq       d@
                    ldd       >CoG+CG.Off+1
                    addd      >CoG+CG.Tmp
                    std       >CoG+CG.Off+1
                    bcc       n@
                    inc       >CoG+CG.Off
n@                  leax      -1,x
                    bra       a@
d@                  ldd       >CoG+CG.Off+1 + 8191, then >> 13
                    addd      #8191
                    std       >CoG+CG.Off+1
                    bcc       s@
                    inc       >CoG+CG.Off
s@                  ldd       >CoG+CG.Off
                    lsra
                    rorb
                    lsra
                    rorb
                    lsra
                    rorb
                    lsra
                    rorb
                    lsra
                    rorb
                    puls      x,pc

********************************************************************
* CWArea CPX CPY SZX SZY: cells, relative to the window, inside it
DoCWArea            lbsr      NeedScr
                    lbsr      CurHide
                    ldb       #0
                    lbsr      Prm
                    ldb       #8
                    mul
                    pshs      d
                    ldb       #2
                    lbsr      Prm
                    tsta
                    beq       id@
                    ldb       #8
                    mul
                    pshs      d
                    addd      2,s
                    cmpd      WT.W,u
                    bhi       id2@
                    ldb       #1
                    lbsr      Prm
                    ldb       #8
                    mul
                    pshs      d
                    ldb       #3
                    lbsr      Prm
                    tsta
                    beq       id3@
                    ldb       #8
                    mul
                    pshs      d
                    addd      2,s
                    cmpd      WT.H,u
                    bhi       id4@
                    puls      d
                    std       WT.AH,u
                    puls      d
                    addd      WT.Y,u
                    std       WT.AY,u
                    puls      d
                    std       WT.AW,u
                    puls      d
                    addd      WT.X,u
                    std       WT.AX,u
                    clr       WT.CX,u
                    clr       WT.CY,u
                    lbra      CurShowQ
id4@                leas      2,s
id3@                leas      2,s
id2@                leas      2,s
id@                 leas      2,s
                    comb
                    ldb       #E$IWDef
                    rts

********************************************************************
* Colour

* DefColr: the screen's default palette
DoDefPal            lbsr      NeedScr
                    lbsr      PalDef
                    lbsr      IsDisp
                    bne       x@
                    lbsr      PalShow
x@                  clrb
                    rts

* Palette PRN CTN: CTN is a CoCo 3 colour, 00RGBRGB
DoPalette           lbsr      NeedScr
                    ldb       #1
                    lbsr      Prm
                    lbsr      C6To565
                    pshs      d
                    ldb       #0
                    lbsr      Prm
                    tfr       a,b
                    clra
                    lslb
                    rola
                    pshs      x
                    leax      d,x
                    ldd       2,s
                    std       SC.Pal,x
                    puls      x
                    lbsr      IsDisp
                    bne       x@
                    ldb       #0
                    lbsr      Prm
                    tfr       a,b
                    clra
                    lslb
                    rola
                    pshs      y
                    leay      d,y
                    ldd       2,s
                    std       VG.Pal,y
                    puls      y
                    ldb       #0
                    lbsr      Prm
                    tfr       a,b
                    lda       #1
                    lbsr      VcPal
x@                  leas      2,s
                    clrb
                    rts

* FColor PRN, BColor PRN.  On a fast-text screen the colour pair is the
* screen's (graphics.md 6.4.8) and the font bank is rebuilt.
DoFColor            lbsr      NeedScr
                    ldb       #0
                    lbsr      Prm
                    sta       WT.FG,u
                    bra       NewCol

DoBColor            lbsr      NeedScr
                    ldb       #0
                    lbsr      Prm
                    sta       WT.BG,u

NewCol              lbsr      IsText
                    bne       x@
                    lda       WT.FG,u
                    ldb       WT.BG,u
                    sta       SC.TFG,x
                    stb       SC.TBG,x
                    lbsr      IsDisp
                    bne       x@
                    lbsr      TxFont
x@                  clrb
                    rts

* PalShow - X = the displayed screen: its palette into VG.Pal, all queued
PalShow             pshs      d,x,u
                    leau      VG.Pal,y
                    leax      SC.Pal,x
                    ldd       #256
                    pshs      d
c@                  ldd       ,x++
                    std       ,u++
                    ldd       ,s
                    subd      #1
                    std       ,s
                    bne       c@
                    leas      2,s
                    clra                256 from 0
                    clrb
                    lbsr      VcPal
                    puls      d,x,u,pc

* PalDef - X = a screen: CoWin's sixteen defaults, then RRRGGGBB
PalDef              pshs      d,x,u
                    leau      SC.Pal,x
                    clr       >CoG+CG.Tmp
d@                  lda       >CoG+CG.Tmp 0-15: CoWin's eight, twice
                    anda      #7
                    leax      DefC6,pcr
                    lda       a,x
                    lbsr      C6To565
                    std       ,u++
                    inc       >CoG+CG.Tmp
                    lda       >CoG+CG.Tmp
                    cmpa      #16
                    blo       d@
r@                  lda       >CoG+CG.Tmp 16-255
                    lbsr      C8To565
                    std       ,u++
                    inc       >CoG+CG.Tmp
                    bne       r@
                    puls      d,x,u,pc

* CoWin's defaults (cowin.asm L02F3): white, blue, black, green, red,
* yellow, magenta, cyan
DefC6               fcb       $3F,$09,$00,$12,$24,$36,$2D,$1B

* C6To565 - A = a CoCo 3 colour %00RGBRGB (high bits first): D := RGB565
C6To565             pshs      a,x
                    leax      Lvl5,pcr
                    clrb                red: bits 5 and 2
                    bita      #%00100000
                    beq       r1@
                    addb      #2
r1@                 bita      #%00000100
                    beq       r2@
                    incb
r2@                 ldb       b,x
                    stb       >CoG+CG.Tmp+1
                    clrb                green: bits 4 and 1
                    lda       ,s
                    bita      #%00010000
                    beq       g1@
                    addb      #2
g1@                 bita      #%00000010
                    beq       g2@
                    incb
g2@                 leax      Lvl6,pcr
                    ldb       b,x
                    pshs      b
                    clrb                blue: bits 3 and 0
                    lda       1,s
                    bita      #%00001000
                    beq       b1@
                    addb      #2
b1@                 bita      #%00000001
                    beq       b2@
                    incb
b2@                 leax      Lvl5,pcr
                    ldb       b,x
                    tfr       b,a       A = B5
                    puls      b         B = G6
                    bra       Pack

* C8To565 - A = %RRRGGGBB: D := RGB565
C8To565             pshs      a,x
                    lsra
                    lsra
                    lsra
                    lsra
                    lsra
                    leax      Lvl5of7,pcr
                    lda       a,x
                    sta       >CoG+CG.Tmp+1 R5
                    lda       ,s
                    lsra
                    lsra
                    anda      #7
                    ldb       #9
                    mul                 G6 = G3 * 9
                    lda       ,s
                    anda      #3
                    leax      Lvl5,pcr
                    lda       a,x       A = B5

* Pack - CG.Tmp+1 = R5, B = G6, A = B5, and A and X on the stack: D := RGB565
Pack                pshs      a
                    clra                D = G6 << 5
                    lslb
                    rola
                    lslb
                    rola
                    lslb
                    rola
                    lslb
                    rola
                    lslb
                    rola
                    orb       ,s+       | B5
                    pshs      b
                    ldb       >CoG+CG.Tmp+1 | R5 << 11
                    lslb
                    lslb
                    lslb
                    pshs      b
                    ora       ,s+
                    puls      b
                    leas      1,s
                    puls      x,pc

Lvl5                fcb       0,10,20,31          two bits, *31/3

Lvl6                fcb       0,21,42,63          two bits, *63/3

Lvl5of7             fcb       0,4,8,13,17,22,26,31 three bits, *31/7
