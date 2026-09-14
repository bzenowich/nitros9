********************************************************************
* vidcore.asm - the arm6309 video card's rules, in one place
*
* arm6309 docs/nitros9-av-plan.md 2.1 lists them as V1-V12.  This file is
* `use`d by CoArm, and is the only code there that touches the card's
* registers: everything above it calls these routines.  They keep the
* rules so that callers need not:
*
*   V1  no register access but VSTAT while SPANBUSY: every register write
*       follows VcWait, and the VBL service polls b7 before its own
*   V2  no register write and no VRAM access while LRUN: VcWait waits for
*       b4 as well, and a stream re-checks between chunks
*   V3  WPTR is also the list pointer: VG.PtrGen counts the service's uses
*       of WPTR, and a stream that sees it move reloads its own position
*   V4  the register file reads back the last write, but not under a span
*       or a list: every register the system writes is shadowed in VG
*   V5  VBL is acknowledged by any write to VSTAT, under V1 - VcSvc
*   V6  palette commits snow: only VcSvc commits, 16 entries a blank
*   V7  each scroll pair is written whole, by VcSvc, inside VBLANK
*   V8  a VMODE family change is written just after VBLANK falls - VcVMode,
*       from the main line, so the VBL service never waits for it
*   V11 the tick follows VMODE0: VcSvc returns it in carry for the clock
*   V12 SPANBUSY holds E: VcWait polls it rather than stall on VRAM
*
* THE MASKING RULE (plan 3.4).  A main-line sequence masks /IRQ from its
* first register write to its trigger write, so the VBL service never
* lands inside one.  A VDATA stream is cut into chunks of VcChunk writes
* with /IRQ open between them, so the longest masked stretch is a chunk
* and not a primitive.  arm6309's software/nitros9/run-vid.sh measures it.
*
* A stream's writes are not polled against SPANBUSY: at 10 cycles a write
* they are spaced 4.8 us apart, and the spans they start (direct, mask,
* sprite) retire in at most 2.5 us in cell mode.  Span-solid, up to 81 us,
* is not streamed.
*
* Conventions: Y = VG throughout; X and U are preserved unless a routine
* says otherwise.  (masked) = call with IRQ masked, after VcWait.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P1: the service, the shadows, streams, the batch.

* Polls of VSTAT before VcWait gives up.  SPANBUSY lasts at most 40.7 us
* (a 256-pixel span, V12) - some 17 polls - and twice that in cell mode;
* LRUN is bounded by the list's END, which must come before VSYNC.  At
* ~2.4 us a poll, 16,384 of them is 39 ms: a card that holds either bit so
* long is broken, and the caller is told rather than hung.
VcPolls             equ       16384
* VDATA writes per masked stretch
VcChunk             equ       24

* VcWait - SPANBUSY and LRUN both clear.  A = VSTAT; carry set if they
* never cleared.  A span is waited out as it is, masked or not (40.7 us at
* most); a display list runs most of a frame, so while LRUN is set the wait
* opens /IRQ, and masks it again as the caller had it before looking again.
VcWait              pshs      cc,x,u
                    ldu       VG.Base,y
                    ldx       #VcPolls
w@                  lda       VR.VSTAT,u
                    bita      #VSTAT.Busy+VSTAT.LRun
                    beq       ok@
                    bita      #VSTAT.LRun
                    bne       l@
                    leax      -1,x
                    bne       w@
e@                  leas      1,s
                    comb
                    puls      x,u,pc
l@                  andcc     #^IRQMask
p@                  leax      -1,x
                    beq       r@
                    lda       VR.VSTAT,u
                    bita      #VSTAT.LRun
                    bne       p@
                    lda       ,s        the caller's mask back, then look again
                    bita      #IRQMask
                    beq       w@
                    orcc      #IRQMask
                    bra       w@
r@                  lda       ,s
                    bita      #IRQMask
                    beq       e@
                    orcc      #IRQMask
                    bra       e@
ok@                 leas      1,s
                    andcc     #^Carry
                    puls      x,u,pc

* VcMode (masked) - A = the WMODE bits (WM.*): CTRL takes them if it does
* not hold them already.  The rest of CTRL belongs to the batch.
VcMode              pshs      d,u
                    ldb       VG.Ctrl,y
                    andb      #CT.WMode
                    cmpb      ,s
                    beq       x@
                    ldb       VG.Ctrl,y
                    andb      #^CT.WMode
                    orb       ,s
                    stb       VG.Ctrl,y
                    ldu       VG.Base,y
                    stb       VR.CTRL,u
x@                  puls      d,u,pc

* VcFG, VcBG, VcAdv, VcSpl (masked) - A = WFG, WBG, WADV or SPANLEN,
* written only if it changed
VcFG                cmpa      VG.WFG,y
                    beq       x@
                    sta       VG.WFG,y
                    pshs      u
                    ldu       VG.Base,y
                    sta       VR.WFG,u
                    puls      u
x@                  rts

VcBG                cmpa      VG.WBG,y
                    beq       x@
                    sta       VG.WBG,y
                    pshs      u
                    ldu       VG.Base,y
                    sta       VR.WBG,u
                    puls      u
x@                  rts

VcAdv               cmpa      VG.WAdv,y
                    beq       x@
                    sta       VG.WAdv,y
                    pshs      u
                    ldu       VG.Base,y
                    sta       VR.WADV,u
                    puls      u
x@                  rts

VcSpl               cmpa      VG.SpLen,y
                    beq       x@
                    sta       VG.SpLen,y
                    pshs      u
                    ldu       VG.Base,y
                    sta       VR.SPANLEN,u
                    puls      u
x@                  rts

* VcPtr (masked) - WPTR := B:X (B = bits 18-16).  Recorded in VG.Ptr, with
* the service's generation, so a stream can find its way back (V3).
VcPtr               stb       VG.Ptr,y
                    stx       VG.Ptr+1,y
                    pshs      a
                    clr       VG.PtrN,y
                    clr       VG.PtrN+1,y
                    lda       VG.PtrGen,y
                    sta       VG.PtrSeen,y
                    puls      a
* VcLoad (masked) - the WPTR registers := B:X, nothing recorded
VcLoad              pshs      d,u
                    ldu       VG.Base,y
                    tfr       x,d
                    stb       VR.WPTR0,u little-endian (V3)
                    sta       VR.WPTR1,u
                    lda       1,s
                    sta       VR.WPTR2,u
                    puls      d,u,pc

* VcRePtr (masked) - WPTR := where VG.Ptr has got to after VG.PtrN
* writes.  Any nonzero WADV advances a row per span and reloads the
* column (graphics.md 7.4); WADV 00 advances the column by 1 a write
* (direct) or 8 (mask, sprite), wrapping within the row (V10).
VcRePtr             pshs      d,x
                    lda       VG.WAdv,y
                    bne       row@
                    ldd       VG.PtrN,y
                    pshs      d
                    lda       VG.SFill,y a read steps WPTR by one, whatever the WMODE
                    cmpa      #2
                    beq       one@
                    lda       VG.Ctrl,y
                    anda      #CT.WMode
                    beq       one@
                    ldd       ,s        eight a write
                    lslb
                    rola
                    lslb
                    rola
                    lslb
                    rola
                    std       ,s
one@                ldd       VG.Ptr+1,y
                    addd      ,s
                    anda      #3        the column's two high bits
                    std       ,s
                    lda       VG.Ptr+1,y the row's bits stay
                    anda      #$FC
                    ora       ,s
                    ldb       1,s
                    leas      2,s
                    tfr       d,x
                    ldb       VG.Ptr,y
                    bra       ld@
row@                ldd       VG.PtrN,y rows += n: n << 10 in the upper two bytes
                    lslb
                    rola
                    lslb
                    rola
                    addb      VG.Ptr+1,y
                    adca      VG.Ptr,y
                    anda      #7
                    pshs      a
                    tfr       b,a
                    ldb       VG.Ptr+2,y the column's low byte stays
                    tfr       d,x
                    puls      b
ld@                 bsr       VcLoad
                    lda       VG.PtrGen,y
                    sta       VG.PtrSeen,y
                    puls      d,x,pc

* VcPutN - D bytes from X to VDATA (D = 0: none), from the WPTR VcPtr
* loaded, in the WMODE and WADV already set.  X is left past them.
* VcGetN - D bytes from VDATA to X (graphics.md 11: the byte at WPTR, and
* WPTR steps), X left past them.  A read waits on a span or its prefetch by
* /WAIT, which is the backstop and not the rule: a caller that has just
* started a span-solid polls first (V12).
* VcFillN - X copies of A (X = 0: none); X is preserved.
* Both mask /IRQ themselves a chunk at a time and give the caller back its
* CC.  Carry set (B = E$NotRdy) if the card never came ready.
VcFillN             sta       VG.SByte,y
                    stx       VG.SCnt,y
                    beq       VcNone
                    lda       #1
                    sta       VG.SFill,y
                    pshs      x
                    bsr       Strm
                    puls      x,pc      (PULS leaves the carry alone)

VcPutN              std       VG.SCnt,y
                    beq       VcNone
                    clr       VG.SFill,y
                    bsr       Strm
                    rts

VcGetN              std       VG.SCnt,y
                    beq       VcNone
                    lda       #2
                    sta       VG.SFill,y
                    bsr       Strm
                    rts

VcNone              andcc     #^Carry
                    rts

Strm                pshs      cc,u
                    ldu       VG.Base,y
ch@                 orcc      #IRQMask
                    lda       VG.PtrGen,y
                    cmpa      VG.PtrSeen,y
                    beq       go@
                    lbsr      VcWait    the service used WPTR: its list must END first (V2),
                    bcs       err@
                    lbsr      VcRePtr   then back to where this stream was (V3)
go@                 ldd       VG.SCnt,y
                    cmpd      #VcChunk
                    bls       c1@
                    ldb       #VcChunk
c1@                 pshs      b
                    lda       VG.SFill,y
                    beq       p@
                    cmpa      #2
                    bne       f@
g@                  lda       VR.VDATA,u
                    sta       ,x+
                    decb
                    bne       g@
                    bra       cd@
p@                  lda       ,x+
                    sta       VR.VDATA,u
                    decb
                    bne       p@
                    bra       cd@
f@                  lda       VG.SByte,y
fl@                 sta       VR.VDATA,u
                    decb
                    bne       fl@
cd@                 clra
                    ldb       ,s
                    addd      VG.PtrN,y
                    std       VG.PtrN,y
                    clra
                    puls      b
                    pshs      d
                    ldd       VG.SCnt,y
                    subd      ,s++
                    std       VG.SCnt,y
                    beq       end@
                    lda       ,s        the caller's CC
                    bita      #IRQMask
                    bne       ch@
                    andcc     #^IRQMask a pending VBL is taken here
                    bra       ch@
end@                puls      cc,u
                    andcc     #^Carry
                    rts
err@                puls      cc,u
                    comb
                    ldb       #E$NotRdy
                    rts

********************************************************************
* The frame batch.  The main line queues; VcSvc commits in the next blank.
* Each Q routine masks /IRQ around its own update.

* VcQCtrl - A = CTRL without WMODE, from the next VBL
VcQCtrl             pshs      cc,a
                    orcc      #IRQMask
                    anda      #^CT.WMode
                    sta       VG.BCtrl,y
                    lda       #BF.Ctrl
                    bra       VcQFlag
* VcQVScr, VcQHScr - D = the scroll
VcQVScr             pshs      cc,a
                    orcc      #IRQMask
                    std       VG.BVScr,y
                    lda       #BF.VScr
                    bra       VcQFlag

VcQHScr             pshs      cc,a
                    orcc      #IRQMask
                    std       VG.BHScr,y
                    lda       #BF.HScr
                    bra       VcQFlag
* VcQBank - A = TILEBASE, B = MAPBASE
VcQBank             pshs      cc,a
                    orcc      #IRQMask
                    std       VG.BTBase,y
                    lda       #BF.TBase+BF.MBase

VcQFlag             ora       VG.BFlag,y
                    sta       VG.BFlag,y
                    puls      cc,a,pc

* VcQPal - VG.Pal entries B .. B+A-1 (A = 0: 256) are to be committed,
* merged with any range still pending.
VcQPal              pshs      cc,d,x
                    orcc      #IRQMask
                    clra
                    ldb       2,s       first
                    tfr       d,x
                    ldb       1,s       count
                    bne       c@
                    inca                0 is 256
c@                  pshs      x
                    addd      ,s++      D = end = first + count
                    pshs      d
                    lda       VG.BFlag,y
                    bita      #BF.Pal
                    beq       new@
                    clra                merge with what is pending
                    ldb       VG.PalLo,y
                    pshs      d         the pending start
                    addd      VG.PalN,y the pending end
                    cmpd      2,s
                    bls       e@
                    std       2,s       end = the later
e@                  tfr       x,d
                    cmpd      ,s
                    bls       s@
                    ldx       ,s        start = the earlier
s@                  leas      2,s
new@                tfr       x,d
                    stb       VG.PalLo,y
                    pshs      d
                    ldd       2,s
                    subd      ,s++
                    std       VG.PalN,y
                    leas      2,s
                    lda       VG.BFlag,y
                    ora       #BF.Pal
                    sta       VG.BFlag,y
                    puls      cc,d,x,pc

* VcVMode is CoArm's: it yields (CoFrame), which only CoArm can do
                    ifdef     CoG
* VcVMode - A = the VMODE bits CTRL is to hold.  In the same family nothing
* is written: the caller queues CTRL.  A family change is written here, from
* the main line, just after VBLANK falls (V8: vctrl.v's terminal-count decode
* is partial): CoArm yields until a VBL has been served, which leaves it in
* the blank, polls VBLANK with /IRQ open, and masks only for the write.  Not
* in the blank when it wakes (a late wake), it waits for the next one: three
* tries.
VcVMode             pshs      d,x,u
                    anda      #CT.VMode
                    sta       ,s
                    eora      VG.Ctrl,y
                    bita      #1
                    beq       x@
                    ldu       VG.Base,y
                    lda       #3
                    sta       1,s
t@                  lbsr      CoFrame
                    lda       VR.VSTAT,u
                    bita      #VSTAT.VBlk
                    bne       in@
                    dec       1,s
                    bne       t@
in@                 ldx       #VcPolls
f@                  lda       VR.VSTAT,u
                    bita      #VSTAT.VBlk
                    beq       w@
                    leax      -1,x
                    bne       f@
w@                  pshs      cc
                    orcc      #IRQMask
                    lbsr      VcWait
                    lda       VG.Ctrl,y
                    anda      #^CT.VMode
                    ora       1,s
                    sta       VG.Ctrl,y
                    sta       VR.CTRL,u
                    puls      cc
x@                  puls      d,x,u,pc
                    endc
