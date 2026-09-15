********************************************************************
* CoArm - the arm6309 video console's output half
*
* ArmIO (the driver) sends every byte written to a window device here.
* CoArm runs in software task 1, entered from ArmIO through D.Flip1 and
* leaving through D.Flip0 (defs/armvid.d: the system map has no room for
* it).  It makes no system calls: where it must wait for a blank, or needs
* memory, it yields, and ArmIO does it and resumes it.
*
* CoArm parses CoWin's protocol - control codes $00-$1F, the $1F pairs and
* the $1B escapes with CoWin's parameter counts - for two kinds of screen:
*
*   fast text ($18, $19)       ca_text.asm: cell mode, one map write a
*                              character (graphics.md 6.4.8)
*   bitmap ($10-$13)           640 x 200, 240, 400 or 480, 8bpp: windows,
*                              overlays, text in 8 x 8 cells, graphics and
*                              GP buffers (ca_scr, ca_bmtx, ca_draw, ca_gpb)
*
* and draws through the row layer (ca_row.asm), whose two back-ends are the
* card, through VidCore (vidcore.asm), and a DRAM store for a screen that
* is not displayed.  arm6309 software/nitros9/docs/video-console.md is the
* reference: it says where CoArm follows CoWin and where it does not.
*
* Registers: Y = VG, always.  U = the window being drawn (the device's
* current window: itself or its top overlay) and X = its screen, as Cur
* leaves them; CG.Dev = the device window, whose parser state the bytes run.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phases P1 (fast text), P2 (bitmap screens and windows) and P3
* (display lists, ca_list.asm).

                    nam       CoArm
                    ttl       arm6309 video console output

                    ifp1
                    use       defsfile
                    use       armvid.d
                    endc

tylg                set       Systm+Objct
atrv                set       ReEnt+rev
rev                 set       0
edition             set       2

                    mod       eom,name,tylg,atrv,entry,0

name                fcs       /CoArm/
                    fcb       edition

CoG                 equ       Co.Data   CoArm's globals, in its own map

* Entered by ArmIO's Flip with a full RTI frame: every register zero, the
* call in VG.CFn.  /IRQ is open, and an IRQ taken here stacks on S.  So S
* stays on the flip's frame, above Co.Stack, until the call is known: a
* Resume's yielded stack is under Co.Stack, and an IRQ taken after
* LDS #Co.Stack would stack over it.
entry               ldy       #VG.Addr
                    ldb       VG.CFn,y
                    cmpb      #CF.Resume
                    lbeq      Resume
                    lbhi      bad@      (CoRet leaves on D.CCStk: it needs no stack of CoArm's)
                    lds       #Co.Stack
                    clr       >CoG+CG.PtrHid
                    lslb
                    leax      CallTbl,pcr
                    ldd       b,x
                    leax      d,x
                    pshs      x
                    ldb       VG.CWin,y the device window
                    lbsr      WRec
                    stu       >CoG+CG.Dev
                    lda       VG.CA,y
                    jsr       [,s++]
                    pshs      b,cc
                    lbsr      PtrBack   a pointer the drawing took off goes back
                    puls      b,cc
                    bcs       CoRet
                    clrb
                    bra       CoRet
bad@                ldb       #E$UnkSvc
* CoRet - B = 0 or an error: the call is over
CoRet               ldy       #VG.Addr
                    stb       VG.CErr,y
                    clr       VG.CWait,y
* CoExit - back to ArmIO through D.Flip0 (grfdrv.asm's SysRet): A = its CC,
* X = its stack, and S on a stack both maps see, for Flip0's own push
CoExit              ldy       #VG.Addr
                    lda       VG.SysCC,y
                    orcc      #IntMasks
                    ldx       VG.SysStk,y
                    lds       <D.CCStk
                    jmp       [>D.Flip0]

CallTbl             fdb       CoBoot-CallTbl      CF.Boot
                    fdb       CoInit-CallTbl      CF.Init
                    fdb       CoWrite-CallTbl     CF.Write
                    fdb       CoGetStt-CallTbl    CF.GetStt
                    fdb       CoSetStt-CallTbl    CF.SetStt
                    fdb       CoTerm-CallTbl      CF.Term

********************************************************************
* Yielding.  Every register is kept, and the stack stays where it is:
* Co.Stack is under the flip's frame.

* Yield - A = the reason (CW.*)
Yield               pshs      d,x,y,u
                    sts       >CoG+CG.YieldS
                    ldy       #VG.Addr
                    sta       VG.CWait,y
                    lbra      CoExit

Resume              lds       >CoG+CG.YieldS
                    puls      d,x,y,u,pc

* CoYield - until the frame batch is empty
CoYield             pshs      a
                    lda       #CW.Batch
                    bsr       Yield
                    puls      a,pc

* CoFrame - until a VBL has been served
CoFrame             pshs      a
                    lda       #CW.Frame
                    bsr       Yield
                    puls      a,pc

* CoAlloc - B blocks of RAM: D := the first; carry set, B = the error, if
* there are not that many
CoAlloc             pshs      y
                    ldy       #VG.Addr
                    stb       VG.CB,y
                    lda       #CW.Alloc
                    bsr       Yield
                    ldb       VG.CErr,y
                    bne       e@
                    ldd       VG.CX,y
                    andcc     #^Carry
                    puls      y,pc
e@                  orcc      #Carry
                    puls      y,pc

* CoFree - B blocks from X, back to the system
CoFree              pshs      d,y
                    ldy       #VG.Addr
                    stx       VG.CX,y
                    stb       VG.CB,y
                    lda       #CW.Free
                    bsr       Yield
                    puls      d,y,pc

********************************************************************
* Records

* WRec - B = a window's index: U := its record
WRec                pshs      d
                    lda       #WT.Size
                    mul
                    addd      #CoG+CG.Win
                    tfr       d,u
                    puls      d,pc

* SRec - B = a screen's number: X := its record
SRec                pshs      b
                    ldx       #CoG+CG.Scr
                    tstb
                    beq       x@
s@                  leax      SC.Size,x
                    decb
                    bne       s@
x@                  puls      b,pc

* WIdx - U = a window record: B := its index
WIdx                pshs      a,x
                    tfr       u,d
                    subd      #CoG+CG.Win
                    tfr       d,x
                    clrb
i@                  cmpx      #0
                    beq       x@
                    leax      -WT.Size,x
                    incb
                    bra       i@
x@                  puls      a,x,pc

* SIdx - X = a screen record: B := its number
SIdx                pshs      a,x
                    tfr       x,d
                    subd      #CoG+CG.Scr
                    tfr       d,x
                    clrb
i@                  cmpx      #0
                    beq       x@
                    leax      -SC.Size,x
                    incb
                    bra       i@
x@                  puls      a,x,pc

********************************************************************
* CoBoot - CoArm's globals: no windows, no screens, no buffers
CoBoot              ldx       #CoG
                    ldd       #CG.Size
c@                  clr       ,x+
                    subd      #1
                    bne       c@
                    ldd       #$FFFF    no block in either window yet
                    std       >CoG+CG.WinA
                    std       >CoG+CG.WinB
                    clrb
                    rts

* CoInit - A = IT.VAL: with it set, the window is made from VG.CParm, the
* descriptor's defaults, as CoWin does
CoInit              pshs      a
                    tfr       u,x
                    ldb       #WT.Size
c@                  clr       ,x+
                    decb
                    bne       c@
                    inc       WT.Used,u
                    lda       #$FF
                    sta       WT.Scr,u
                    sta       WT.Par,u
                    lda       VG.CWin,y
                    sta       WT.Cur,u
                    puls      a
                    tsta
                    beq       ok@
                    leax      VG.CParm,y
                    leau      WT.Parms,u
                    ldb       #8
m@                  lda       ,x+
                    sta       ,u+
                    decb
                    bne       m@
                    lbsr      CurQ
                    lbra      DoDWSet
ok@                 clrb
                    rts

* CoTerm - the device's windows go, and a screen left with none
CoTerm              lbsr      DevEnd
                    ldu       >CoG+CG.Dev
                    clr       WT.Used,u
                    clrb
                    rts

********************************************************************
* CoWrite - A = the byte
CoWrite             ldu       >CoG+CG.Dev
                    ldx       WT.EscVct,u
                    beq       plain@
                    jmp       ,x
plain@              tst       WT.Ansi,u an ANSI terminal's bytes (ca_ext.asm)
                    lbne      AnsiByte
                    cmpa      #$1B
                    lbeq      EscStart
                    lbsr      Cur       U := the current window, X := its screen
                    lbsr      Mute      nothing is drawn on a tile or exclusive screen
                    beq       nop@
                    cmpa      #C$SPAC
                    lbhs      PutCh
                    cmpa      #$1F
                    lbeq      AttrStart
                    cmpa      #$0D
                    bhi       nop@
                    lsla
                    leax      CtlTbl,pcr
                    ldd       a,x
                    leax      d,x
                    pshs      x
                    ldx       >CoG+CG.CurS
                    rts                 into the routine: U, X as Cur left them
nop@                clrb
                    rts

* Cur - U := the device's current window, X := its screen (and CG.CurS);
* with no screen, E$WUndef goes back to CoWrite's caller.  A is kept.
Cur                 bsr       CurQ
                    cmpx      #0
                    beq       no@
                    rts
no@                 leas      2,s
                    comb
                    ldb       #E$WUndef
                    rts

* CurQ - U := the current window and X its screen, or X = 0 if the device
* has none yet.  A is kept.
CurQ                pshs      a
                    ldu       >CoG+CG.Dev
                    ldb       WT.Cur,u
                    lbsr      WRec
                    ldx       #0
                    ldb       WT.Scr,u
                    cmpb      #$FF
                    beq       n@
                    lbsr      SRec
n@                  stx       >CoG+CG.CurS
                    stu       >CoG+CG.WPtr
                    puls      a,pc

* Collect - A = parameter bytes to gather, X = the routine that takes them.
* It is entered as an escape routine is: U and X as CurQ leaves them, the
* bytes in the device's WT.Parms (Prm, PrmW).
Collect             pshs      u
                    ldu       >CoG+CG.Dev
                    sta       WT.PrmCnt,u
                    stx       WT.PrmFn,u
                    leax      WT.Parms,u
                    stx       WT.PrmPtr,u
                    leax      Collect1,pcr
                    stx       WT.EscVct,u
                    puls      u
                    clrb
                    rts

Collect1            ldx       WT.PrmPtr,u
                    sta       ,x+
                    stx       WT.PrmPtr,u
                    dec       WT.PrmCnt,u
                    beq       go@
                    clrb
                    rts
go@                 clra
                    clrb
                    std       WT.EscVct,u
                    ldx       WT.PrmFn,u
                    pshs      x
                    lbra      CurQ      and its RTS goes into the routine

* Prm - A := parameter byte B; PrmW - D := the big-endian word at B
Prm                 pshs      x
                    ldx       >CoG+CG.Dev
                    abx
                    lda       WT.Parms,x
                    puls      x,pc

PrmW                pshs      x
                    ldx       >CoG+CG.Dev
                    abx
                    ldd       WT.Parms,x
                    puls      x,pc

* NeedScr - an escape routine that needs a screen: X = 0 goes back to
* CoWrite's caller with E$WUndef
NeedScr             cmpx      #0
                    beq       no@
                    rts
no@                 leas      2,s
                    comb
                    ldb       #E$WUndef
                    rts

* IsBmp - X = a screen: Z set if it is a bitmap ($10-$13)
IsBmp               pshs      a
                    lda       SC.Type,x
                    anda      #$FC
                    cmpa      #$10
                    puls      a,pc

* IsTile - X = a screen: Z set if it is a tile screen ($1C, $1D)
IsTile              pshs      a
                    lda       SC.Type,x
                    anda      #$FE
                    cmpa      #STY.Tile25
                    puls      a,pc

* IsText - X = a screen: Z set if it is fast text
IsText              pshs      a
                    lda       SC.Type,x
                    cmpa      #STY.Txt25
                    beq       x@
                    cmpa      #STY.Txt30
x@                  puls      a,pc

********************************************************************
* Control codes: the fast-text screen's (ca_text.asm) or a bitmap
* window's (ca_bmtx.asm), by the screen's type
CtlTbl              fdb       CtlNop-CtlTbl       $00
                    fdb       CtlHome-CtlTbl      $01 home
                    fdb       CtlXY-CtlTbl        $02 X+32 Y+32
                    fdb       CtlErLn-CtlTbl      $03 erase line
                    fdb       CtlErEOL-CtlTbl     $04 erase to end of line
                    fdb       CtlCur-CtlTbl       $05 $20 off, $21 on
                    fdb       CtlRight-CtlTbl     $06 cursor right
                    fdb       CtlNop-CtlTbl       $07 bell: AudDrv, plan phase P4
                    fdb       CtlLeft-CtlTbl      $08 cursor left
                    fdb       CtlUp-CtlTbl        $09 cursor up
                    fdb       CtlDown-CtlTbl      $0A cursor down, line feed
                    fdb       CtlErEOS-CtlTbl     $0B erase to end of screen
                    fdb       CtlCls-CtlTbl       $0C clear screen
                    fdb       CtlCR-CtlTbl        $0D carriage return

CtlNop              clrb
                    rts

* $1F xx
AttrStart           lda       #1
                    leax      DoAttr,pcr
                    lbra      Collect

********************************************************************
* Escapes.  EscTbl is CoWin's own parameter counts for $20-$54, so every
* sequence consumes exactly its parameters.  Each entry: the count ($FF:
* CoWin has nothing there), and the routine as an offset from EscTbl.
EscStart            leax      EscCode,pcr
                    ldu       >CoG+CG.Dev
                    stx       WT.EscVct,u
                    clrb
                    rts

EscCode             clr       WT.EscVct,u
                    clr       WT.EscVct+1,u
                    suba      #$20
                    blo       x@
                    cmpa      #EscTblN
                    bhs       x@
                    pshs      a         a tile or exclusive screen takes only Select, DWEnd
                    lbsr      CurQ      and the palette's escapes
                    cmpx      #0
                    beq       ok@
                    lbsr      Mute
                    bne       ok@
                    lda       ,s
                    cmpa      #$21-$20
                    beq       ok@
                    cmpa      #$24-$20
                    beq       ok@
                    cmpa      #$30-$20
                    beq       ok@
                    cmpa      #$31-$20
                    beq       ok@
                    cmpa      #$60-$20
                    beq       ok@
                    cmpa      #$61-$20
                    beq       ok@
                    puls      a
                    comb
                    ldb       #E$IWTyp
                    rts
ok@                 puls      a
                    tfr       a,b       B * 3, unsigned: the entry
                    lslb
                    pshs      a
                    addb      ,s+
                    leax      EscTbl,pcr
                    abx
                    lda       ,x
                    cmpa      #$FF
                    beq       x@
                    pshs      a
                    ldd       1,x
                    leax      EscTbl,pcr
                    leax      d,x
                    puls      a
                    tsta
                    lbne      Collect
                    pshs      x
                    lbra      CurQ      and into the routine
x@                  clrb
                    rts

EscTbl              fcb       7
                    fdb       DoDWSet0-EscTbl     $20 DWSet
                    fcb       0
                    fdb       DoSelect-EscTbl     $21 Select
                    fcb       7
                    fdb       DoOWSet-EscTbl      $22 OWSet
                    fcb       0
                    fdb       DoOWEnd-EscTbl      $23 OWEnd
                    fcb       0
                    fdb       DoDWEnd-EscTbl      $24 DWEnd
                    fcb       4
                    fdb       DoCWArea-EscTbl     $25 CWArea
                    fcb       $FF,0,0             $26
                    fcb       $FF,0,0             $27
                    fcb       $FF,0,0             $28
                    fcb       4
                    fdb       DoDefGPB-EscTbl     $29 DefGPB
                    fcb       2
                    fdb       DoKillBuf-EscTbl    $2A KillBuf
                    fcb       9
                    fdb       DoGPLoad-EscTbl     $2B GPLoad
                    fcb       10
                    fdb       DoGetBlk-EscTbl     $2C GetBlk
                    fcb       6
                    fdb       DoPutBlk-EscTbl     $2D PutBlk
                    fcb       2
                    fdb       DoPSet-EscTbl       $2E PSet
                    fcb       1
                    fdb       DoLSet-EscTbl       $2F LSet
                    fcb       0
                    fdb       DoDefPal-EscTbl     $30 DefColr
                    fcb       2
                    fdb       DoPalette-EscTbl    $31 Palette
                    fcb       1
                    fdb       DoFColor-EscTbl     $32 FColor
                    fcb       1
                    fdb       DoBColor-EscTbl     $33 BColor
                    fcb       1
                    fdb       EscNop-EscTbl       $34 Border: the card has none (graphics.md 9.3)
                    fcb       1
                    fdb       EscNop-EscTbl       $35 ScaleSw: the new screen types are never scaled
                    fcb       1
                    fdb       EscNop-EscTbl       $36 DWProtSw
                    fcb       $FF,0,0             $37
                    fcb       $FF,0,0             $38
                    fcb       2
                    fdb       DoGCSet-EscTbl      $39 GCSet
                    fcb       2
                    fdb       DoFont-EscTbl       $3A Font
                    fcb       $FF,0,0             $3B
                    fcb       1
                    fdb       DoTChar-EscTbl      $3C TCharSw
                    fcb       1
                    fdb       DoBold-EscTbl       $3D BoldSw
                    fcb       $FF,0,0             $3E
                    fcb       1
                    fdb       EscNop-EscTbl       $3F PropSw
                    fcb       4
                    fdb       DoSetDP-EscTbl      $40 SetDPtr
                    fcb       4
                    fdb       DoRSetDP-EscTbl     $41 RSetDPtr
                    fcb       4
                    fdb       DoPoint-EscTbl      $42 Point
                    fcb       4
                    fdb       DoRPoint-EscTbl     $43 RPoint
                    fcb       4
                    fdb       DoLine-EscTbl       $44 Line
                    fcb       4
                    fdb       DoRLine-EscTbl      $45 RLine
                    fcb       4
                    fdb       DoLineM-EscTbl      $46 LineM
                    fcb       4
                    fdb       DoRLineM-EscTbl     $47 RLineM
                    fcb       4
                    fdb       DoBox-EscTbl        $48 Box
                    fcb       4
                    fdb       DoRBox-EscTbl       $49 RBox
                    fcb       4
                    fdb       DoBar-EscTbl        $4A Bar
                    fcb       4
                    fdb       DoRBar-EscTbl       $4B RBar
                    fcb       $FF,0,0             $4C
                    fcb       $FF,0,0             $4D
                    fcb       4
                    fdb       DoPutGC-EscTbl      $4E PutGC
                    fcb       0
                    fdb       DoFFill-EscTbl      $4F FFill
                    fcb       2
                    fdb       DoCircle-EscTbl     $50 Circle
                    fcb       4
                    fdb       DoEllipse-EscTbl    $51 Ellipse
                    fcb       12
                    fdb       DoArc-EscTbl        $52 Arc
                    fcb       2
                    fdb       DoFCircle-EscTbl    $53 filled Circle
                    fcb       4
                    fdb       DoFEllipse-EscTbl   $54 filled Ellipse
                    fcb       $FF,0,0             $55
                    fcb       $FF,0,0             $56
                    fcb       $FF,0,0             $57
                    fcb       $FF,0,0             $58
                    fcb       $FF,0,0             $59
                    fcb       $FF,0,0             $5A
                    fcb       $FF,0,0             $5B
                    fcb       $FF,0,0             $5C
                    fcb       $FF,0,0             $5D
                    fcb       $FF,0,0             $5E
                    fcb       $FF,0,0             $5F
* the extensions (plan 5.2)
                    fcb       3
                    fdb       DoPal565-EscTbl     $60 Pal565
                    fcb       2
                    fdb       DoPalRng-EscTbl     $61 PalRange
                    fcb       9
                    fdb       DoPatDef-EscTbl     $62 PatDef
                    fcb       8
                    fdb       DoPatBar-EscTbl     $63 PatBar
                    fcb       6
                    fdb       DoPutMsk-EscTbl     $64 PutMask
                    fcb       2
                    fdb       DoPoly-EscTbl       $65 Poly
                    fcb       2
                    fdb       DoPolyP-EscTbl      $66 PolyPat
                    fcb       6
                    fdb       DoPutBlk-EscTbl     $67 Image: PutBlk, for an 8bpp buffer
                    fcb       7
                    fdb       DoIcon-EscTbl       $68 Icon
                    fcb       1
                    fdb       DoAnsiSw-EscTbl     $69 AnsiSw
EscTblN             equ       (*-EscTbl)/3

EscNop              clrb
                    rts

********************************************************************
* GetStat and SetStat.  ArmIO has answered what is its own.  A = the code;
* VG.CA, CB, CX and CY hold the caller's A, B, X and Y, and go back to it
* as they are left.
CoGetStt            lbsr      CurQ
                    cmpa      #SS.Mouse the mouse has no need of a window
                    lbeq      MsPkt
                    cmpx      #0
                    beq       unk@
                    cmpa      #SS.ScSiz
                    bne       g1@
                    lbsr      IsText
                    bne       bm@
                    clra
                    ldb       SC.Cols,x
                    std       VG.CX,y
                    ldb       SC.Rows,x
                    std       VG.CY,y
                    bra       ok@
bm@                 ldd       WT.AW,u   a bitmap window: its working area, in cells
                    lsra
                    rorb
                    lsra
                    rorb
                    lsra
                    rorb
                    std       VG.CX,y
                    ldd       WT.AH,u
                    lsra
                    rorb
                    lsra
                    rorb
                    lsra
                    rorb
                    std       VG.CY,y
                    bra       ok@
g1@                 cmpa      #SS.ScTyp
                    bne       g2@
                    lda       SC.Type,x
                    sta       VG.CA,y
                    bra       ok@
g2@                 cmpa      #SS.FBRgs
                    bne       g3@
                    lda       WT.FG,u
                    ldb       WT.BG,u
                    std       VG.CA,y
                    clra
                    clrb
                    std       VG.CX,y
                    bra       ok@
g3@                 cmpa      #SS.Cursr
                    bne       unk@
                    clra
                    ldb       WT.CX,u
                    std       VG.CX,y
                    ldb       WT.CY,u
                    std       VG.CY,y
                    lbsr      CharAt    A := the character under the cursor
                    sta       VG.CA,y
ok@                 clrb
                    rts
unk@                comb
                    ldb       #E$UnkSvc
                    rts

CoSetStt            cmpa      #SS.Excl
                    bne       s1@
                    lbsr      Cur
                    lbra      DoExcl
s1@                 cmpa      #SS.RastOff
                    lbeq      DoRastOff
                    cmpa      #SS.Raster
                    bne       u@
                    lbsr      Cur
                    lbra      DoRaster
u@                  comb
                    ldb       #E$UnkSvc
                    rts

                    use       ca_scr.asm
                    use       ca_text.asm
                    use       ca_bmtx.asm
                    use       ca_draw.asm
                    use       ca_gpb.asm
                    use       ca_row.asm
                    use       ca_ptr.asm
                    use       ca_list.asm
                    use       ca_tile.asm
                    use       ca_ext.asm
                    use       vidptr.asm
                    use       vidcore.asm
                    use       coarmfont.asm

                    emod
eom                 equ       *
* ⚠ ArmIO maps CoArm at slots 1-2 (the recipe checks its size) and its
* globals at 3-4 (armvid.d Co.*)
                    ifgt      CG.Size-Co.DBlks*$2000
                    error     CoArm's globals are more than Co.DBlks blocks
                    endc
                    end
