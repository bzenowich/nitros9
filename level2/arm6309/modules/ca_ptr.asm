********************************************************************
* ca_ptr.asm - CoArm's side of the pointer and the mouse: GCSet, PutGC,
* SS.Mouse, and keeping the pointer off what CoArm draws
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P2.

* PtrOff - the pointer off the card (it comes back when CoArm's call ends,
* if CG.PtrHid is set)
PtrOff              lbra      PtrErase

* PtrBack - at the end of every call: the pointer drawn again if the call
* took it off, or moved if the mouse or PutGC moved it
PtrBack             tst       >CoG+CG.PtrHid
                    beq       m@
                    clr       >CoG+CG.PtrHid
                    lbra      PtrDraw
m@                  lbra      PtrMove

* PtrScreen - Select has displayed a screen: the pointer's view of it
PtrScreen           pshs      d,x
                    clr       VG.PtrVis,y the pixels it saved are gone with the old picture
                    clr       VG.DBit,y
                    ldb       >CoG+CG.Disp
                    beq       x@
                    decb
                    lbsr      SRec
                    lbsr      IsBmp
                    bne       x@
                    inc       VG.DBit,y
                    ldd       SC.Top,x
                    std       VG.DTop,y
                    ldd       SC.H,x
                    std       VG.DH,y
                    lbsr      PtrClamp
                    inc       >CoG+CG.PtrHid drawn when the call ends
x@                  puls      d,x,pc

* PtrClamp - the mouse and the pointer inside the displayed screen
PtrClamp            pshs      d
                    ldd       VG.MsX,y
                    cmpd      #639
                    bls       x@
                    ldd       #639
                    std       VG.MsX,y
x@                  ldd       VG.DH,y
                    subd      #1
                    cmpd      VG.MsY,y
                    bhs       y@
                    std       VG.MsY,y
y@                  ldd       VG.MsX,y
                    std       VG.PtrX,y
                    ldd       VG.MsY,y
                    std       VG.PtrY,y
                    puls      d,pc

* PtrGuard - a card op is about to cover CG.RN pixels of rows CG.RY to
* CG.RY + A - 1 from CG.RX: the pointer comes off first if it is under them
PtrGuard            tst       VG.PtrVis,y
                    beq       x@
                    pshs      d
                    ldd       >CoG+CG.RY rows: RY < DY + H and RY + A > DY
                    pshs      d
                    ldd       VG.PtrDY,y
                    addb      VG.PtrH,y
                    adca      #0
                    cmpd      ,s
                    bls       no@
                    clra
                    ldb       2,s       A, as it came
                    addd      ,s
                    cmpd      VG.PtrDY,y
                    bls       no@
                    ldd       >CoG+CG.RX columns: RX < DX + 16 and RX + RN > DX
                    std       ,s
                    ldd       VG.PtrDX,y
                    addd      #16
                    cmpd      ,s
                    bls       no@
                    ldd       >CoG+CG.RX
                    addd      >CoG+CG.RN
                    cmpd      VG.PtrDX,y
                    bls       no@
                    lbsr      PtrErase
                    inc       >CoG+CG.PtrHid
no@                 leas      2,s
                    puls      d
x@                  rts

********************************************************************
* GCSet grp buf: group 0, no pointer; any other, the arrow
DoGCSet             ldb       #0
                    lbsr      Prm
                    tsta
                    bne       on@
                    lbsr      PtrErase
                    clr       VG.PtrOn,y
                    clrb
                    rts
on@                 lda       #1
                    sta       VG.PtrOn,y
                    inc       >CoG+CG.PtrHid drawn when the call ends
                    clrb
                    rts

* PutGC x y: the pointer, in screen pixels
DoPutGC             ldb       #0
                    lbsr      PrmW
                    std       VG.MsX,y
                    ldb       #2
                    lbsr      PrmW
                    std       VG.MsY,y
                    tst       VG.DBit,y
                    beq       x@
                    lbsr      PtrClamp
x@                  clrb
                    rts

* MsPkt - SS.Mouse: VG.MsPkt, cocovtio.d's Pt.* packet, for ArmIO to move
* to the caller.  A device that does not have the keyboard gets zeros.
Pt.Valid            equ       $00
Pt.CBSA             equ       $08
Pt.CBSB             equ       $09
Pt.Stat             equ       $16
Pt.AcX              equ       $18
Pt.AcY              equ       $1A
Pt.WRX              equ       $1C
Pt.WRY              equ       $1E

MsPkt               pshs      d,x,u
                    leax      VG.MsPkt,y
                    ldb       #32
c@                  clr       ,x+
                    decb
                    bne       c@
                    ldu       >CoG+CG.Dev
                    lbsr      WIdx
                    cmpb      VG.CSel,y
                    bne       x@
                    lda       #1
                    sta       VG.MsPkt+Pt.Valid,y
                    lda       VG.MsBtn,y
                    anda      #1
                    sta       VG.MsPkt+Pt.CBSA,y
                    lda       VG.MsBtn,y
                    lsra
                    anda      #1
                    sta       VG.MsPkt+Pt.CBSB,y
                    ldd       VG.MsX,y
                    std       VG.MsPkt+Pt.AcX,y
                    ldd       VG.MsY,y
                    std       VG.MsPkt+Pt.AcY,y
                    lbsr      CurQ      in the current window's working area?
                    cmpx      #0
                    beq       off@
                    ldd       VG.MsX,y
                    subd      WT.AX,u
                    blt       off@
                    cmpd      WT.AW,u
                    bge       off@
                    std       VG.MsPkt+Pt.WRX,y
                    ldd       VG.MsY,y
                    subd      WT.AY,u
                    blt       off@
                    cmpd      WT.AH,u
                    bge       off@
                    std       VG.MsPkt+Pt.WRY,y
                    bra       x@
off@                lda       #2        off the window: no window-relative position
                    sta       VG.MsPkt+Pt.Stat,y
                    clra
                    clrb
                    std       VG.MsPkt+Pt.WRX,y
                    std       VG.MsPkt+Pt.WRY,y
x@                  clrb
                    puls      d,x,u,pc
