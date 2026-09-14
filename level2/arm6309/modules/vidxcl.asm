********************************************************************
* vidxcl.asm - ArmIO's calls for an exclusive screen: SS.Batch, SS.TileLd,
* SS.MapWr and SS.TBank
*
* `use`d by ArmIO.  SS.Excl itself is CoArm's (ca_tile.asm), because the
* pointer and the screens are.  These write the card from ArmIO, in the
* caller's system state: each takes VG.CBusy as a CoArm call does, so
* nothing else draws meanwhile, and puts it back.  Every one but SS.Batch
* is for the exclusive owner only.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P3.

* XCheck - an exclusive owner that has gone gives the screen back.  Called
* before every call into CoArm.
XCheck              pshs      d,x
                    ldx       #VG.Addr
                    tst       VG.XScr,x
                    beq       x@
                    ldb       VG.XPID,x
                    ldx       <D.PrcDBT
                    abx
                    tst       ,x
                    bne       x@
                    ldx       #VG.Addr  no such process
                    clr       VG.XScr,x
                    lda       VG.XPtr,x
                    sta       VG.PtrOn,x
x@                  puls      d,x,pc

* XOwner - Y = the path descriptor: carry set (E$NotRdy) unless its process
* holds the exclusive screen
XOwner              pshs      a,x
                    bsr       XCheck
                    ldx       #VG.Addr
                    tst       VG.XScr,x
                    beq       no@
                    lda       PD.CPR,y
                    cmpa      VG.XPID,x
                    bne       no@
                    andcc     #^Carry
                    puls      a,x,pc
no@                 puls      a,x
                    comb
                    ldb       #E$NotRdy
                    rts

* XBusy - VG.CBusy taken, waiting out a CoArm call in progress; XFree
XBusy               pshs      x
w@                  ldx       #VG.Addr
                    tst       VG.CBusy,x
                    beq       go@
                    ldx       #1
                    os9       F$Sleep
                    bra       w@
go@                 inc       VG.CBusy,x
                    puls      x,pc

XFree               pshs      x
                    ldx       #VG.Addr
                    clr       VG.CBusy,x
                    puls      x,pc

********************************************************************
* SS.Batch - X = the records, Y = their length: after a batch still
* waiting has gone, this one goes to the next VBL
XBatch              ldx       PD.RGS,y
                    ldd       R$Y,x
                    cmpd      #BT.Max
                    lbhi      bad@
                    lbsr      XBusy
                    pshs      y,u
                    ldu       #VG.Addr
                    leax      VG.BtBuf,u
                    leax      d,x
                    stx       VG.XEnd,u
                    clr       ,x        an END after the records, whatever they say
                    tst       VG.BtOn,u one still waiting: it goes first
                    beq       m@
                    ldd       VG.MkMiss,u
                    addd      #1
                    std       VG.MkMiss,u
w@                  ldu       #VG.Addr
                    tst       VG.BtOn,u
                    beq       m@
                    ldx       #1
                    os9       F$Sleep
                    bra       w@
m@                  ldx       ,s        the records
                    ldx       PD.RGS,x
                    ldy       R$Y,x
                    beq       ok@
                    ldx       R$X,x
                    ldu       #VG.Addr+VG.BtBuf
                    lbsr      FromCallerX
                    bcs       e@
                    ldu       #VG.Addr
                    leax      VG.BtBuf,u each record whole, and inside
r@                  cmpx      VG.XEnd,u
                    bhs       ok@
                    lda       ,x+
                    beq       ok@
                    cmpa      #BT.Reg
                    bne       p@
                    lda       ,x++
                    cmpa      #VR.VSCR
                    blo       bd@
                    cmpa      #VR.HSCRH
                    bls       l@
                    cmpa      #VR.TBASE
                    beq       l@
                    cmpa      #VR.MBASE
                    bne       bd@
                    bra       l@
p@                  cmpa      #BT.Put
                    bne       t@
                    ldb       3,x
                    abx
                    leax      4,x
                    bra       l@
t@                  cmpa      #BT.Tags
                    bne       k@
                    leax      4,x
                    bra       l@
k@                  cmpa      #BT.Poke
                    bne       bd@
                    ldb       ,x        n x 3 + 2
                    lda       #3
                    mul
                    addd      #2
                    leax      d,x
l@                  cmpx      VG.XEnd,u
                    bls       r@
bd@                 ldb       #E$IllArg
                    coma
                    bra       e@
ok@                 ldu       #VG.Addr
                    lda       #1
                    sta       VG.BtOn,u
                    clrb
e@                  puls      y,u
                    pshs      cc,b
                    lbsr      XFree
                    puls      cc,b,pc
bad@                comb
                    ldb       #E$IllArg
                    rts

********************************************************************
* SS.TBank - X = TILEBASE, at the next VBL
XTBank              lbsr      XOwner
                    bcs       x@
                    ldx       PD.RGS,y
                    lda       R$X+1,x
                    pshs      y
                    ldy       #VG.Addr
                    ldb       VG.MBase,y
                    lbsr      VcQBank
                    puls      y
                    clrb
x@                  rts

********************************************************************
* SS.TileLd - X = 16,384 bytes, Y = the bank (a TILEBASE value): the tiles
* into VRAM at bank * 16,384, a ring row at a time.  Not the bank the map
* is in.
XTileLd             lbsr      XOwner
                    lbcs      x@
                    ldx       PD.RGS,y
                    ldd       R$Y,x
                    cmpd      #31
                    lbhi      bad@
                    lslb                the bank's first ring row: bank * 16
                    rola
                    lslb
                    rola
                    lslb
                    rola
                    lslb
                    rola
                    pshs      d
                    pshs      y
                    ldy       #VG.Addr
                    clra                the map's: MAPBASE * 4
                    ldb       VG.MBase,y
                    lslb
                    rola
                    lslb
                    rola
                    puls      y
                    addd      #3        its four rows against the bank's sixteen
                    subd      ,s
                    blo       ok@
                    cmpd      #16+3
                    lblo      bad1@
ok@                 lbsr      XBusy
                    ldx       PD.RGS,y
                    ldx       R$X,x
                    pshs      x,y,u     the caller's bytes, the path descriptor, the statics
                    lda       #16
                    pshs      a
row@                ldy       #VG.Addr  WPTR := the row << 10
                    ldd       7,s
                    lslb
                    rola
                    lslb
                    rola
                    pshs      cc
                    orcc      #IRQMask
                    pshs      a
                    tfr       b,a
                    clrb
                    tfr       d,x
                    puls      b
                    lbsr      VcWait
                    lda       #WM.Direct
                    lbsr      VcMode
                    clra
                    lbsr      VcAdv
                    lbsr      VcPtr
                    puls      cc
                    lda       #2        two moves of 512
                    pshs      a
h@                  ldx       2,s
                    ldy       #512
                    ldu       #VG.Addr+VG.XBuf
                    lbsr      FromCallerX
                    bcs       err@
                    ldx       2,s
                    leax      512,x
                    stx       2,s
                    ldy       #VG.Addr
                    ldd       #512
                    ldx       #VG.Addr+VG.XBuf
                    lbsr      VcPutN
                    bcs       err@
                    dec       ,s
                    bne       h@
                    leas      1,s
                    ldd       7,s
                    addd      #1
                    std       7,s
                    dec       ,s
                    bne       row@
                    clrb
                    bra       end@
err@                leas      1,s
end@                leas      1,s
                    puls      x,y,u
                    leas      2,s
                    pshs      cc,b
                    lbsr      XFree
                    puls      cc,b,pc
bad1@               leas      2,s
bad@                comb
                    ldb       #E$IllArg
x@                  rts

********************************************************************
* SS.MapWr - X = a rectangle (MW.*), Y = its length: its codes into the map
* at MAPBASE, each row reloading WPTR where the ring's 128 columns wrap
XMapWr              lbsr      XOwner
                    lbcs      x@
                    ldx       PD.RGS,y
                    ldd       R$Y,x
                    cmpd      #RT.Max
                    lbhi      bad@
                    pshs      y,u
                    tfr       d,y
                    ldx       R$X,x
                    ldu       #VG.Addr+VG.XBuf
                    lbsr      FromCallerX
                    puls      y,u
                    lbcs      x@
                    ldx       #VG.Addr+VG.XBuf
                    lda       MW.W,x    the length must be W x H + 4
                    ldb       MW.H,x
                    mul
                    addd      #MW.Codes
                    ldx       PD.RGS,y
                    cmpd      R$Y,x
                    lbne      bad@
                    lbsr      XBusy
                    pshs      y,u
                    ldy       #VG.Addr
                    leau      VG.XBuf+MW.Codes,y
                    lda       VG.XBuf+MW.Row,y
                    sta       VG.XRow,y
                    lda       VG.XBuf+MW.H,y
                    sta       VG.XRows,y
                    beq       ok@
row@                lda       VG.XBuf+MW.Col,y
                    sta       VG.XCol,y
                    lda       VG.XBuf+MW.W,y
                    sta       VG.XLeft,y
                    beq       nr@
seg@                bsr       MapAt
                    lda       VG.XCol,y the cells before the ring's column wraps
                    anda      #127
                    nega
                    adda      #128      (128 is $80, unsigned)
                    cmpa      VG.XLeft,y
                    bls       n@
                    lda       VG.XLeft,y
n@                  sta       VG.XN,y
                    tfr       a,b
                    clra
                    tfr       u,x
                    lbsr      VcPutN
                    bcs       e@
                    ldb       VG.XN,y
                    clra
                    leau      d,u
                    lda       VG.XCol,y
                    adda      VG.XN,y
                    sta       VG.XCol,y
                    lda       VG.XLeft,y
                    suba      VG.XN,y
                    sta       VG.XLeft,y
                    bne       seg@
nr@                 inc       VG.XRow,y
                    dec       VG.XRows,y
                    bne       row@
ok@                 clrb
e@                  puls      y,u
                    pshs      cc,b
                    lbsr      XFree
                    puls      cc,b,pc
bad@                comb
                    ldb       #E$IllArg
x@                  rts

* MapAt - Y = VG: WPTR := MAPBASE << 12 + (VG.XRow & 31) << 7 +
* (VG.XCol & 127), for direct writes
MapAt               pshs      d,x
                    ldb       VG.XRow,y row << 7
                    andb      #31
                    tfr       b,a
                    clrb
                    lsra
                    rorb
                    pshs      a
                    lda       VG.MBase,y MAPBASE's bits 15-12
                    anda      #15
                    lsla
                    lsla
                    lsla
                    lsla
                    ora       ,s+
                    pshs      a
                    lda       VG.XCol,y
                    anda      #127
                    pshs      a
                    orb       ,s+
                    puls      a
                    tfr       d,x
                    pshs      cc
                    orcc      #IRQMask
                    lbsr      VcWait
                    lda       #WM.Direct
                    lbsr      VcMode
                    clra
                    lbsr      VcAdv
                    ldb       VG.MBase,y MAPBASE's bits 18-16
                    lsrb
                    lsrb
                    lsrb
                    lsrb
                    lbsr      VcPtr
                    puls      cc
                    puls      d,x,pc
