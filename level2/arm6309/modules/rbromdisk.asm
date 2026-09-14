********************************************************************
* rbromdisk - read-only RBF driver for the arm6309 boot ROM's disk
*
* The ROM disk is an RBF image in the boot ROM from page ROMDsk.Pg on
* (defs/arm6309.d): LSN n is ROM page ROMDsk.Pg + n/32, offset
* (n mod 32) * 256.  A sector is copied to PD.BUF through map slot 0
* with interrupts masked, as Rammer does with its blocks: slot 0 holds
* only system globals, which nothing touches while the copy runs, and
* PD.BUF is system memory that is never in block 0.  The copy loop uses
* no stack, because the system stack may be in block 0 too.
*
* Writes return E$WP.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Initial version.

                    nam       rbromdisk
                    ttl       ROM disk driver for arm6309

                    ifp1
                    use       defsfile
                    endc

tylg                set       Drivr+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       1

                    mod       eom,name,tylg,atrv,start,size

                    rmb       DRVBEG+DRVMEM one drive
size                equ       .

                    fcb       DIR.+SHARE.+PREAD.+PEXEC.+READ.+EXEC.

name                fcs       /rbromdisk/
                    fcb       edition

start               lbra      Init
                    lbra      Read
                    lbra      Write
                    lbra      GetStat
                    lbra      SetStat
                    lbra      Term

* Init: one drive, sized from the ROM.
* Entry: Y = device descriptor, U = device memory
Init                lda       #1
                    sta       V.NDRV,u
                    leax      DRVBEG,u
                    ldd       #ROMDsk.Sz
                    std       DD.TOT+1,x
GetStat
SetStat
Term                clrb
                    rts

Write               comb
                    ldb       #E$WP
                    rts

* Read
* Entry: B:X = LSN, Y = path descriptor, U = device memory
Read                tstb                LSNs past 65535 are past the ROM
                    bne       bad@
                    cmpx      #ROMDsk.Sz
                    bhs       bad@
                    pshs      x,y,u
                    tfr       x,d       D = LSN
                    lsra                D >>= 5: the page within the disk
                    rorb
                    lsra
                    rorb
                    lsra
                    rorb
                    lsra
                    rorb
                    lsra
                    rorb
                    addb      #ROMDsk.Pg
                    pshs      b         [page] [LSN hi] [LSN lo]
                    ldb       2,s       (LSN mod 32) * 256 is the offset
                    andb      #31
                    tfr       b,a
                    clrb
                    tfr       d,x       X = the sector, through slot 0
                    puls      b         B = ROM page
                    ldy       PD.BUF,y  Y = RBF's buffer
                    pshs      cc
                    orcc      #IntMasks
                    stb       DAT.Regs  slot 0 = the ROM page ...
                    lda       #ROM.Hi
                    sta       DAT.RegsHi
                    clrb                ... and no stack until it is block 0 again
cp@                 lda       ,x+
                    sta       ,y+
                    decb
                    bne       cp@
                    stb       DAT.Regs  B = 0: block 0
                    lda       #RAM.Hi
                    sta       DAT.RegsHi
                    puls      cc
                    puls      x,y,u
                    leax      ,x        LSN 0?
                    bne       ok@
                    ldx       PD.BUF,y  keep its DD.* in the drive table
                    leay      DRVBEG,u
                    ldb       #DD.SIZ
dd@                 lda       ,x+
                    sta       ,y+
                    decb
                    bne       dd@
ok@                 clrb
                    rts
bad@                comb
                    ldb       #E$Sect
                    rts

                    emod
eom                 equ       *
                    end
