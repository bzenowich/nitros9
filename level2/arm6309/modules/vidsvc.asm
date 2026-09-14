********************************************************************
* vidsvc.asm - the arm6309 video card's VBL service, and the waits on it
*
* `use`d by ArmIO, in the system map: the service runs in the IRQ, and the
* waits sleep, and CoArm - in a task of its own - can do neither.  The rules
* it keeps are vidcore.asm's V1, V2, V5-V7 and V11.

* Palette entries a blank commits: 16 is ~0.2 ms, and a whole palette in
* sixteen blanks (0.23 s)
VcPalPer            equ       16
* Polls of VBLANK before a list's GO: the IRQ comes 12 lines into a 49-line
* blank, so ~37 lines, ~140 polls, are left; this is the bound
VcLPolls            equ       400
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
* A batch is at most both scroll pairs, CTRL, the two bases and VcPalPer
* palette entries: ~40 writes, plan 3.4's 0.5 ms with room.  Only the
* palette carries to a later blank, and VG.PalCar counts the blanks it did.
* ⚠ It never waits for VBLANK to fall (V8): that took 1.2 ms of the IRQ
* on each family change, found by run-vid.sh's CALLTIME, and VcVMode does
* it from the main line instead.  A CTRL queued with a different VMODE0 is
* written at once.
VcSvc               tfr       x,y
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
                    bita      #BF.Pal   V6: VcPalPer entries this blank
                    beq       done@
                    ldb       VG.PalLo,y
                    stb       VR.PIDX,u
                    clra
                    lslb
                    rola
                    leax      d,y
                    leax      VG.Pal,x
                    ldd       VG.PalN,y
                    cmpd      #VcPalPer
                    bls       n@
                    ldd       #VcPalPer
n@                  pshs      d
                    ldd       VG.PalN,y
                    subd      ,s
                    std       VG.PalN,y
                    lda       VG.PalLo,y
                    adda      1,s
                    sta       VG.PalLo,y
pl@                 ldd       ,x++
                    stb       VR.PDATL,u
                    sta       VR.PDATH,u commits; PIDX steps
                    dec       1,s
                    bne       pl@
                    leas      2,s
                    ldd       VG.PalN,y
                    bne       car@
                    lda       VG.BFlag,y
                    anda      #^BF.Pal
                    sta       VG.BFlag,y
                    bra       done@
car@                ldd       VG.PalCar,y
                    addd      #1
                    std       VG.PalCar,y
done@               lbsr      VcFSig
                    lbsr      VcGo
                    lda       VG.Ctrl,y
                    lsra                C = VMODE0
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

* VcGo - the displayed screen's display list (SS.Raster), started as the
* blank ends (plan 3.4.1 (a)): graphics.md 10.3.2's WAIT n is line n only
* for a GO inside line 0.  So the service polls VBLANK with /IRQ masked,
* ~1.2 ms a frame while a list is on.  A service that finds the blank
* already over starts nothing this frame, and counts it.  The list takes
* WPTR (V3), so the generation moves.
VcGo                tst       VG.LOn,y
                    beq       n@
                    lda       VG.LScr,y
                    cmpa      VG.DScr,y
                    bne       n@
                    ldu       VG.Base,y
                    lda       VR.VSTAT,u
                    bita      #VSTAT.VBlk
                    beq       late@
                    ldx       #VcLPolls
w@                  lda       VR.VSTAT,u
                    bita      #VSTAT.VBlk
                    beq       go@
                    leax      -1,x
                    bne       w@
late@               ldd       VG.LLate,y
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
                    sta       VR.BCTRL,u GO
                    inc       VG.PtrGen,y
                    ldd       VG.LTag,y
                    std       VG.MkPh,y
                    rts
