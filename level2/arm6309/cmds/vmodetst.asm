********************************************************************
* vmodetst - set the video card's VMODE from the shell: a test of the clock
*
*   vmodetst 0|1|2|3
*
* A stand-in for the video driver that does not exist yet (plan phase P1).
* It writes CTRL's VMODE bits directly - the I/O page is in every map - so
* that the clock's per-tick period (defs/arm6309.d) can be checked in both
* timing families.  The rest of CTRL is kept from its read-back.
*
* graphics.md 13's rules, kept: nothing is written under SPANBUSY.  The write
* lands just after VBLANK falls, which the card no longer needs: it takes a
* family change where the frame ends (graphics.md 6.2).  ⚠ So the frame this
* write lands in is still the old family's, and the clock sizes its tick
* from the new VMODE0: 2.3 ms of the clock, once.  A user process cannot
* mask interrupts, so the window is found by polling, and a VBL service that
* runs in between only acknowledges.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Initial version.

                    nam       vmodetst
                    ttl       set VMODE: a clock test

                    ifp1
                    use       defsfile
                    endc

                    mod       eom,name,Prgrm+Objct,ReEnt+0,start,size

                    org       0
                    rmb       200       stack
size                equ       .

name                fcs       /vmodetst/
                    fcb       1

start               lda       ,x        the argument's first character
                    suba      #'0
                    cmpa      #3
                    bhi       bad@
                    pshs      a
                    ldx       #Video.Base
h@                  lda       V.VSTAT,x wait for VBLANK (b6) ...
                    bita      #%01000000
                    beq       h@
l@                  lda       V.VSTAT,x ... and for it to fall
                    bita      #%01000000
                    bne       l@
b@                  tst       V.VSTAT,x not under a span
                    bmi       b@
                    lda       V.CTRL,x
                    anda      #%11111100
                    ora       ,s+
                    sta       V.CTRL,x
                    clrb
                    os9       F$Exit
bad@                ldb       #E$IllArg
                    os9       F$Exit

                    emod
eom                 equ       *
                    end
