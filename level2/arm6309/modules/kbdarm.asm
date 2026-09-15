********************************************************************
* KbdArm - the arm6309 PS/2 keyboard, for ArmIO
*
* io/ps2/docs/ps2.md is the card: four registers, raw set-2 scan codes,
* a byte latch per port, and transmit done by software (7).  This module
* initialises the keyboard port by 11.2, puts a service on the /IRQ
* polling table for IOSTAT's KDR, and turns scan codes into characters
* for the window whose screen is displayed (VG.CurDev).
*
* The translation tables are Wildbits' keydrv_ps2 (the same set-2 codes,
* CoCo 3 key values: the arrows are $0C $0A $08 $09, Esc is BREAK $05,
* F1 and F2 are $B1 and $B2).
*
* The mouse port too (plan P2's MseArm, folded in: one service for both
* ports): initialised by 11.2, its 3-byte packets move VG.MsX, VG.MsY and
* VG.MsBtn, and through ArmIO the pointer.
*
* What it does not do: LEDs (a transmit masks /IRQ for ~2 ms a byte, ps2.md
* 7.1, so Caps Lock's state is kept and not shown), typematic, and the
* IntelliMouse wheel.
*
* Entry table: Init, Term, each with U = VG.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P1.

                    nam       KbdArm
                    ttl       arm6309 PS/2 keyboard

                    ifp1
                    use       defsfile
                    use       armvid.d
                    endc

tylg                set       Systm+Objct
atrv                set       ReEnt+rev
rev                 set       0
edition             set       1

                    mod       eom,name,tylg,atrv,start,0

name                fcs       /KbdArm/
                    fcb       edition

start               lbra      Init
                    lbra      Term

* VG.KbFlag bits
KF.E0               equ       %00000001 the last byte was the E0 prefix

KF.F0               equ       %00000010 the next code is a release

KF.Shift            equ       %00000100

KF.Ctrl             equ       %00001000

KF.Alt              equ       %00010000

KF.Caps             equ       %00100000

* Both ports' ready bits, and both ports' enables (IOCTRL b6 KIRQEN, b7
* MIRQEN, ps2.md 3.1).  The card had one enable for both until 2026-09-14,
* and a service that took only KDR left MDR's power-on bytes (AA 00) holding
* the line: IOMan's poll found no one to claim it, and the kernel went back
* from the IRQ with interrupts masked - found on the first run.  A driver
* for one port now enables that port alone.
IRQPkt              fcb       0         flip: a ready bit reads 1 when a byte waits
                    fcb       %00000011 mask: KDR and MDR
                    fcb       $F0       priority

********************************************************************
* Init - U = VG.  ps2.md 11.2: phase, reset (FA AA), enable (FA).  A
* keyboard that does not answer leaves the port without a service, and is
* not an error: the console still writes.
Init                clr       VG.KbFlag,u
                    clr       VG.KbSkip,u
                    clr       VG.MsIdx,u
                    clr       VG.KbPort,u the keyboard: FF (FA AA), F4 (FA)
                    lbsr      Phase
                    lda       #$FF
                    ldb       #2
                    lbsr      Cmd
                    bcs       ms@
                    lda       #$F4
                    ldb       #1
                    lbsr      Cmd
ms@                 lda       #1        the mouse: FF (FA AA 00), F3 3C (FA FA), F4 (FA)
                    sta       VG.KbPort,u
                    lbsr      Phase
                    lda       #$FF
                    ldb       #3
                    lbsr      Cmd
                    bcs       irq@
                    lda       #$F3
                    ldb       #1
                    lbsr      Cmd
                    bcs       irq@
                    lda       #$3C      60 samples a second (ps2.md 5.2)
                    ldb       #1
                    lbsr      Cmd
                    bcs       irq@
                    lda       #$F4
                    ldb       #1
                    lbsr      Cmd
irq@                clr       VG.KbPort,u
                    ldx       VG.KBase,u
                    lda       PR.KDATA,x anything left in either latch
                    lda       PR.MDATA,x
                    ldd       VG.KBase,u
                    addd      #PR.IOSTAT
                    leax      IRQPkt,pcr
                    leay      Svc,pcr
                    os9       F$IRQ
                    bcs       x@
                    lda       VG.IOCtl,u KIRQEN and MIRQEN: both ports are serviced
                    ora       #%11000000
                    lbsr      PutCtl
x@                  clrb
                    rts

* Term - U = VG
Term                lda       VG.IOCtl,u
                    anda      #^%11000000
                    lbsr      PutCtl
                    ldx       #0
                    leay      Svc,pcr
                    os9       F$IRQ
                    clrb
                    rts

********************************************************************
* Svc - the /IRQ service: U = VG.  Every byte the latch holds.
Svc                 ldx       VG.KBase,u
                    lda       PR.IOSTAT,x
                    bita      #%00000010 MDR: a mouse byte
                    beq       k@
                    lda       PR.MDATA,x the read clears MDR
                    lbsr      Mouse
                    bra       Svc
k@                  lsra
                    bcc       x@
                    lda       PR.KDATA,x the read clears KDR
                    lbsr      Scan
                    bra       Svc
x@                  clrb
                    rts

* Mouse - A = a byte of a 3-byte packet (ps2.md 11.3): the position and
* buttons.  The pointer follows from the kernel's idle loop (ArmIO's PtrIdle)
Mouse               ldb       VG.MsIdx,u
                    bne       b1@
                    bita      #%00001000 byte 1's bit 3 is always 1: otherwise out of step
                    beq       x@
                    sta       VG.MsB0,u
                    inc       VG.MsIdx,u
x@                  rts
b1@                 cmpb      #1
                    bne       b2@
                    sta       VG.MsB1,u
                    inc       VG.MsIdx,u
                    rts
b2@                 clr       VG.MsIdx,u
                    pshs      a         Y: byte 3, sign from byte 1's bit 5, positive up
                    lda       VG.MsB0,u
                    anda      #7
                    sta       VG.MsBtn,u
                    ldb       VG.MsB1,u X: byte 2, sign from bit 4
                    clra
                    tst       VG.MsB0,u
                    pshs      b
                    lda       VG.MsB0,u
                    bita      #%00010000
                    puls      b
                    beq       xp@
                    lda       #$FF
                    bra       xa@
xp@                 clra
xa@                 addd      VG.MsX,u
                    bpl       x0@
                    clra
                    clrb
x0@                 cmpd      #639
                    ble       x1@
                    ldd       #639
x1@                 std       VG.MsX,u
                    puls      b
                    lda       VG.MsB0,u
                    bita      #%00100000
                    beq       yp@
                    lda       #$FF
                    bra       ya@
yp@                 clra
ya@                 pshs      d
                    ldd       VG.MsY,u  y := y - dy
                    subd      ,s++
                    bpl       y0@
                    clra
                    clrb
y0@                 pshs      d
                    ldd       #480      the displayed bitmap's height, or 480
                    tst       VG.DBit,u
                    beq       h@
                    ldd       VG.DH,u
h@                  subd      #1
                    cmpd      ,s
                    bge       y1@
                    std       ,s
y1@                 puls      d
                    std       VG.MsY,u
                    tst       VG.PtrOn,u
                    beq       n@
                    ldd       VG.MsX,u
                    std       VG.PtrX,u
                    ldd       VG.MsY,u
                    std       VG.PtrY,u
n@                  rts

* Scan - A = a set-2 byte
Scan                tst       VG.KbSkip,u Pause's eight bytes (ps2.md 11.1)
                    beq       n@
                    dec       VG.KbSkip,u
                    rts
n@                  cmpa      #$E1
                    bne       e0@
                    lda       #7
                    sta       VG.KbSkip,u
                    rts
e0@                 cmpa      #$E0
                    bne       f0@
                    lda       #KF.E0
                    bra       set@
f0@                 cmpa      #$F0
                    bne       code@
                    lda       #KF.F0
set@                ora       VG.KbFlag,u
                    sta       VG.KbFlag,u
                    rts
code@               cmpa      #$80      acknowledgements and errors are not keys
                    lbhs       clr@
                    ldb       VG.KbFlag,u
                    bitb      #KF.F0
                    lbne      up@
* a make code
                    cmpa      #$12      the modifiers
                    beq       sh@
                    cmpa      #$59
                    beq       sh@
                    cmpa      #$14
                    beq       ct@
                    cmpa      #$11
                    beq       al@
                    cmpa      #$58
                    beq       cap@
                    bitb      #KF.E0
                    bne       ext@
                    leax      Map,pcr
                    bitb      #KF.Shift
                    beq       m@
                    leax      ShMap,pcr
m@                  lda       a,x
                    lbeq       clr@
                    bitb      #KF.Ctrl
                    beq       caps@
                    cmpa      #'@
                    blo       caps@
                    anda      #$1F      CTRL: the letters and @[\]^_ become $00-$1F
                    bra       put@
caps@               bitb      #KF.Caps
                    beq       put@
                    cmpa      #'a
                    blo       uc@
                    cmpa      #'z
                    bhi       put@
                    suba      #$20
                    bra       put@
uc@                 cmpa      #'A
                    blo       put@
                    cmpa      #'Z
                    bhi       put@
                    adda      #$20
put@                bsr       Clear
                    lbra      Char
ext@                leax      ExtMap,pcr E0 xx: arrows, keypad Enter and /, Delete
e1@                 tst       ,x
                    lbeq       clr@
                    cmpa      ,x++
                    bne       e1@
                    lda       -1,x
                    bra       put@
sh@                 lda       #KF.Shift
                    bra       mod@
ct@                 lda       #KF.Ctrl
                    bra       mod@
al@                 lda       #KF.Alt
mod@                ora       VG.KbFlag,u
                    sta       VG.KbFlag,u
                    lbra      clr@
cap@                lda       VG.KbFlag,u
                    eora      #KF.Caps
                    sta       VG.KbFlag,u
                    lbra      clr@
* a release: only the modifiers care
up@                 ldb       #^KF.Shift
                    cmpa      #$12
                    beq       rel@
                    cmpa      #$59
                    beq       rel@
                    ldb       #^KF.Ctrl
                    cmpa      #$14
                    beq       rel@
                    ldb       #^KF.Alt
                    cmpa      #$11
                    lbne       clr@
rel@                andb      VG.KbFlag,u
                    stb       VG.KbFlag,u
clr@                bsr       Clear
                    rts

* Clear - the prefixes are spent
Clear               pshs      a
                    lda       VG.KbFlag,u
                    anda      #^(KF.E0+KF.F0)
                    sta       VG.KbFlag,u
                    puls      a,pc

* Char - A = a character for the displayed window.  The window's own
* interrupt, quit and pause characters signal rather than buffer, as an
* SCF serial driver does.  U = VG.
Char                ldx       VG.CurDev,u
                    beq       x@
                    cmpa      V.PCHR,x
                    bne       i@
                    ldy       V.DEV2,x
                    beq       wake@
                    sta       V.PAUS,y
                    bra       wake@
i@                  ldb       #S$Intrpt
                    cmpa      V.INTR,x
                    beq       sig@
                    ldb       #S$Abort
                    cmpa      V.QUIT,x
                    bne       buf@
sig@                lda       V.LPRC,x
                    beq       x@
                    os9       F$Send
x@                  clrb
                    rts
buf@                leay      V.InBuf,x
                    ldb       V.EndPtr,x
                    leay      b,y       (B < 128: a positive offset)
                    incb
                    bpl       w@
                    clrb
w@                  cmpb      V.InPtr,x full: the key is lost
                    beq       x@
                    sta       ,y
                    stb       V.EndPtr,x
                    lda       V.SSigID,x a data-ready signal?
                    beq       wake@
                    ldb       V.SSigSg,x
                    clr       V.SSigID,x
                    os9       F$Send
                    clrb
                    rts
wake@               lda       V.WAKE,x
                    beq       x@
                    clr       V.WAKE,x
                    ldb       #S$Wake
                    os9       F$Send
                    clrb
                    rts

********************************************************************
* The ports.  ps2.md 7 and 11.2, ps2tst's, for either port: VG.KbPort is 0
* (the keyboard) or 1 (the mouse), and a port's IOCTRL and IOSTAT bits are
* the keyboard's shifted up by one (RST, DR) or two (CLK, DAT).

* Sh1, Sh2 - A = the keyboard's bit: A := this port's
Sh1                 tst       VG.KbPort,u
                    beq       x@
                    lsla
x@                  rts

Sh2                 tst       VG.KbPort,u
                    beq       x@
                    lsla
                    lsla
x@                  rts

* PutCtl - IOCTRL := A, shadowed (the register is write-only).  X := the base.
PutCtl              sta       VG.IOCtl,u
                    ldx       VG.KBase,u
                    sta       PR.IOCTRL,x
                    rts

* Phase - 11.2 step 0: RST held until CLK is idle, then released, and the
* data latch read empty
Phase               lda       #%00010000
                    bsr       Sh1
                    pshs      a
                    ora       VG.IOCtl,u
                    bsr       PutCtl
                    lda       #%00000100 CLK: 1 is the line low
                    bsr       Sh2
                    ldy       #0
p@                  bita      PR.IOSTAT,x
                    beq       r@
                    leay      -1,y
                    bne       p@
r@                  puls      a
                    coma
                    anda      VG.IOCtl,u
                    bsr       PutCtl
                    ldb       VG.KbPort,u
                    lda       b,x       KDATA or MDATA: the read clears DR
                    rts

* Get - A := the next byte on the port; carry set after ~0.5 s of nothing
Get                 ldx       VG.KBase,u
                    ldb       #%00000001
                    tst       VG.KbPort,u
                    beq       k@
                    lslb
k@                  ldy       #0
g@                  bitb      PR.IOSTAT,x
                    bne       have@
                    leay      -1,y
                    bne       g@
                    comb
                    rts
have@               ldb       VG.KbPort,u
                    lda       b,x
                    andcc     #^Carry
                    rts

* Send - A, by ps2.md 7.  Carry set on a timeout.
*
* The device holds CLK low for one 30-50 us half period a bit, and the bit
* must be on DATA before it lets CLK rise - some 80 E cycles.  So the ten
* IOCTRL values (eight data bits, parity, stop) are worked out before the
* frame, and the loop per bit is a poll and a store.
Send                pshs      a
                    ldb       #1        odd parity: 1 + the data bits, mod 2
                    ldx       #8
par@                lsra
                    adcb      #0
                    leax      -1,x
                    bne       par@
                    andb      #1
                    pshs      b         parity at 0,s, the byte at 1,s
                    lda       #%00000010 this port's bits: DATD ...
                    lbsr      Sh2
                    sta       VG.KbDat,u
                    lda       #%00000001 ... CLKD ...
                    lbsr      Sh2
                    sta       VG.KbClk,u
                    lda       #%00000100 ... IOSTAT's CLK ...
                    lbsr      Sh2
                    sta       VG.KbSClk,u
                    lda       #%00001000 ... and DAT
                    lbsr      Sh2
                    sta       VG.KbSDat,u
                    lda       #%00010000 1. hold the receive counter
                    lbsr      Sh1
                    ora       VG.IOCtl,u
                    sta       VG.IOCtl,u
                    leax      VG.KbBuf,u the ten values: DATD set for a 0 bit
                    lda       1,s
                    ldb       #8
v@                  lsra
                    pshs      a
                    lda       VG.IOCtl,u
                    bcs       one@
                    ora       VG.KbDat,u
                    bra       st@
one@                pshs      b
                    ldb       VG.KbDat,u
                    comb
                    pshs      b
                    anda      ,s+
                    puls      b
st@                 sta       ,x+
                    puls      a
                    decb
                    bne       v@
                    lda       VG.IOCtl,u parity
                    tst       ,s
                    bne       p1@
                    ora       VG.KbDat,u
                    bra       p2@
p1@                 ldb       VG.KbDat,u
                    comb
                    pshs      b
                    anda      ,s+
p2@                 sta       ,x+
                    ldb       VG.KbDat,u stop: released
                    comb
                    pshs      b
                    lda       VG.IOCtl,u
                    anda      ,s+
                    sta       ,x
                    leas      2,s
                    ldy       VG.KBase,u
                    lda       VG.IOCtl,u
                    sta       PR.IOCTRL,y
                    pshs      cc
                    orcc      #IRQMask  2. /IRQ only: /FIRQ stays live
                    ora       VG.KbClk,u 3. inhibit ...
                    sta       PR.IOCTRL,y
                    ldx       #60       ... >= 100 us
d@                  leax      -1,x
                    bne       d@
                    ora       VG.KbDat,u ... the start bit
                    sta       PR.IOCTRL,y
                    ldb       VG.KbClk,u ... and release CLK
                    comb
                    pshs      b
                    anda      ,s+
                    sta       PR.IOCTRL,y
                    leax      VG.KbBuf,u 4. each value: CLK low, store, CLK high
                    lda       #10
                    sta       VG.KbTmp,u
                    ldb       VG.KbSClk,u
b@                  pshs      x
                    ldx       #0
lo@                 bitb      PR.IOSTAT,y
                    bne       low@
                    leax      -1,x
                    bne       lo@
                    puls      x
                    bra       tmo@
low@                puls      x
                    lda       ,x+
                    sta       PR.IOCTRL,y
                    pshs      x
                    ldx       #0
hi@                 bitb      PR.IOSTAT,y
                    beq       rise@
                    leax      -1,x
                    bne       hi@
                    puls      x
                    bra       tmo@
rise@               puls      x
                    dec       VG.KbTmp,u
                    bne       b@
                    lda       -1,x      the stop value
                    sta       VG.IOCtl,u
                    ldb       VG.KbSDat,u 5. the ACK: DATA low
                    ldx       #0
ack@                bitb      PR.IOSTAT,y
                    bne       acked@
                    leax      -1,x
                    bne       ack@
                    bra       tmo@
acked@              lda       VG.KbSDat,u 6. RST off once both lines are idle
                    ora       VG.KbSClk,u
                    ldx       #0
idle@               bita      PR.IOSTAT,y
                    beq       rel@
                    leax      -1,x
                    bne       idle@
rel@                lda       #%00010000
                    lbsr      Sh1
                    coma
                    anda      VG.IOCtl,u
                    sta       VG.IOCtl,u
                    sta       PR.IOCTRL,y
                    puls      cc
                    andcc     #^Carry
                    rts
tmo@                lda       #%00010000
                    lbsr      Sh1
                    ora       VG.KbDat,u
                    coma
                    anda      VG.IOCtl,u
                    sta       VG.IOCtl,u
                    sta       PR.IOCTRL,y
                    puls      cc
                    comb
                    rts

* Cmd - A = a command for the port, B = the bytes it answers (FA first):
* sent, and the answer read.  Carry set if the device did not answer.
Cmd                 pshs      b
                    lbsr      Send
                    bcs       x@
r@                  lbsr      Get
                    bcs       x@
                    dec       ,s
                    bne       r@
x@                  puls      b,pc

********************************************************************
* Set 2 to CoCo 3 key values (Wildbits' keydrv_ps2 tables)
Map                 fcb       0,0,0,0,0,$B1,$B2,0,0,0,0,0,0,0,'`,0
                    fcb       0,0,0,0,0,'q,'1,0,0,0,'z,'s,'a,'w,'2,0
                    fcb       0,'c,'x,'d,'e,'4,'3,0,0,C$SPAC,'v,'f,'t,'r,'5,0
                    fcb       0,'n,'b,'h,'g,'y,'6,0,0,0,'m,'j,'u,'7,'8,0
                    fcb       0,C$COMA,'k,'i,'o,'0,'9,0,0,'.,'/,'l,';,'p,'-,0
                    fcb       0,0,'',0,'[,'=,0,0,0,0,C$CR,'],0,'\,0,0
                    fcb       0,0,0,0,0,0,$08,0,0,'1,0,'4,'7,0,0,0
                    fcb       '0,'.,'2,'5,'6,'8,$05,0,0,'+,'3,'-,'*,'9,$17,0

ShMap               fcb       0,0,0,0,0,$B3,$B4,0,0,0,0,0,0,0,'~,0
                    fcb       0,0,0,0,0,'Q,'!,0,0,0,'Z,'S,'A,'W,'@,0
                    fcb       0,'C,'X,'D,'E,'$,'#,0,0,C$SPAC,'V,'F,'T,'R,'%,0
                    fcb       0,'N,'B,'H,'G,'Y,'^,0,0,0,'M,'J,'U,'&,'*,0
                    fcb       0,'<,'K,'I,'O,'),'(,0,0,'>,'?,'L,':,'P,'_,0
                    fcb       0,0,'",0,'{,'+,0,0,0,0,C$CR,'},0,'|,0,0
                    fcb       0,0,0,0,0,0,$18,0,0,'1,0,'4,'7,0,0,0
                    fcb       '0,'.,'2,'5,'6,'8,$05,0,0,'+,'3,'-,'*,'9,$17,0

* E0-prefixed makes: code, value
ExtMap              fcb       $75,$0C   up
                    fcb       $72,$0A   down
                    fcb       $6B,$08   left
                    fcb       $74,$09   right
                    fcb       $5A,C$CR  keypad Enter
                    fcb       $4A,'/    keypad /
                    fcb       $71,$7F   Delete
                    fcb       0

                    emod
eom                 equ       *
                    end
