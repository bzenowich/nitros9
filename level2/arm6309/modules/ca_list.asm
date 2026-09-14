********************************************************************
* ca_list.asm - display lists: SS.Raster and SS.RastOff
*
* A list is the card's (graphics.md 10.3.2): MOVE $0r v writes register r,
* WAIT $80 holds to the next scanline, END $FF.  CoArm composes one from
* the caller's table (armvid.d RT.*, moved into VG.XBuf by ArmIO) into a
* ring row below the displayed screen, and the VBL service starts it at
* the end of every blank (vidsvc.asm VcGo) while that screen is displayed.
*
* Two rows take turns: the new list is written into the row the service is
* not starting, and the service is pointed at it in one masked store, so a
* frame never starts a list half written.  The rows are 16 and 17 rows
* below the screen's last, in the ring: clear of a bitmap screen's rows and
* of the row a full-screen scroll clears next.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P3.

********************************************************************
* SS.Raster: the displayed bitmap screen's list, from the next frame
DoRaster            lbsr      IsDisp
                    beq       d@
                    comb
                    ldb       #E$NotRdy
                    rts
d@                  lbsr      IsBmp
                    beq       b@
                    comb
                    ldb       #E$IWTyp
                    rts
b@                  leau      VG.XBuf,y
                    lda       RT.Kind,u
                    cmpa      #1
                    lbhi      bad@
                    ldd       RT.N,u
                    cmpd      #RT.MaxN
                    lbhi      bad@
* its length: y0 + N (MOVEs + lines) + the put-back + END, at most a row
                    ldb       #4        HSCROLL: two MOVEs
                    tst       RT.Kind,u
                    beq       k@
                    ldb       #6        a palette entry: three
k@                  pshs      b
                    addb      RT.Lines,u
                    clra
                    pshs      d         an entry's bytes
                    ldd       RT.Y0,u
                    addb      2,s       the put-back
                    adca      #0
                    addd      #1        END
                    ldx       RT.N,u
                    beq       s@
a@                  addd      ,s
                    cmpd      #1024
                    lbhi      big@
                    leax      -1,x
                    bne       a@
s@                  leas      3,s
                    cmpd      #1024
                    lbhi      bad@
* composed in CG.LBuf: y0 WAITs, the entries, the put-back, END
                    ldx       #CoG+CG.LBuf
                    ldd       RT.Y0,u
                    beq       e0@
                    leax      d,x
                    pshs      x
                    ldx       #CoG+CG.LBuf
                    lda       #$80
y@                  sta       ,x+
                    cmpx      ,s
                    blo       y@
                    leas      2,s
e0@                 ldd       RT.N,u
                    beq       t@
                    std       >CoG+CG.Cnt
                    leau      RT.Tab,u
e@                  ldd       ,u++
                    lbsr      LEntry
                    ldd       >CoG+CG.Cnt
                    subd      #1
                    std       >CoG+CG.Cnt
                    bne       e@
t@                  leau      VG.XBuf,y the put-back: the register as the screen has it
                    tst       RT.Kind,u
                    bne       tp@
                    ldd       VG.HScr,y
                    bra       tb@
tp@                 pshs      x
                    ldb       RT.Idx,u
                    clra
                    lslb
                    rola
                    ldx       >CoG+CG.CurS
                    leax      d,x
                    ldd       SC.Pal,x
                    puls      x
tb@                 clr       RT.Lines,u no WAITs after it
                    lbsr      LEntry
                    lda       #$FF      END
                    sta       ,x+
                    tfr       x,d
                    subd      #CoG+CG.LBuf
                    std       >CoG+CG.Cnt
* into the row the service is not starting: 16 or 17 ring rows below the screen
                    ldx       >CoG+CG.CurS
                    ldd       SC.Top,x
                    addd      SC.H,x
                    addd      #16
                    addb      VG.LAlt,y
                    adca      #0
                    anda      #1
                    std       >CoG+CG.RY
                    pshs      cc
                    orcc      #IRQMask
                    lbsr      VcWait
                    lda       #WM.Direct
                    lbsr      VcMode
                    clra
                    lbsr      VcAdv
                    ldd       >CoG+CG.RY WPTR := row << 10
                    lslb
                    rola
                    lslb
                    rola
                    pshs      a
                    tfr       b,a
                    clrb
                    tfr       d,x
                    puls      b
                    lbsr      VcPtr
                    puls      cc
                    ldd       >CoG+CG.Cnt
                    ldx       #CoG+CG.LBuf
                    lbsr      VcPutN
                    bcs       err@
                    ldx       >CoG+CG.CurS
                    lbsr      SIdx
                    incb
                    orcc      #IRQMask  the service starts the new row from the next blank
                    stb       VG.LScr,y
                    ldd       >CoG+CG.RY
                    std       VG.LRow,y
                    ldd       RT.Tag,u
                    addd      #1
                    std       VG.LTag,y
                    lda       #1
                    sta       VG.LOn,y
                    eora      VG.LAlt,y
                    sta       VG.LAlt,y
                    andcc     #^IRQMask
                    clrb
                    rts
big@                leas      3,s
bad@                comb
                    ldb       #E$IllArg
err@                rts

* LEntry - D = an entry's value, X = where it goes in CG.LBuf, VG.XBuf's
* kind, index and lines: its MOVEs and WAITs, X past them
LEntry              pshs      d,u
                    leau      VG.XBuf,y
                    tst       RT.Kind,u
                    bne       p@
                    lda       #VR.HSCR  HSCROLL: bits 7-0, then 9-8
                    sta       ,x+
                    lda       1,s
                    sta       ,x+
                    lda       #VR.HSCRH
                    sta       ,x+
                    lda       ,s
                    anda      #3
                    sta       ,x+
                    bra       w@
p@                  lda       #VR.PIDX  PIDX, PDATL, then PDATH, which commits
                    sta       ,x+
                    lda       RT.Idx,u
                    sta       ,x+
                    lda       #VR.PDATL
                    sta       ,x+
                    lda       1,s
                    sta       ,x+
                    lda       #VR.PDATH
                    sta       ,x+
                    lda       ,s
                    sta       ,x+
w@                  ldb       RT.Lines,u
                    beq       x@
                    lda       #$80
l@                  sta       ,x+
                    decb
                    bne       l@
x@                  puls      d,u,pc

********************************************************************
* SS.RastOff: no list.  The last one ran to its end, and put back what it
* moved.
DoRastOff           orcc      #IRQMask
                    clr       VG.LOn,y
                    clr       VG.MkPh,y
                    clr       VG.MkPh+1,y
                    andcc     #^IRQMask
                    clrb
                    rts
