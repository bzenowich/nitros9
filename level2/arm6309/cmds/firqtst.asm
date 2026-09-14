********************************************************************
* firqtst - count /FIRQs, in system state and in user state
*
* Opens /FT0 (level2/arm6309/modules/firqtstdrv.asm), which starts the
* audio card's timer at 50 Hz on /FIRQ, and prints two lines:
*
*   FIRQs in 100 ticks: nnnnn
*     the count across F$Sleep 100.  At a 70 Hz tick that is 1.43 s, so a
*     working stub counts about 71.  Here the FIRQs arrive while the kernel
*     idles, in the system map.
*
*   FIRQs in user state: nnnnn, registers intact
*     the count across a busy loop of 4 x 65,536 passes, about 2 s of
*     machine, which is the case the stub's map handling is for: each FIRQ
*     enters in this process's map and must come back to it.  The loop steps
*     X, Y and U, holding A, B and DP, and Y and U by amounts that wrap back
*     to where they started, so "intact" means every register the stub saves
*     came out of the loop as it went in.  Otherwise the line says "CORRUPTED".
*
* Closing the path stops the timer (the driver's Term).
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Initial version.

                    nam       firqtst
                    ttl       count FIRQs in system and user state

                    ifp1
                    use       defsfile
                    endc

SS.FIRQCnt          equ       $EF

                    mod       eom,name,Prgrm+Objct,ReEnt+0,start,size

                    org       0
path                rmb       1
before              rmb       2
count               rmb       2
verdict             rmb       1
outer               rmb       1
buf                 rmb       64
                    rmb       200       stack
size                equ       .

name                fcs       /firqtst/
                    fcb       1

dev                 fcs       "/FT0"
msg1                fcc       "FIRQs in 100 ticks: "
msg1len             equ       *-msg1
msg2                fcc       "FIRQs in user state: "
msg2len             equ       *-msg2
intact              fcc       ", registers intact"
intactlen           equ       *-intact
broken              fcc       ", CORRUPTED"
brokenlen           equ       *-broken
pow                 fdb       10000,1000,100,10,1

start               leax      dev,pcr
                    lda       #READ.
                    os9       I$Open
                    lbcs      exit
                    sta       path,u

* ---- system state: across F$Sleep ---------------------------------------
                    lbsr      Count0    before := the count
                    ldx       #100
                    os9       F$Sleep
                    lbsr      Delta     count := the count - before
                    leay      buf,u
                    leax      msg1,pcr
                    ldb       #msg1len
                    lbsr      Copy
                    lbsr      Decimal
                    lbsr      Emit

* ---- user state: across a busy loop -------------------------------------
                    lbsr      Count0
                    pshs      u
                    lda       #4
                    pshs      a         the outer count, on the stack
                    ldy       #$1234    +4 x 262,144 wraps back to $1234
                    ldu       #$4321    -1 x 262,144 wraps back to $4321
                    lda       #$5A
                    tfr       a,dp      DP held at $5A
                    ldb       #$A5      A and B held
                    ldx       #0
loop@               leay      4,y
                    leau      -1,u
                    leax      1,x
                    bne       loop@
                    dec       ,s
                    bne       loop@
                    leas      1,s
                    clr       ,-s       the verdict: 0 = intact
                    cmpa      #$5A
                    bne       bad@
                    cmpb      #$A5
                    bne       bad@
                    tfr       dp,a
                    cmpa      #$5A
                    bne       bad@
                    cmpy      #$1234
                    bne       bad@
                    cmpu      #$4321
                    beq       good@
bad@                inc       ,s
good@               puls      a
                    puls      u
                    sta       verdict,u
                    clra
                    tfr       a,dp
                    lbsr      Delta
                    leay      buf,u
                    leax      msg2,pcr
                    ldb       #msg2len
                    bsr       Copy
                    bsr       Decimal
                    leax      intact,pcr
                    ldb       #intactlen
                    tst       verdict,u
                    beq       v@
                    leax      broken,pcr
                    ldb       #brokenlen
v@                  bsr       Copy
                    bsr       Emit

                    lda       path,u
                    os9       I$Close
                    clrb
exit                os9       F$Exit

* Count0: before := the driver's count.  Delta: count := it - before.
Count0              bsr       Get
                    stx       before,u
                    rts
Delta               bsr       Get
                    tfr       x,d
                    subd      before,u
                    std       count,u
                    rts
Get                 lda       path,u
                    ldb       #SS.FIRQCnt
                    os9       I$GetStt
                    bcs       fail@
                    rts
fail@               leas      2,s       out of Get's caller too
                    lbra      exit

* Copy: B bytes from X to Y.
Copy                lda       ,x+
                    sta       ,y+
                    decb
                    bne       Copy
                    rts

* Decimal: count,u as five digits at Y.
Decimal             leax      pow,pcr
                    ldb       #5
                    stb       outer,u
d@                  lda       #'0
                    pshs      a
s@                  ldd       count,u   subtract this power of ten until it borrows
                    subd      ,x
                    bcs       done@
                    std       count,u
                    inc       ,s
                    bra       s@
done@               puls      a
                    sta       ,y+
                    leax      2,x
                    dec       outer,u
                    bne       d@
                    rts

* Emit: buf up to Y, and a CR, to standard output.
Emit                lda       #C$CR
                    sta       ,y+
                    tfr       y,d
                    leax      buf,u
                    pshs      x
                    subd      ,s++
                    tfr       d,y
                    lda       #1
                    os9       I$WritLn
                    rts

                    emod
eom                 equ       *
                    end
