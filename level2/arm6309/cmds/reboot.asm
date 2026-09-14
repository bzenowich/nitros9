********************************************************************
* reboot - restart the machine through its boot ROM
*
* F$Debug with A = 255, which only the superuser may call.  On arm6309 the
* kernel quiets the cards and re-enters the boot ROM at its reset vector, so
* the machine runs its power-on self-test and boots NitrOS-9 again
* (level2/modules/kernel/fdebug.asm).  It does not return.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Initial version.

                    nam       reboot
                    ttl       restart through the boot ROM

                    ifp1
                    use       defsfile
                    endc

                    mod       eom,name,Prgrm+Objct,ReEnt+0,start,size

                    org       0
                    rmb       100       stack
size                equ       .

name                fcs       /reboot/
                    fcb       1

start               lda       #255      the reboot request
                    os9       F$Debug
                    os9       F$Exit    only if it was refused: B is the error

                    emod
eom                 equ       *
                    end
