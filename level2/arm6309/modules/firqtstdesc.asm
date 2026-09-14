********************************************************************
* firqtstdesc - /FT0, the FIRQ test driver on the audio card
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Initial version.

                    nam       FT0
                    ttl       FIRQ test descriptor for arm6309

                    ifp1
                    use       defsfile
                    endc

                    mod       eom,name,Devic+Objct,ReEnt+0,mgrnam,drvnam

                    fcb       UPDAT.
                    fcb       HW.Page
                    fdb       Audio.Base
                    fcb       initsize-*-1
                    fcb       DT.SCF
initsize            equ       *

name                fcs       /FT0/
mgrnam              fcs       /SCF/
drvnam              fcs       /FIRQDrv/

                    emod
eom                 equ       *
                    end
