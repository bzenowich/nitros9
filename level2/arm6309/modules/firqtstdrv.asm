********************************************************************
* firqtstdrv - a /FIRQ test driver for arm6309 (module FIRQDrv)
*
* Runs the audio card's tempo timer (audio.md 8.2) at 50 Hz on /FIRQ and
* counts the interrupts through krn's FIRQ stub (defs/arm6309.d).  It is the
* check for that stub, not an audio driver: it owns nothing but the timer.
*
*   Init     stop the timer, install the FIRQ service, load TIMER, enable
*   service  acknowledge AINTREQ b4, count
*   GetStat  SS.FIRQCnt: X = the count
*   Term     stop the timer, put the previous service back
*
* audio.md 9.2's rule is kept on every write, the service's included: poll
* ASTAT b6 first, because a write made while the host port is busy is lost.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Initial version.

                    nam       firqtst
                    ttl       FIRQ test driver for arm6309

                    ifp1
                    use       defsfile
                    endc

SS.FIRQCnt          equ       $EF       GetStat: X = FIRQs counted

* audio.md 9.2
AINTENA             equ       $03
AINTREQ             equ       $04
ACTRL               equ       $05
ASTAT               equ       $0A
TIMER1              equ       $0B
TIMER0              equ       $0C
Tempo50             equ       14187     1773447/125: 50.002 Hz

tylg                set       Drivr+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       1

                    mod       eom,name,tylg,atrv,start,size

                    org       V.SCF
Count               rmb       2
PrevSvc             rmb       2
PrevSt              rmb       2
size                equ       .

                    fcb       UPDAT.

name                fcs       /FIRQDrv/
                    fcb       edition

start               lbra      Init
                    lbra      Read
                    lbra      Write
                    lbra      GetStat
                    lbra      SetStat
                    lbra      Term

* Wr: register B := A, after ASTAT b6 clears.  X = the card.
Wr                  pshs      a
b@                  lda       ASTAT,x
                    bita      #%01000000
                    bne       b@
                    puls      a
                    sta       b,x
                    rts

* StopTimer: ACTRL b6 off, the timer's enable and request cleared.
StopTimer           clra
                    ldb       #ACTRL
                    bsr       Wr
                    lda       #%00010000 b7=0: clear AINTENA b4
                    ldb       #AINTENA
                    bsr       Wr
                    ldb       #AINTREQ  b7=0: clear AINTREQ b4
                    bra       Wr

* Init.  Y = descriptor, U = static.
Init                ldx       V.PORT,u
                    bsr       StopTimer
                    pshs      cc
                    orcc      #IntMasks
                    ldd       <D.FIRQ
                    std       PrevSvc,u
                    ldd       <D.FIRQSt
                    std       PrevSt,u
                    stu       <D.FIRQSt
                    leax      Service,pcr
                    stx       <D.FIRQ
                    puls      cc
                    ldx       V.PORT,u
                    lda       #Tempo50/256 TIMER is committed on its low byte
                    ldb       #TIMER1
                    bsr       Wr
                    lda       #Tempo50%256
                    ldb       #TIMER0
                    bsr       Wr
                    lda       #%10010000 b7=1: set AINTENA b4
                    ldb       #AINTENA
                    bsr       Wr
                    lda       #%01000000 ACTRL b6: the timer runs
                    ldb       #ACTRL
                    bsr       Wr
Read
Write               clrb
                    rts

* The FIRQ service: U = static (defs/arm6309.d's contract).
Service             ldx       V.PORT,u
                    lda       #%00010000 b7=0: clear AINTREQ b4, the level
                    ldb       #AINTREQ
                    bsr       Wr
                    ldd       Count,u
                    addd      #1
                    std       Count,u
                    rts

GetStat             cmpa      #SS.FIRQCnt
                    bne       SetStat
                    ldd       Count,u
                    ldx       PD.RGS,y
                    std       R$X,x
                    clrb
                    rts
SetStat             comb
                    ldb       #E$UnkSvc
                    rts

Term                ldx       V.PORT,u
                    lbsr      StopTimer
                    pshs      cc
                    orcc      #IntMasks
                    ldd       PrevSvc,u
                    std       <D.FIRQ
                    ldd       PrevSt,u
                    std       <D.FIRQSt
                    puls      cc
                    clrb
                    rts

                    emod
eom                 equ       *
                    end
