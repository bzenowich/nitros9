********************************************************************
* ca_gpb.asm - CoArm's GP buffers: DefGPB, KillBuf, GPLoad, GetBlk,
* PutBlk, Font; and the block streams behind them
*
* A GP buffer is an entry in CG.GPB and its bytes in F$AllRAM blocks,
* reached through Co.WinA.  Sizes are CoWin's: 16 bits.  GetBlk makes an
* 8bpp buffer (its type is the screen's) of a rectangle inside the working
* area; PutBlk draws one, clipped to the working area - 8bpp bytes as they
* are, and a 1bpp buffer (GPLoad type 5) in the window's colours.  A font is
* a 1bpp buffer whose glyph for a code is the eight bytes at code * 8
* (grfdrv.asm), and a pattern (PSet, ca_draw.asm) an 8bpp one.
*
* Buffers are CoArm's, not a path's: a group lives until KillBuf, as it
* does under CoWin.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P2.

********************************************************************
* Block streams at Co.WinA: CG.BBlk is the block, CG.BPtr where in the
* window the stream has got to

* BMapA - map CG.BBlk
BMapA               pshs      d
                    ldd       >CoG+CG.BBlk
                    lbsr      MapA
                    puls      d,pc

* BWrite - D bytes from X into the stream.  X is left past them.
BWrite              pshs      d,u
                    ldu       >CoG+CG.BPtr
                    cmpd      #0
                    beq       x@
                    std       >CoG+CG.Cnt
w@                  lda       ,x+
                    sta       ,u+
                    cmpu      #Co.WinA+$2000
                    bne       n@
                    bsr       BNext
n@                  ldd       >CoG+CG.Cnt
                    subd      #1
                    std       >CoG+CG.Cnt
                    bne       w@
x@                  stu       >CoG+CG.BPtr
                    puls      d,u,pc

* BRead - D bytes from the stream into X.  X is left past them.
BRead               pshs      d,u
                    ldu       >CoG+CG.BPtr
                    cmpd      #0
                    beq       x@
                    std       >CoG+CG.Cnt
r@                  lda       ,u+
                    sta       ,x+
                    cmpu      #Co.WinA+$2000
                    bne       n@
                    bsr       BNext
n@                  ldd       >CoG+CG.Cnt
                    subd      #1
                    std       >CoG+CG.Cnt
                    bne       r@
x@                  stu       >CoG+CG.BPtr
                    puls      d,u,pc

* BNext - the stream's next block; U := the window's start
BNext               pshs      d
                    ldd       >CoG+CG.BBlk
                    addd      #1
                    std       >CoG+CG.BBlk
                    lbsr      MapA
                    ldu       #Co.WinA
                    puls      d,pc

********************************************************************
* The directory

* GPRec - B = an entry: X := its record
GPRec               pshs      d
                    lda       #GB.Len
                    mul
                    addd      #CoG+CG.GPB
                    tfr       d,x
                    puls      d,pc

* GPFind - A = group, B = buffer: X := the entry, B := its index; carry set,
* B = E$BadBuf, if there is none
GPFind              pshs      a
                    ldx       #CoG+CG.GPB
                    clr       >CoG+CG.Tmp
f@                  lda       GB.Grp,x
                    beq       n@
                    cmpa      ,s
                    bne       n@
                    cmpb      GB.Buf,x
                    beq       y@
n@                  leax      GB.Len,x
                    inc       >CoG+CG.Tmp
                    lda       >CoG+CG.Tmp
                    cmpa      #GPMax
                    blo       f@
                    puls      a
                    comb
                    ldb       #E$BadBuf
                    rts
y@                  ldb       >CoG+CG.Tmp
                    puls      a
                    andcc     #^Carry
                    rts

* GPSeek - X = an entry, D = an offset into its bytes: the stream there,
* and X := its address in Co.WinA
GPSeek              pshs      d
                    lsra                the block: offset >> 13
                    lsra
                    lsra
                    lsra
                    lsra
                    tfr       a,b
                    clra
                    addd      GB.Blk,x
                    std       >CoG+CG.BBlk
                    lbsr      MapA
                    ldd       ,s
                    anda      #$1F
                    addd      #Co.WinA
                    std       >CoG+CG.BPtr
                    tfr       d,x
                    puls      d,pc

* GPNew - A = group, B = buffer, D' = CG.Cnt = its size: a new entry with
* its blocks.  X := the entry.  Carry set, B = the error, if it exists or
* there is no room.
GPNew               pshs      d
                    lbsr      GPFind
                    bcs       n@
                    puls      d
                    comb
                    ldb       #E$WADef  (CoWin: the buffer exists)
                    rts
n@                  ldx       #CoG+CG.GPB a free entry
                    clrb
f@                  tst       GB.Grp,x
                    beq       got@
                    leax      GB.Len,x
                    incb
                    cmpb      #GPMax
                    blo       f@
                    puls      d
                    comb
                    ldb       #E$TblFul
                    rts
got@                ldd       >CoG+CG.Cnt the blocks: ceil(size / 8192)
                    addd      #8191
                    tfr       a,b
                    rorb                (the carry from the add is bit 8 of the high byte)
                    lsrb
                    lsrb
                    lsrb
                    lsrb
                    tstb
                    bne       k@
                    incb                at least one
k@                  stb       GB.NBlk,x
                    lbsr      CoAlloc
                    bcs       e@
                    std       GB.Blk,x
                    ldd       >CoG+CG.Cnt
                    std       GB.Size,x
                    puls      d
                    sta       GB.Grp,x
                    stb       GB.Buf,x
                    clr       GB.Sty,x
                    clr       GB.XS,x
                    clr       GB.XS+1,x
                    clr       GB.YS,x
                    clr       GB.YS+1,x
                    andcc     #^Carry
                    rts
e@                  leas      2,s
                    rts

* GPKill - X = an entry: its blocks back, and the entry free
GPKill              pshs      d,x
                    ldb       GB.NBlk,x
                    ldx       GB.Blk,x
                    lbsr      CoFree
                    ldx       2,s
                    clr       GB.Grp,x
                    puls      d,x,pc

********************************************************************
* DefGPB grp buf size
DoDefGPB            ldb       #2
                    lbsr      PrmW
                    beq       ia@
                    std       >CoG+CG.Cnt
                    ldb       #0
                    lbsr      Prm
                    tsta
                    beq       ia@
                    cmpa      #$FF
                    beq       ia@
                    pshs      a
                    ldb       #1
                    lbsr      Prm
                    tfr       a,b
                    puls      a
                    tstb
                    beq       ia@
                    lbra      GPNew
ia@                 comb
                    ldb       #E$IllArg
                    rts

* KillBuf grp buf: buffer 0, every buffer of the group
DoKillBuf           ldb       #0
                    lbsr      Prm
                    pshs      a
                    ldb       #1
                    lbsr      Prm
                    tfr       a,b
                    puls      a
                    tstb
                    bne       one@
                    ldx       #CoG+CG.GPB
                    ldb       #GPMax
k@                  cmpa      GB.Grp,x
                    bne       n@
                    lbsr      GPKill
n@                  leax      GB.Len,x
                    decb
                    bne       k@
                    clrb
                    rts
one@                lbsr      GPFind
                    bcs       x@
                    lbsr      GPKill
                    clrb
x@                  rts

* GPLoad grp buf sty xs ys n, then n bytes: into the buffer (made, or big
* enough already)
DoGPLoad            ldb       #7
                    lbsr      PrmW
                    std       >CoG+CG.Cnt
                    ldb       #0
                    lbsr      Prm
                    pshs      a
                    ldb       #1
                    lbsr      Prm
                    tfr       a,b
                    puls      a
                    pshs      d
                    lbsr      GPFind
                    bcs       new@
                    ldd       GB.Size,x
                    cmpd      >CoG+CG.Cnt
                    bhs       have@
                    leas      2,s
                    comb
                    ldb       #E$BufSiz
                    lbra      Swallow
new@                puls      d
                    pshs      d
                    lbsr      GPNew
                    bcs       err@
have@               leas      2,s
                    ldb       #2
                    lbsr      Prm
                    sta       GB.Sty,x
                    ldb       #3
                    lbsr      PrmW
                    std       GB.XS,x
                    ldb       #5
                    lbsr      PrmW
                    std       GB.YS,x
                    ldd       >CoG+CG.Cnt
                    beq       x@
                    std       >CoG+CG.GPOff the bytes to come
                    stx       >CoG+CG.GP
                    ldd       #0
                    lbsr      GPSeek
                    ldu       >CoG+CG.Dev
                    leax      GPData,pcr
                    stx       WT.EscVct,u
x@                  clrb
                    rts
err@                leas      2,s

Swallow             pshs      b         GPLoad's data still arrives: swallow it
                    ldd       >CoG+CG.Cnt
                    ldu       >CoG+CG.Dev
                    std       WT.Skip,u
                    beq       s@
                    leax      Skip1,pcr
                    stx       WT.EscVct,u
s@                  puls      b
                    orcc      #Carry    not COMB: that would complement the error in B
                    rts

* GPData - A = the next byte of a GPLoad
GPData              pshs      a
                    ldd       >CoG+CG.BBlk the stream may have been moved by a draw between bytes
                    lbsr      MapA
                    ldx       >CoG+CG.BPtr
                    puls      a
                    sta       ,x+
                    cmpx      #Co.WinA+$2000
                    bne       n@
                    ldd       >CoG+CG.BBlk
                    addd      #1
                    std       >CoG+CG.BBlk
                    ldx       #Co.WinA
n@                  stx       >CoG+CG.BPtr
                    ldd       >CoG+CG.GPOff
                    subd      #1
                    std       >CoG+CG.GPOff
                    bne       x@
                    clr       WT.EscVct,u
                    clr       WT.EscVct+1,u
x@                  clrb
                    rts

* Skip1 - a byte of data with nowhere to go
Skip1               ldd       WT.Skip,u
                    subd      #1
                    std       WT.Skip,u
                    bne       x@
                    clr       WT.EscVct,u
                    clr       WT.EscVct+1,u
x@                  clrb
                    rts

* GetBlk grp buf x y xs ys: the rectangle, inside the working area, into a
* new 8bpp buffer
DoGetBlk            lbsr      DrawOn
                    ldb       #2        inside the working area?
                    lbsr      PrmW
                    tsta
                    lbmi      ic@
                    addd      #0
                    pshs      d
                    ldb       #6
                    lbsr      PrmW
                    lbeq      ic2@
                    addd      ,s
                    cmpd      WT.AW,u
                    lbhi      ic2@
                    leas      2,s
                    ldb       #4
                    lbsr      PrmW
                    tsta
                    lbmi      ic@
                    pshs      d
                    ldb       #8
                    lbsr      PrmW
                    lbeq      ic2@
                    addd      ,s
                    cmpd      WT.AH,u
                    lbhi      ic2@
                    leas      2,s
                    ldb       #6        the size: xs * ys
                    lbsr      PrmW
                    std       >CoG+CG.Ma
                    ldb       #8
                    lbsr      PrmW
                    std       >CoG+CG.Mb
                    lbsr      UMul16
                    ldd       >CoG+CG.Q
                    bne       ic@       over 64K
                    ldd       >CoG+CG.Q+2
                    std       >CoG+CG.Cnt
                    ldb       #0
                    lbsr      Prm
                    pshs      a
                    ldb       #1
                    lbsr      Prm
                    tfr       a,b
                    puls      a
                    lbsr      GPNew
                    bcs       x@
                    stx       >CoG+CG.GP
                    ldx       >CoG+CG.CurS
                    lda       SC.Type,x
                    ldx       >CoG+CG.GP
                    sta       GB.Sty,x
                    ldb       #6
                    lbsr      PrmW
                    std       GB.XS,x
                    std       >CoG+CG.RN
                    ldb       #8
                    lbsr      PrmW
                    std       GB.YS,x
                    std       >CoG+CG.FH
                    ldd       #0
                    lbsr      GPSeek
                    ldb       #2
                    lbsr      PrmX
                    std       >CoG+CG.RX
                    ldb       #4
                    lbsr      PrmY
                    std       >CoG+CG.RY
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
x@                  lbra      DrawOff
ic2@                leas      2,s
ic@                 comb
                    ldb       #E$ICoord
                    lbra      DrawOffE

* PutBlk grp buf x y: the buffer, clipped to the working area
DoPutBlk            lbsr      DrawOn
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
                    std       >CoG+CG.EDy the buffer's row
                    ldb       #2
                    lbsr      PrmX
                    std       >CoG+CG.ECx its corner on the screen
                    ldb       #4
                    lbsr      PrmY
                    std       >CoG+CG.ECy
r@                  ldx       >CoG+CG.GP
                    ldd       >CoG+CG.EDy
                    cmpd      GB.YS,x
                    lbhs      x@
                    addd      >CoG+CG.ECy
                    std       >CoG+CG.SY
                    cmpd      >CoG+CG.CY0
                    lblt      n@
                    cmpd      >CoG+CG.CY1
                    lbgt      x@
                    lbsr      BufRow    CG.Row := the buffer's row, as pixels
                    ldd       >CoG+CG.ECx the part of it inside the clip
                    std       >CoG+CG.RX
                    ldd       #0
                    std       >CoG+CG.EX the first of the row's bytes put
                    ldd       >CoG+CG.RX
                    cmpd      >CoG+CG.CX0
                    bge       l@
                    ldd       >CoG+CG.CX0
                    subd      >CoG+CG.RX
                    std       >CoG+CG.EX
                    ldd       >CoG+CG.CX0
                    std       >CoG+CG.RX
l@                  ldx       >CoG+CG.GP
                    ldd       >CoG+CG.ECx the last column: ECx + XS - 1, clipped
                    addd      GB.XS,x
                    subd      #1
                    cmpd      >CoG+CG.CX1
                    ble       rr@
                    ldd       >CoG+CG.CX1
rr@                 subd      >CoG+CG.RX
                    blt       n@
                    addd      #1
                    std       >CoG+CG.RN
                    ldd       >CoG+CG.SY
                    std       >CoG+CG.RY
                    ldd       >CoG+CG.EX
                    addd      #CoG+CG.Row
                    tfr       d,x
                    lbsr      RowPut
n@                  ldd       >CoG+CG.EDy
                    addd      #1
                    std       >CoG+CG.EDy
                    lbra      r@
x@                  lbra      DrawOff

* BufRow - CG.Row := row CG.EDy of the buffer CG.GP, as pixels: 8bpp as it
* is; 1bpp (type 5, a row of ceil(XS / 8) bytes) in the window's colours
BufRow              ldx       >CoG+CG.GP
                    lda       GB.Sty,x
                    cmpa      #5
                    beq       bits@
                    ldd       GB.XS,x   8bpp: the offset EDy * XS
                    std       >CoG+CG.Ma
                    ldd       >CoG+CG.EDy
                    std       >CoG+CG.Mb
                    lbsr      UMul16
                    ldd       >CoG+CG.Q+2
                    lbsr      GPSeek
                    ldx       >CoG+CG.GP
                    ldd       GB.XS,x
                    cmpd      #640
                    bls       a@
                    ldd       #640
a@                  ldx       #CoG+CG.Row
                    lbra      BRead
bits@               ldd       GB.XS,x   1bpp: the row's bytes, EDy * ceil(XS / 8)
                    addd      #7
                    lsra
                    rorb
                    lsra
                    rorb
                    lsra
                    rorb
                    std       >CoG+CG.Ma
                    std       >CoG+CG.PatW (the bytes a row)
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
b@                  lbsr      BRead
                    ldx       >CoG+CG.WPtr the window's colours
                    lda       WT.FG,x
                    sta       >CoG+CG.MFg
                    lda       WT.BG,x
                    sta       >CoG+CG.MBg
                    ldx       #CoG+CG.Buf
                    pshs      u
                    ldu       #CoG+CG.Row
                    ldb       >CoG+CG.PatW+1 the row's bytes, up to 80
                    cmpb      #80
                    bls       e@
                    ldb       #80
e@                  lda       ,x+
                    pshs      b
                    ldb       #8
c@                  lsla
                    pshs      a
                    lda       >CoG+CG.MFg
                    bcs       o@
                    lda       >CoG+CG.MBg
o@                  sta       ,u+
                    puls      a
                    decb
                    bne       c@
                    puls      b
                    decb
                    bne       e@
                    puls      u,pc

* DrawOffE - B = an error: the cursor back, and the error
DrawOffE            pshs      b
                    ldx       >CoG+CG.CurS
                    lbsr      CurShow
                    puls      b
                    orcc      #Carry
                    rts

* Font grp buf: group 0, the built-in font
DoFont              lbsr      NeedScr
                    ldb       #0
                    lbsr      Prm
                    tsta
                    bne       f@
                    clr       WT.Font,u
                    clrb
                    rts
f@                  pshs      a
                    ldb       #1
                    lbsr      Prm
                    tfr       a,b
                    puls      a
                    lbsr      GPFind
                    bcs       nf@
                    incb
                    stb       WT.Font,u
                    clrb
                    rts
nf@                 ldb       #E$NFont
                    orcc      #Carry
                    rts
