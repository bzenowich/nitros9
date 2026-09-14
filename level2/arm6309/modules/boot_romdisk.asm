********************************************************************
* boot_romdisk - Boot module for arm6309: OS9Boot from the ROM disk
*
* Provides HWInit, HWTerm and HWRead for boot_common.asm.  The ROM disk
* is an RBF image in the boot ROM from page ROMDsk.Pg on: LSN n is ROM
* page ROMDsk.Pg + n/32, offset (n mod 32) * 256.
*
* A ROM page is reached by pointing a map slot at it: high byte ROM.Hi,
* low byte the page.  F$Boot runs on the system stack in block 0 with
* LSN0's buffer there too, and F$BtMem hands out the bootfile's memory
* from the top of the system map down, so slot 1 ($2000-$3FFF) is clear
* of both unless the bootfile passes ~40 K - which HWRead checks.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Initial version.

                    nam       Boot
                    ttl       ROM disk boot module for arm6309

                  IFP1
                    use       defsfile
                  ENDC

tylg                set       Systm+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       1

                    mod       eom,name,tylg,atrv,start,size

* on-stack static storage (boot_common's)
                    org       0
seglist             rmb       2         pointer to segment list
blockloc            rmb       2         pointer to requested memory
blockimg            rmb       2         duplicate of above
bootloc             rmb       3         sector pointer
bootsize            rmb       2         size in bytes
LSN0Ptr             rmb       2         LSN0 pointer
size                equ       .

name                fcs       /Boot/
                    fcb       edition

LSN24BIT            equ       1
FLOPPY              equ       0

                    use       boot_common.asm

Slot                equ       1         the borrowed map slot
Window              equ       Slot*DAT.BlSz

HWInit
HWTerm              clrb
                    rts

*------------------------------------------------------------
* HWRead - one 256-byte sector from the ROM disk
*
* Entry: B:X = LSN, blockloc,u = the 256-byte buffer
* Exit:  X = the buffer, carry clear; or carry set, B = error
HWRead              tstb                LSNs past 65535 are past the ROM
                    bne       bad@
                    cmpx      #ROMDsk.Sz
                    bhs       bad@
                    ldy       blockloc,u
                    cmpy      #Window+DAT.BlSz the buffer must not be in the window
                    bhs       ok@
                    cmpy      #Window-256
                    bhi       bad@
ok@                 tfr       x,d       D = LSN
                    pshs      b         (n mod 32) * 256 is the offset's high byte
                    andb      #31
                    stb       ,-s
                    ldb       1,s
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
                    lda       ,s+       A = offset high byte, B = ROM page
                    leas      1,s
                    adda      #Window/256
                    pshs      cc
                    orcc      #IntMasks
                    stb       DAT.Regs+Slot
                    ldb       #ROM.Hi
                    stb       DAT.RegsHi+Slot
                    clrb
                    tfr       d,x       X = the sector in the window
                    clrb
cp@                 lda       ,x+
                    sta       ,y+
                    decb
                    bne       cp@
                    ldb       #RAM.Hi   put slot 1 back as the system DAT image has it
                    stb       DAT.RegsHi+Slot
                    ldx       <D.SysDAT
                    ldb       Slot*2+1,x
                    stb       DAT.Regs+Slot
                    puls      cc
                    ldx       blockloc,u
                    clrb
                    rts
bad@                comb
                    ldb       #E$Sect
                    rts

Address             fdb       0         no hardware address

                    emod
eom                 equ       *
                    end
