********************************************************************
* romdiskdesc - descriptor for the arm6309 ROM disk
*
* Assemble with -DDD=1 for /DD, otherwise /R0.  The geometry is only
* what format and dcheck read; rbromdisk sizes the disk from the ROM.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Initial version.

                    nam       romdiskdesc
                    ttl       ROM disk descriptor for arm6309

                    ifp1
                    use       defsfile
                    endc

tylg                set       Devic+Objct
atrv                set       ReEnt+rev
rev                 set       $00

                    mod       eom,name,tylg,atrv,mgrnam,drvnam

                    fcb       DIR.+SHARE.+PREAD.+PEXEC.+READ.+EXEC.
                    fcb       HW.Page   extended controller address
                    fdb       $0000     no controller: the ROM is reached through the map
                    fcb       initsize-*-1 initialization table size
                    fcb       DT.RBF    device type
                    fcb       0         drive number
                    fcb       $00       step rate
                    fcb       $80       drive type: hard disk
                    fcb       $01       density
                    fdb       ROMDsk.Sz/32 cylinders (one per ROM page)
                    fcb       $01       sides
                    fcb       $01       no write verify
                    fdb       32        sectors per track
                    fdb       32        sectors on track 0
                    fcb       $01       interleave
                    fcb       8         segment allocation size
initsize            equ       *

                  IFNE    DD
name                fcs       /DD/
                  ELSE
name                fcs       /R0/
                  ENDC
mgrnam              fcs       /RBF/
drvnam              fcs       /rbromdisk/

                    emod
eom                 equ       *
                    end
