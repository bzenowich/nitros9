********************************************************************
* ca_row.asm - CoArm's rows: every pixel CoArm draws on a bitmap screen
*
* arm6309 docs/nitros9-av-plan.md 3.3: every primitive decomposes into
* span operations, with two back-ends - the card, for the displayed screen,
* and a DRAM store, for a screen that is not displayed.  This file is that
* layer.  Above it, nothing knows which back-end it is drawing to.
*
*   RowFill   A = a colour: CG.RN pixels from (CG.RY, CG.RX)
*   RowPut    X = CG.RN bytes to put there; X is left past them
*   RowGet    X = where CG.RN bytes read from there go; X left past them
*   RowMask   A = a mask byte: 8 pixels, a 1 in CG.MFg, a 0 in CG.MBg, or
*             left alone if CG.MTr is set (sprite mode, features.md 8.4); X lost
*   Glyph     X = 8 row bytes: the 8 x 8 cell at (CG.RY, CG.RX), as RowMask
*             row by row; X is left past them
*
* The target is CG.TStr: 0 for the card (rows are ring rows CG.TTop + RY,
* graphics.md 8), or the first block of a store, a screen's pixels in
* raster order, 640 a row, in F$AllRAM blocks mapped at Co.WinB.
*
* On the card each op is VidCore's (vidcore.asm): span-solid in chunks of
* up to 256 with a poll before each (a span is up to 81 us in cell mode),
* direct streams, span-mask and sprite, and a glyph as one WPTR load and
* eight chained mask writes (WADV 01, graphics.md 7.4).
*
* Rows are not clipped here: callers clip.  Y = VG; U is preserved; MapA
* and MapB lose A.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P2.

********************************************************************
* The block windows: D = a block

* MapA - the block at Co.WinA (slot 5)
MapA                cmpd      >CoG+CG.WinA
                    beq       x@
                    std       >CoG+CG.WinA
                    std       VG.CoImg+10,y the image, for the next time task 1 is loaded
                    pshs      cc
                    orcc      #IntMasks ... and the map, now
                    stb       >DAT.Regs+8+5
                    adda      #RAM.Hi
                    sta       >DAT.RegsHi+8+5
                    puls      cc
x@                  rts

* MapB - the block at Co.WinB (slot 6)
MapB                cmpd      >CoG+CG.WinB
                    beq       x@
                    std       >CoG+CG.WinB
                    std       VG.CoImg+12,y
                    pshs      cc
                    orcc      #IntMasks
                    stb       >DAT.Regs+8+6
                    adda      #RAM.Hi
                    sta       >DAT.RegsHi+8+6
                    puls      cc
x@                  rts

********************************************************************
* The card's address for (CG.RY, CG.RX): B:X, the ring row (CG.TTop +
* RY) mod 512 in bits 18-10 and the column in bits 9-0
CardAddr            ldd       >CoG+CG.TTop
                    addd      >CoG+CG.RY
                    anda      #1
                    lslb
                    rola
                    lslb
                    rola                A = bits 18-16, B = bits 15-10
                    orb       >CoG+CG.RX bits 9-8
                    pshs      a
                    tfr       b,a
                    ldb       >CoG+CG.RX+1
                    tfr       d,x
                    puls      b,pc

* The store's place for (CG.RY, CG.RX): X := its address in Co.WinB, the
* block mapped.  Offset = RY * 640 + RX = RY << 9 + RY << 7 + RX.
DSeek               pshs      d
                    clr       >CoG+CG.Off
                    ldd       >CoG+CG.RY RY << 7: 16 bits is enough (RY < 512 is 9 bits)
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
                    lslb
                    rola
                    lslb
                    rola
                    std       >CoG+CG.Off+1 RY << 7, in the low 16 (it fits: < 65,536)
                    ldd       >CoG+CG.RY RY << 9 = (RY << 1) << 8
                    lslb
                    rola
                    addb      >CoG+CG.Off+1 (the middle byte)
                    adca      #0        (the high byte was 0)
                    stb       >CoG+CG.Off+1
                    sta       >CoG+CG.Off
                    ldd       >CoG+CG.Off+1 + RX
                    addd      >CoG+CG.RX
                    std       >CoG+CG.Off+1
                    lda       >CoG+CG.Off
                    adca      #0
                    sta       >CoG+CG.Off
* the block: first + offset >> 13; the address: WinB + offset & $1FFF
                    ldd       >CoG+CG.Off off >> 8, as 16 bits
                    lsra
                    rorb
                    lsra
                    rorb
                    lsra
                    rorb
                    lsra
                    rorb
                    lsra
                    rorb                D = off >> 13
                    addd      >CoG+CG.TStr
                    std       >CoG+CG.DBlk
                    lbsr      MapB
                    ldd       >CoG+CG.Off+1
                    anda      #$1F
                    addd      #Co.WinB
                    tfr       d,x
                    puls      d,pc

* DNext - X has reached the end of Co.WinB: the next block
DNext               pshs      d
                    ldd       >CoG+CG.DBlk
                    addd      #1
                    std       >CoG+CG.DBlk
                    lbsr      MapB
                    ldx       #Co.WinB
                    puls      d,pc

********************************************************************
* RowFill - A = the colour
RowFill             ldx       >CoG+CG.RN
                    lbeq      x@
                    ldx       >CoG+CG.TStr
                    lbne      dram@
                    pshs      a,u
                    lda       #1        the pointer off, if this covers it
                    lbsr      PtrGuard
                    pshs      cc
                    orcc      #IRQMask
                    lbsr      VcWait
                    lda       #WM.Solid
                    lbsr      VcMode
                    clra
                    lbsr      VcAdv
                    lda       1,s       the colour
                    lbsr      VcFG
                    lbsr      CardAddr
                    lbsr      VcPtr
                    puls      cc
                    ldd       >CoG+CG.RN
                    pshs      d
c@                  ldd       ,s        this span: up to 256
                    cmpd      #256
                    bls       n@
                    ldd       #256
n@                  pshs      d
                    pshs      cc
                    orcc      #IRQMask
                    lbsr      VcWait    V1 and V12: the last span first
                    lda       2,s       the length - 1: 256 is $00 - 1
                    deca
                    lbsr      VcSpl
                    ldu       VG.Base,y
                    sta       VR.VDATA,u the trigger: any byte
                    puls      cc
                    ldd       2,s
                    subd      ,s++
                    std       ,s
                    bne       c@
                    leas      2,s
                    puls      a,u
x@                  rts
dram@               pshs      a
                    lbsr      DSeek
                    ldd       >CoG+CG.RN
                    pshs      d
                    lda       2,s
f@                  sta       ,x+
                    cmpx      #Co.WinB+$2000
                    bne       k@
                    lbsr      DNext
k@                  pshs      a
                    ldd       1,s
                    subd      #1
                    std       1,s
                    puls      a
                    bne       f@
                    leas      2,s
                    puls      a,pc

* RowPut - X = the bytes
RowPut              ldd       >CoG+CG.RN
                    lbeq      x@
                    pshs      u
                    ldu       >CoG+CG.TStr
                    bne       dram@
                    lda       #1
                    lbsr      PtrGuard
                    pshs      x
                    pshs      cc
                    orcc      #IRQMask
                    lbsr      VcWait
                    lda       #WM.Direct
                    lbsr      VcMode
                    clra
                    lbsr      VcAdv
                    lbsr      CardAddr
                    lbsr      VcPtr
                    puls      cc
                    puls      x
                    ldd       >CoG+CG.RN
                    lbsr      VcPutN
                    puls      u,pc
dram@               tfr       x,u       U = the source
                    lbsr      DSeek
                    ldd       >CoG+CG.RN
                    pshs      d
p@                  lda       ,u+
                    sta       ,x+
                    cmpx      #Co.WinB+$2000
                    bne       k@
                    lbsr      DNext
k@                  ldd       ,s
                    subd      #1
                    std       ,s
                    bne       p@
                    leas      2,s
                    tfr       u,x
                    puls      u
x@                  rts

* RowGet - X = where the bytes go
RowGet              ldd       >CoG+CG.RN
                    lbeq      x@
                    pshs      u
                    ldu       >CoG+CG.TStr
                    bne       dram@
                    lda       #1        (a read sees the pointer too)
                    lbsr      PtrGuard
                    pshs      x
                    pshs      cc
                    orcc      #IRQMask
                    lbsr      VcWait
                    lbsr      CardAddr
                    lbsr      VcPtr
                    puls      cc
                    puls      x
                    ldd       >CoG+CG.RN
                    lbsr      VcGetN
                    puls      u,pc
dram@               tfr       x,u       U = the destination
                    lbsr      DSeek
                    ldd       >CoG+CG.RN
                    pshs      d
g@                  lda       ,x+
                    sta       ,u+
                    cmpx      #Co.WinB+$2000
                    bne       k@
                    lbsr      DNext
k@                  ldd       ,s
                    subd      #1
                    std       ,s
                    bne       g@
                    leas      2,s
                    tfr       u,x
                    puls      u
x@                  rts

* RowMask - A = the mask byte
RowMask             pshs      a,u
                    ldu       >CoG+CG.TStr
                    lbne      dram@
                    ldd       #8
                    std       >CoG+CG.RN
                    lda       #1
                    lbsr      PtrGuard
                    pshs      cc
                    orcc      #IRQMask
                    lbsr      VcWait
                    lda       #WM.Mask
                    tst       >CoG+CG.MTr
                    beq       m@
                    lda       #WM.Sprite
m@                  lbsr      VcMode
                    clra
                    lbsr      VcAdv
                    lda       >CoG+CG.MFg
                    lbsr      VcFG
                    lda       >CoG+CG.MBg
                    lbsr      VcBG
                    lbsr      CardAddr
                    lbsr      VcPtr
                    leax      1,s       the mask byte
                    ldd       #1
                    lbsr      VcPutN
                    puls      cc
                    puls      a,u,pc
dram@               pshs      x
                    lbsr      DSeek
                    lda       2,s
                    ldb       #8
                    pshs      b
b@                  lsla
                    pshs      a
                    lda       >CoG+CG.MFg
                    bcs       w@
                    tst       >CoG+CG.MTr
                    bne       s@
                    lda       >CoG+CG.MBg
w@                  sta       ,x
s@                  leax      1,x
                    cmpx      #Co.WinB+$2000
                    bne       k@
                    lbsr      DNext
k@                  puls      a
                    dec       ,s
                    bne       b@
                    leas      1,s
                    puls      x
                    puls      a,u,pc

* Glyph - X = 8 row bytes, at (CG.RY, CG.RX)
Glyph               pshs      u
                    ldu       >CoG+CG.TStr
                    lbne      dram@
                    ldd       #8
                    std       >CoG+CG.RN
                    lda       #8
                    lbsr      PtrGuard
                    pshs      x
                    pshs      cc
                    orcc      #IRQMask
                    lbsr      VcWait
                    lda       #WM.Mask
                    tst       >CoG+CG.MTr
                    beq       m@
                    lda       #WM.Sprite
m@                  lbsr      VcMode
                    lda       #1        WADV 01: each row a span, the column reloaded
                    lbsr      VcAdv
                    lda       >CoG+CG.MFg
                    lbsr      VcFG
                    lda       >CoG+CG.MBg
                    lbsr      VcBG
                    lbsr      CardAddr
                    lbsr      VcPtr
                    puls      cc
                    puls      x
                    ldd       #8
                    lbsr      VcPutN
                    puls      u,pc
dram@               ldd       >CoG+CG.RY one RowMask a row
                    pshs      d
                    ldb       #8
r@                  pshs      b
                    lda       ,x+
                    pshs      x
                    lbsr      RowMask
                    puls      x
                    ldd       >CoG+CG.RY
                    addd      #1
                    std       >CoG+CG.RY
                    puls      b
                    decb
                    bne       r@
                    puls      d
                    std       >CoG+CG.RY
                    puls      u,pc
