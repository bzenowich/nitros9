********************************************************************
* vidsvc.asm - the arm6309 video card's VBL service, and the waits on it
*
* `use`d by ArmIO, in the system map: the service runs in the IRQ, and the
* waits sleep, and CoArm - in a task of its own - can do neither.  The rules
* it keeps are vidcore.asm's V1, V2, V5, V7 and V11.

*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P1.

* VcFrame - sleep until at least one VBL has been served since the call.
* System state, /IRQ open.  Carry set after ~4 s without one.
VcFrame             pshs      d,x
                    ldd       VG.Frames,y
                    pshs      d
                    lda       #255
                    pshs      a
f@                  ldx       #1
                    os9       F$Sleep
                    ldd       VG.Frames,y
                    cmpd      1,s
                    bne       ok@
                    dec       ,s
                    bne       f@
                    leas      3,s
                    comb
                    puls      d,x,pc
ok@                 leas      3,s
                    andcc     #^Carry
                    puls      d,x,pc

* VcBatchWait - sleep until the batch is empty: everything queued is on
* the card.  Carry set after ~4 s.
VcBatchWait         pshs      d,x
                    lda       #255
                    pshs      a
w@                  tst       VG.BFlag,y
                    beq       ok@
                    ldx       #1
                    os9       F$Sleep
                    dec       ,s
                    bne       w@
                    leas      1,s
                    comb
                    puls      d,x,pc
ok@                 leas      1,s
                    andcc     #^Carry
                    puls      d,x,pc

********************************************************************
* VcSvc - the VBL service (plan 3.4).  The clock calls it through VG.Svc
* in the IRQ, with X = VG, the system map and DP = 0; D, X, Y and U are
* free.  It returns carry = VMODE0 of CTRL, for the tick's length.
*
* A batch is at most both scroll pairs, CTRL and the two bases.  The
* palette is not in it: the card posts a CPU's commit to the next HLOAD
* (graphics.md 13.1), so VidCore writes it from the main line (VcPal).
* A CTRL with a different VMODE0 is written like any other: the card takes
* the family where the frame ends (vctrl's M0, graphics.md 6.2), and this
* write is in the blank, before that end - so the frame this VBL closes was
* the old family's, and the carry is VMODE0 as the service found it.
VcSvc               tfr       x,y
                    lda       VG.Ctrl,y the family of the frame this VBL ends, for the tick
                    sta       VG.TkFam,y
                    ldu       VG.Base,y
                    ldx       #VcPolls
s@                  lda       VR.VSTAT,u V1: out of any span
                    bpl       l@
                    leax      -1,x
                    bne       s@
l@                  bita      #VSTAT.LRun V2: a list still running at VSYNC broke the
                    beq       a@        rule; acknowledging costs it a byte, and is right
                    ldd       VG.LRunV,y
                    addd      #1
                    std       VG.LRunV,y
a@                  sta       VR.VSTAT,u V5: any write acknowledges
                    lbsr      VcBatch   SS.Batch first: an exclusive owner's flip needs the blank
                    ldu       VG.Base,y
                    ldd       VG.Frames,y
                    addd      #1
                    std       VG.Frames,y
                    lda       VG.BFlag,y
                    lbeq      done@
                    bita      #BF.VScr  V7: each pair whole, inside VBLANK
                    beq       h@
                    ldd       VG.BVScr,y
                    std       VG.VScr,y
                    stb       VR.VSCR,u
                    sta       VR.VSCRH,u
h@                  lda       VG.BFlag,y
                    bita      #BF.HScr
                    beq       t@
                    ldd       VG.BHScr,y
                    std       VG.HScr,y
                    stb       VR.HSCR,u
                    sta       VR.HSCRH,u
t@                  lda       VG.BFlag,y
                    bita      #BF.TBase
                    beq       m@
                    lda       VG.BTBase,y
                    sta       VG.TBase,y
                    sta       VR.TBASE,u
m@                  lda       VG.BFlag,y
                    bita      #BF.MBase
                    beq       c@
                    lda       VG.BMBase,y
                    sta       VG.MBase,y
                    sta       VR.MBASE,u
c@                  lda       VG.BFlag,y
                    bita      #BF.Ctrl
                    beq       p@
                    lda       VG.Ctrl,y the main line's WMODE stays
                    anda      #CT.WMode
                    ora       VG.BCtrl,y
                    sta       VG.Ctrl,y
                    sta       VR.CTRL,u
p@                  lda       VG.BFlag,y
                    anda      #^(BF.VScr+BF.HScr+BF.TBase+BF.MBase+BF.Ctrl)
                    sta       VG.BFlag,y
done@               lbsr      VcFSig
                    lbsr      VcGo
                    lda       VG.TkFam,y
                    lsra                C = VMODE0 of that frame
                    rts

* VcBatch - SS.Batch's records (armvid.d BT.*), in the blank, in order.  A
* put takes WPTR (V3) and needs direct mode and WADV 00: both are read back
* - the exclusive owner's libvid may have left anything - and put back.
* The timing marks at $FF2E, which decode nowhere, are demo.asm's: a
* recording's marks.txt says when the writes ran against the blank.
VcBatch             tst       VG.BtOn,y
                    lbeq      x@
                    ldu       VG.Base,y
                    leax      VG.BtBuf,y
                    clr       ,-s       no put yet
r@                  lda       ,x+
                    lbeq      d@
                    cmpa      #BT.Reg
                    bne       p@
                    ldb       ,x+
                    lda       ,x+
                    pshs      x
                    leax      b,u
                    sta       ,x        the register ...
                    leax      VG.VScr+1,y ... and its shadow
                    cmpb      #VR.VSCR
                    beq       sh@
                    leax      -1,x
                    cmpb      #VR.VSCRH
                    beq       sh@
                    leax      VG.HScr+1,y
                    cmpb      #VR.HSCR
                    beq       sh@
                    leax      -1,x
                    cmpb      #VR.HSCRH
                    beq       sh@
                    leax      VG.TBase,y
                    cmpb      #VR.TBASE
                    beq       sh@
                    leax      VG.MBase,y
sh@                 sta       ,x
                    puls      x
                    bra       r@
p@                  cmpa      #BT.Put
                    beq       pp@
                    cmpa      #BT.Poke
                    bne       t@
pp@                 tfr       a,b       (the record's type, while A sets up)
                    tst       ,s
                    bne       p1@
                    lda       #1        the first put: the mark, and the modes
                    sta       >$FF2E
                    sta       ,s
                    lda       VR.CTRL,u
                    pshs      a
                    anda      #^CT.WMode
                    sta       VR.CTRL,u
                    puls      a
                    sta       VG.BtCtl,y
                    lda       VR.WADV,u
                    sta       VG.BtAdv,y
                    clr       VR.WADV,u
                    inc       VG.PtrGen,y
p1@                 cmpb      #BT.Poke
                    bne       pu@
                    ldb       ,x+       a poke: WPTR2 once, then the low two a byte
                    lda       ,x+
                    sta       VR.WPTR2,u
k@                  lda       1,x
                    sta       VR.WPTR0,u
                    lda       ,x
                    sta       VR.WPTR1,u
                    lda       2,x
                    sta       VR.VDATA,u
                    leax      3,x
                    decb
                    bne       k@
                    lbra      r@
pu@                 lda       2,x       WPTR, little-endian
                    sta       VR.WPTR0,u
                    lda       1,x
                    sta       VR.WPTR1,u
                    lda       ,x
                    sta       VR.WPTR2,u
                    leax      3,x
                    ldb       ,x+
                    lbeq      r@
c@                  lda       ,x+
                    sta       VR.VDATA,u
                    decb
                    bne       c@
                    lbra      r@
t@                  cmpa      #BT.Tags
                    bne       d@
                    ldd       ,x++
                    std       VG.MkCam,y
                    ldd       ,x++
                    std       VG.MkHero,y
                    lbra      r@
d@                  tst       ,s+
                    beq       o@
                    lda       VG.BtAdv,y
                    sta       VR.WADV,u
                    lda       VG.BtCtl,y
                    sta       VR.CTRL,u
                    lda       #2
                    sta       >$FF2E
o@                  clr       VG.BtOn,y
x@                  rts

* VcFSig - SS.FrmSig: the signal, every VG.FSN frames
VcFSig              lda       VG.FSPID,y
                    beq       x@
                    dec       VG.FSC,y
                    bne       x@
                    ldb       VG.FSN,y
                    stb       VG.FSC,y
                    ldb       VG.FSSig,y
                    os9       F$Send
x@                  rts

* VcGo - the displayed screen's display list (SS.Raster), started from the
* blank: the card holds a GO written while VBLANK is high and starts the
* engine as the blank ends (graphics.md 10.3.1's armed GO), which is where
* WAIT n is line n.  The list takes WPTR (V3), so the generation moves, and
* VG.LArm tells the main line that WPTR is the list's until the blank ends
* (VcWait).  A service that finds the blank already over starts nothing this
* frame, and counts it.
VcGo                tst       VG.LOn,y
                    beq       n@
                    lda       VG.LScr,y
                    cmpa      VG.DScr,y
                    bne       n@
                    ldu       VG.Base,y
                    lda       VR.VSTAT,u
                    bita      #VSTAT.VBlk
                    bne       go@
                    ldd       VG.LLate,y
                    addd      #1
                    std       VG.LLate,y
n@                  clr       VG.MkPh,y
                    clr       VG.MkPh+1,y
                    rts
go@                 ldd       VG.LRow,y WPTR := row << 10, little-endian
                    lslb
                    rola
                    lslb
                    rola
                    clr       VR.WPTR0,u
                    stb       VR.WPTR1,u
                    sta       VR.WPTR2,u
                    lda       #1
                    sta       VR.BCTRL,u GO, armed to the blank's end
                    sta       VG.LArm,y
                    inc       VG.PtrGen,y
                    ldd       VG.LTag,y
                    std       VG.MkPh,y
                    rts
