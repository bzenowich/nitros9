********************************************************************
* ArmIO - the arm6309 video console's SCF driver
*
* One driver for every window device (/W1 ...).  It keeps the input buffer
* the keyboard fills, answers the calls that are about input, runs the VBL
* service, and carries everything else into CoArm.  arm6309
* docs/nitros9-av-plan.md 3.1 is the split: CoCo 3 VTIO's.  The name is not
* VT* on purpose - SCF sends bulk text past any driver named "VT..." to a
* GrfDrv (level1/modules/scf.asm), and there is no GrfDrv here.
*
* COARM RUNS IN A TASK OF ITS OWN (defs/armvid.d says why).  The first Init:
*   1. puts the video globals (VG) at VG.Addr in block 0 and reads the
*      card's registers into their shadows;
*   2. links KbdArm and initialises the keyboard;
*   3. finds CoArm with F$NMLink, or loads it from the execution directory
*      with F$NMLoad - neither maps it into the system - and builds software
*      task 1's DAT image: block 0, CoArm's blocks, four data blocks from
*      F$AllRAM, and the kernel's block, which the kernel forces;
*   4. calls CoArm's CF.Boot, then puts VG in D.VBLSt: from that moment the
*      clock hands every VBL to the service here (vidsvc.asm).
* The last Term undoes all of it.
*
* A CALL INTO COARM (CoCall) is CoCo 3 CoWin's entry to GrfDrv: the system
* stack is saved in VG, a full RTI frame for CoArm's entry is pushed on the
* stack under D.CCStk, and D.Flip1 loads task 1 and RTIs into it.  CoArm
* comes back through D.Flip0, which returns here with the system stack.
* When CoArm has to wait for the frame batch to reach the card it yields
* (VG.CWait); CoCall sleeps until the batch is empty and resumes it, and
* VG.CBusy keeps any other window's call out until it has finished.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P1.

                    nam       ArmIO
                    ttl       arm6309 video console driver

                    ifp1
                    use       defsfile
                    use       armvid.d
                    endc

tylg                set       Drivr+Objct
atrv                set       ReEnt+rev
rev                 set       0
edition             set       1

                    mod       eom,name,tylg,atrv,start,V.ArmSiz

                    fcb       READ.+WRITE.

name                fcs       /ArmIO/
                    fcb       edition

start               lbra      Init
                    lbra      Read
                    lbra      Write
                    lbra      GetStat
                    lbra      SetStat
                    lbra      Term

CoName              fcs       /CoArm/

KbName              fcs       /KbdArm/

CoPath              fcs       "/DD/CMDS/CoArm"

********************************************************************
* Init - Y = the descriptor, U = the statics
Init                lda       IT.WND,y
                    beq       bad@
                    cmpa      #WinMax
                    blo       ok@
bad@                comb
                    ldb       #E$BPAddr
                    rts
ok@                 sta       V.WinNum,u
                    clra
                    clrb
                    std       V.SSigID,u
                    std       V.InPtr,u
                    ldx       <D.VBLSt
                    bne       have@
                    lbsr      ConUp     the first window: the console comes up
                    bcc       have@
                    rts
have@               ldx       #VG.Addr
                    inc       VG.Users,x
                    ldb       V.WinNum,u
                    lslb
                    abx
                    stu       VG.WinDev,x
                    ldx       #VG.Addr
                    lda       V.WinNum,u
                    sta       VG.CWin,x
                    lda       IT.VAL,y
                    sta       VG.CA,x
                    leax      VG.CParm,x the defaults, as DWSet's parameters
                    lda       IT.STY,y
                    sta       ,x+
                    lda       IT.CPX,y
                    sta       ,x+
                    lda       IT.CPY,y
                    sta       ,x+
                    lda       IT.COL,y
                    sta       ,x+
                    lda       IT.ROW,y
                    sta       ,x+
                    lda       IT.FGC,y
                    sta       ,x+
                    lda       IT.BGC,y
                    sta       ,x+
                    lda       IT.BDC,y
                    sta       ,x
                    ldb       #CF.Init
                    lbra      CoCall

* ConUp - Y = the first descriptor.  Carry set with B if the console
* cannot come up.
ConUp               pshs      y,u
                    ldx       #VG.Addr
                    ldd       #VG.Size
c@                  clr       ,x+
                    subd      #1
                    bne       c@
                    ldu       #VG.Addr
                    ldd       IT.VBase,y
                    std       VG.Base,u
                    ldd       IT.KBase,y
                    std       VG.KBase,u
                    leax      VcSvc,pcr
                    stx       VG.Svc,u
                    leax      PtrIdle,pcr
                    stx       VG.Idle,u
* the card's registers as the boot ROM left them (V4: the file reads back
* the last write), once no span is running (V1)
                    ldx       VG.Base,u
                    ldy       #VcPolls
b@                  lda       VR.VSTAT,x
                    bpl       r@
                    leay      -1,y
                    bne       b@
r@                  lda       VR.CTRL,x
                    sta       VG.Ctrl,u
                    lda       VR.VSCRH,x
                    anda      #1
                    ldb       VR.VSCR,x
                    std       VG.VScr,u
                    lda       VR.HSCRH,x
                    anda      #3
                    ldb       VR.HSCR,x
                    std       VG.HScr,u
                    lda       VR.WFG,x
                    sta       VG.WFG,u
                    lda       VR.WBG,x
                    sta       VG.WBG,u
                    lda       VR.WADV,x
                    anda      #3
                    sta       VG.WAdv,u
                    lda       VR.SPANLEN,x
                    sta       VG.SpLen,u
                    lda       VR.TBASE,x
                    sta       VG.TBase,u
                    lda       VR.MBASE,x
                    sta       VG.MBase,u
* the modules, as the system (VTIO's way)
                    ldd       <D.Proc
                    pshs      d
                    ldd       <D.SysPrc
                    std       <D.Proc
                    leax      KbName,pcr
                    lda       #Systm+Objct
                    pshs      u
                    os9       F$Link
                    tfr       u,x
                    puls      u
                    bcs       nokb@     a console with no keyboard still writes
                    stx       VG.KbMod,u
                    sty       VG.KbEnt,u
nokb@               leax      CoName,pcr
                    lda       #Systm+Objct
                    os9       F$NMLink
                    bcc       found@
                    leax      CoName,pcr
                    lda       #Systm+Objct
                    os9       F$NMLoad  from the execution directory, or ...
                    bcc       found@
                    leax      CoPath,pcr ... from /DD/CMDS
                    lda       #Systm+Objct
                    os9       F$NMLoad
                    bcs       fail@
found@              leax      CoName,pcr find it in the module directory: its blocks
                    lda       #Systm+Objct
                    ldy       <D.SysPrc
                    leay      P$DATImg,y
                    pshs      u
                    os9       F$FModul
                    tfr       u,x       X = the module directory entry
                    puls      u
                    bcs       fail@
                    lbsr      Image
                    bcs       fail@
                    puls      d
                    std       <D.Proc
* the keyboard, CoArm's globals, then the VBL service
                    ldy       VG.KbEnt,u
                    beq       k@
                    jsr       Kb.Init,y U = VG; a keyboard that does not answer is not an error
k@                  ldb       #CF.Boot
                    lbsr      CoCall
                    bcs       unwind@
                    orcc      #IRQMask
                    ldx       #VG.Addr
                    stx       <D.VBLSt
                    andcc     #^IRQMask
                    clrb
                    puls      y,u,pc
fail@               puls      d
                    std       <D.Proc
unwind@             pshs      b
                    lbsr      ConDown
                    puls      b
                    orcc      #Carry
                    puls      y,u,pc

* Image - X = CoArm's module directory entry, U = VG: software task 1's DAT
* image, and D.TskIPt's task 1 entry pointing at it.  Carry set on error.
Image               pshs      x
                    leay      VG.CoImg,u every slot free, block 0 at slot 0
                    ldd       #DAT.Free
                    ldb       #8
                    pshs      b
                    ldd       #DAT.Free
f@                  std       ,y++
                    dec       ,s
                    bne       f@
                    leas      1,s
                    clra
                    clrb
                    std       VG.CoImg,u
* CoArm's blocks at slots 1 and 2: the module's own image, from the slot
* its pointer is in
                    ldd       MD$MPtr,x
                    anda      #$1F      the offset in its block
                    adda      #Co.Code/256
                    pshs      d         CoArm's address in task 1
                    ldd       MD$MPtr,x
                    lsra
                    lsra
                    lsra
                    lsra
                    lsra
                    lsla                the module's first slot, times 2
                    ldy       MD$MPDAT,x
                    leay      a,y
                    ldd       ,y
                    std       VG.CoImg+2,u
                    ldd       2,y       (the next: CoArm is under 16 K)
                    std       VG.CoImg+4,u
* its entry: M$Exec from the module header, read through the module's image
                    ldx       2,s       the directory entry
                    ldy       MD$MPDAT,x
                    ldx       MD$MPtr,x
                    ldd       #M$Exec
                    os9       F$LDDDXY
                    bcs       e@
                    addd      ,s++
                    std       VG.CoEnt,u
* four data blocks
                    ldb       #Co.DBlks
                    os9       F$AllRAM
                    bcs       e1@
                    std       VG.CoBlk,u
                    leay      VG.CoImg+6,u
                    ldx       #Co.DBlks
d@                  std       ,y++
                    addd      #1
                    leax      -1,x
                    bne       d@
                    orcc      #IntMasks task 1's image is ours now
                    ldx       <D.TskIPt
                    ldd       2,x
                    std       VG.OldImg,u
                    leay      VG.CoImg,u
                    sty       2,x
                    clr       <D.Task1N the next flip must load it
                    andcc     #^IntMasks
                    clrb
                    puls      x,pc
e@                  leas      2,s
e1@                 puls      x
                    orcc      #Carry
                    rts

* ConDown - U = VG: everything ConUp did, undone, as far as it got
ConDown             pshs      y,u
                    orcc      #IRQMask
                    clr       <D.VBLSt
                    clr       <D.VBLSt+1
                    andcc     #^IRQMask
                    ldy       VG.KbEnt,u
                    beq       k@
                    jsr       Kb.Term,y
                    pshs      u
                    ldu       VG.KbMod,u
                    os9       F$UnLink
                    puls      u
k@                  ldd       VG.CoBlk,u
                    beq       i@
                    tfr       d,x
                    ldb       #Co.DBlks
                    os9       F$DelRAM
i@                  ldd       VG.OldImg,u
                    beq       m@
                    orcc      #IntMasks
                    ldx       <D.TskIPt
                    std       2,x
                    clr       <D.Task1N
                    andcc     #^IntMasks
m@                  ldd       <D.Proc
                    pshs      d
                    ldd       <D.SysPrc
                    std       <D.Proc
                    leax      CoName,pcr
                    lda       #Systm+Objct
                    os9       F$UnLoad
                    puls      d
                    std       <D.Proc
                    puls      y,u,pc


********************************************************************
* CoCall - B = the call (CF.*), its arguments in VG.  Returns carry set and
* B = VG.CErr if CoArm answered with an error.  System state, /IRQ open.
CoCall              lbsr      XCheck    an exclusive screen whose owner has gone is free
                    ldx       #VG.Addr
w@                  tst       VG.CBusy,x another window's call is waiting on a blank
                    beq       go@
                    pshs      b
                    ldx       #1
                    os9       F$Sleep
                    puls      b
                    ldx       #VG.Addr
                    bra       w@
go@                 inc       VG.CBusy,x
                    stb       VG.CFn,x
c@                  bsr       Flip
                    ldx       #VG.Addr
                    tst       VG.CWait,x
                    beq       done@
                    pshs      y         CoArm yielded (VG.CWait, CW.*): for the batch to
                    ldy       #VG.Addr  reach the card, for a VBL, or for memory
                    lda       VG.CWait,y
                    cmpa      #CW.Frame
                    beq       fr@
                    cmpa      #CW.Alloc
                    beq       al@
                    cmpa      #CW.Free
                    beq       fe@
                    lbsr      VcBatchWait
                    bra       wk@
fr@                 lbsr      VcFrame
                    bra       wk@
al@                 ldb       VG.CB,y   blocks for CoArm: VG.CX := the first, VG.CErr
                    os9       F$AllRAM
                    bcc       a1@
                    stb       VG.CErr,y
                    bra       wk@
a1@                 std       VG.CX,y
                    clr       VG.CErr,y
                    bra       wk@
fe@                 ldx       VG.CX,y   CoArm's blocks back: VG.CB of them from VG.CX
                    ldb       VG.CB,y
                    os9       F$DelRAM
wk@                 puls      y
                    ldx       #VG.Addr
                    lda       #CF.Resume
                    sta       VG.CFn,x
                    bra       c@
done@               clr       VG.CBusy,x
                    pshs      y         the mouse may have moved the pointer meanwhile
                    ldy       #VG.Addr
                    lbsr      PtrTick1
                    puls      y
                    ldx       #VG.Addr
                    ldb       VG.CSel,x the displayed window gets the keyboard
                    beq       e@
                    lslb
                    abx
                    ldd       VG.WinDev,x
                    ldx       #VG.Addr
                    std       VG.CurDev,x
e@                  ldb       VG.CErr,x
                    beq       ok@
                    orcc      #Carry
                    rts
ok@                 clrb
                    rts

* Flip - into CoArm and back (cowin.asm's L0101).  CoArm's registers are
* all zero but DP, its CC has only E set - /IRQ open, which the kernel's
* IRQ path allows in task 1 (krn.asm S.SysIRQ) - and it returns through
* D.Flip0, whose RTS comes back to Flip's caller.
Flip                pshs      cc
                    orcc      #IntMasks
                    ldx       #VG.Addr
                    lda       ,s+
                    sta       VG.SysCC,x
                    sts       VG.SysStk,x S points at Flip's return
                    lds       <D.CCStk
                    ldd       VG.CoEnt,x
                    pshs      d         PC
                    clra
                    clrb
                    pshs      d         U
                    pshs      d         Y
                    pshs      d         X
                    pshs      a         DP
                    pshs      d         B, A
                    lda       #Entire
                    pshs      a         CC
                    jmp       [>D.Flip1]

********************************************************************
* Read - A := the next key, sleeping until there is one
Read                lda       V.SSigID,u a data-ready signal is armed: not ready
                    bne       NotReady
                    leax      V.InBuf,u
                    ldb       V.InPtr,u
                    orcc      #IRQMask
                    cmpb      V.EndPtr,u
                    beq       sleep@
                    abx
                    lda       ,x
                    incb
                    bpl       k@
                    clrb
k@                  stb       V.InPtr,u
                    andcc     #^(IRQMask+Carry)
                    rts
sleep@              lda       V.BUSY,u
                    sta       V.WAKE,u
                    andcc     #^IRQMask
                    ldx       #0
                    os9       F$Sleep
                    clr       V.WAKE,u
                    ldx       <D.Proc
                    ldb       P$Signal,x
                    beq       Read
                    lda       P$State,x
                    bita      #Condem
                    bne       e@
                    cmpb      #S$Window
                    bhs       Read
e@                  coma
                    rts

NotReady            comb
                    ldb       #E$NotRdy
                    rts

********************************************************************
* Write - A = the byte, for CoArm
Write               ldx       #VG.Addr
                    sta       VG.CA,x
                    lda       V.WinNum,u
                    sta       VG.CWin,x
                    ldb       #CF.Write
                    lbra      CoCall

********************************************************************
* GetStat - A = the code, Y = the path descriptor
GetStat             cmpa      #SS.Ready
                    bne       g1@
                    ldb       V.EndPtr,u
                    subb      V.InPtr,u
                    beq       NotReady
                    bpl       n@
                    addb      #128
n@                  ldx       PD.RGS,y
                    stb       R$B,x
                    clrb
                    rts
g1@                 cmpa      #SS.EOF
                    bne       g2@
                    clrb
                    rts
g2@                 cmpa      #SS.Mouse
                    bne       g3@
                    ldb       #CF.GetStt CoArm builds the packet in VG.MsPkt ...
                    lbsr      ToCo
                    bcs       xm@
                    pshs      y,u       ... and it is moved to the caller's buffer at X
                    ldx       PD.RGS,y
                    ldu       R$X,x
                    ldx       <D.Proc
                    ldb       P$Task,x
                    lda       <D.SysTsk
                    ldx       #VG.Addr+VG.MsPkt
                    ldy       #32
                    os9       F$Move
                    puls      y,u
xm@                 rts
g3@                 ldb       #CF.GetStt
* ToCo - the call B for code A: the caller's B, X and Y go over, and come
* back as CoArm left them
ToCo                pshs      y,u
                    pshs      b         the call
                    ldx       #VG.Addr
                    sta       VG.CA,x
                    ldb       PD.CPR,y  whose
                    stb       VG.CPID,x
                    lda       V.WinNum,u
                    sta       VG.CWin,x
                    ldu       PD.RGS,y
                    lda       R$B,u
                    sta       VG.CB,x
                    ldd       R$X,u
                    std       VG.CX,x
                    ldd       R$Y,u
                    std       VG.CY,x
                    puls      b
                    lbsr      CoCall
                    bcs       x@
                    ldx       #VG.Addr
                    ldu       ,s        the path descriptor
                    ldu       PD.RGS,u
                    lda       VG.CA,x
                    ldb       VG.CB,x
                    std       R$D,u
                    ldd       VG.CX,x
                    std       R$X,u
                    ldd       VG.CY,x
                    std       R$Y,u
                    clrb
x@                  puls      y,u,pc

* SetStat - A = the code, Y = the path descriptor
SetStat             cmpa      #SS.SSig
                    bne       s1@
                    ldx       PD.RGS,y
                    lda       PD.CPR,y
                    ldb       R$X+1,x
                    orcc      #IRQMask
                    pshs      d
                    ldb       V.EndPtr,u
                    cmpb      V.InPtr,u
                    puls      d
                    bne       now@
                    std       V.SSigID,u
                    andcc     #^IRQMask
                    clrb
                    rts
now@                andcc     #^IRQMask
                    os9       F$Send
                    rts
s1@                 cmpa      #SS.Relea
                    bne       s2@
                    lda       PD.CPR,y
                    cmpa      V.SSigID,u
                    bne       x@
                    clr       V.SSigID,u
x@                  clrb
                    rts
s2@                 cmpa      #SS.FrmWait
                    bne       s3@
                    pshs      y         until a VBL has been served
                    ldy       #VG.Addr
                    lbsr      VcFrame
                    ldd       VG.Frames,y
                    puls      y
                    ldx       PD.RGS,y
                    std       R$X,x
                    clrb
                    rts
s3@                 cmpa      #SS.FrmSig
                    bne       s4@
                    ldx       PD.RGS,y
                    lda       R$Y+1,x   every n frames; 0 is off
                    ldb       R$X+1,x   the signal
                    ldx       #VG.Addr
                    pshs      cc
                    orcc      #IRQMask
                    clr       VG.FSPID,x
                    sta       VG.FSN,x
                    sta       VG.FSC,x
                    beq       f@
                    stb       VG.FSSig,x
                    ldb       PD.CPR,y
                    stb       VG.FSPID,x
f@                  puls      cc
                    clrb
                    rts
s4@                 cmpa      #SS.Raster
                    bne       s5@
                    pshs      a,y,u     the table into VG.XBuf: its head, then its entries
                    ldu       #VG.Addr+VG.XBuf
                    ldy       #RT.Tab
                    bsr       FromCaller
                    bcs       xr@
                    ldx       #VG.Addr+VG.XBuf
                    ldd       RT.N,x
                    cmpd      #RT.MaxN
                    bhi       br@
                    lslb
                    rola
                    tfr       d,y
                    cmpy      #0
                    beq       t@
                    ldu       #VG.Addr+VG.XBuf+RT.Tab
                    ldx       1,s       the path descriptor
                    ldx       PD.RGS,x
                    ldx       R$X,x
                    leax      RT.Tab,x
                    bsr       FromCallerX
                    bcs       xr@
t@                  puls      a,y,u
s5@                 cmpa      #SS.Batch the exclusive screen's, ArmIO's own (vidxcl.asm)
                    lbeq      XBatch
                    cmpa      #SS.TileLd
                    lbeq      XTileLd
                    cmpa      #SS.MapWr
                    lbeq      XMapWr
                    cmpa      #SS.TBank
                    lbeq      XTBank
                    ldb       #CF.SetStt
                    lbra      ToCo
br@                 ldb       #E$IllArg
                    coma
xr@                 leas      1,s
                    puls      y,u,pc

* FromCaller - Y bytes from the caller's X (R$X) to the system's U
FromCaller          ldx       2+1,s     the path descriptor (a, y, u pushed by SetStat)
                    ldx       PD.RGS,x
                    ldx       R$X,x
* FromCallerX - Y bytes from the caller's X to the system's U
FromCallerX         pshs      x         (D is not kept: B is F$Move's error)
                    ldx       <D.Proc
                    lda       P$Task,x
                    ldb       <D.SysTsk
                    puls      x
                    os9       F$Move
                    rts

********************************************************************
* Term - U = the statics
Term                ldx       #VG.Addr
                    lda       V.WinNum,u
                    sta       VG.CWin,x
                    ldb       #CF.Term
                    lbsr      CoCall
                    ldx       #VG.Addr
                    ldb       V.WinNum,u
                    lslb
                    abx
                    clr       VG.WinDev,x
                    clr       VG.WinDev+1,x
                    ldx       #VG.Addr
                    cmpu      VG.CurDev,x
                    bne       u@
                    clr       VG.CurDev,x
                    clr       VG.CurDev+1,x
u@                  dec       VG.Users,x
                    bne       x@
                    pshs      u
                    ldu       #VG.Addr
                    lbsr      ConDown
                    puls      u
x@                  clrb
                    rts

* PtrIdle - the kernel's idle loop, IRQs masked and no process to run: the
* pointer to the mouse, if it has moved or is not drawn.  Moving it is 16
* rows read back and 16 written, ~15 ms, so it is done here with IRQs
* enabled between the stream's chunks, and not in KbdArm's /IRQ service.
* Not while a CoArm call is in progress: its end does it.  C set if it drew.
PtrIdle             ldy       #VG.Addr
                    tst       VG.CBusy,y
                    bne       n@
                    tst       VG.PtrBusy,y
                    bne       n@
                    tst       VG.PtrOn,y
                    beq       n@
                    tst       VG.DBit,y
                    beq       n@
                    tst       VG.PtrVis,y
                    beq       go@
                    ldd       VG.PtrX,y
                    cmpd      VG.PtrDX,y
                    bne       go@
                    ldd       VG.PtrY,y
                    cmpd      VG.PtrDY,y
                    bne       go@
n@                  andcc     #^Carry
                    rts
go@                 inc       VG.PtrBusy,y
                    andcc     #^IntMasks
                    lbsr      PtrMove
                    orcc      #IntMasks
                    clr       VG.PtrBusy,y
                    tst       VG.PtrVis,y
                    beq       n@
                    orcc      #Carry
                    rts

* PtrTick1 - Y = VG: the pointer to the mouse, at a CoArm call's end
PtrTick1            tst       VG.PtrBusy,y
                    bne       x@
                    inc       VG.PtrBusy,y
                    lbsr      PtrMove
                    clr       VG.PtrBusy,y
x@                  rts

                    use       vidsvc.asm
                    use       vidxcl.asm
                    use       vidptr.asm
                    use       vidcore.asm

                    emod
eom                 equ       *
                    end
