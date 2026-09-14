                  IFNE    ARM6309.D-1

ARM6309.D           SET       1

********************************************************************
* arm6309.d - arm6309 machine hardware definitions
*
* A 6809E/6309 machine on a backplane: a motherboard with a 32 MB
* map, a 640-wide 8bpp video card, a Paula-style audio card, a
* TL16C550C serial port and a PS/2 port.  The machine's own documents
* are the authority: github arm6309 docs/machine.md (the map, the I/O
* page, interrupts), video/docs/graphics.md, audio/docs/audio.md.
*
* Memory map (machine.md 2, 3):
*   logical  $0000-$FEFF   RAM, 8 x 8K blocks through the map
*   logical  $FF00-$FFFF   the I/O page, decoded ahead of the map
*   logical  $FFC0-$FFFF   the boot ROM's vector page, served always
*
* The map (machine.md 5 item 3, hardware/ram.md 4.3) is GIME-shaped:
*   $FFA0-$FFAF  low byte of each entry  = physical A20..A13
*   $FF90-$FF9F  high byte of each entry = physical A24..A21
*   $FFB0        TASK (bit 0): which half of the 16 entries is live
* Entry index = {TASK, block}: $FFA0-$FFA7 task 0, $FFA8-$FFAF task 1,
* and task 0 can write task 1's half without switching to it - the
* GIME's own arrangement, so the CoCo 3 kernel's two-set model holds.
*
* What is NOT a GIME:
*   - there is no constant RAM page at $FE00-$FEFF.  Slot 7 of every
*     task's DAT image is KrnBlk, as on the Pico-Thing, so the kernel's
*     vector stubs and SWI stack are visible in every map.
*   - $FF90-$FF9F is the map's high byte, not INIT0/IRQ/timer/video.
*     NitrOS-9 block numbers are the LOW byte only; the loader sets
*     every high byte to RAM.Hi once, so blocks 0-$FF are the first
*     2 MB of the first SIMM socket (physical 4.0-6.0 MB).
*   - $FFB0-$FFBF is TASK (even) and RUN (odd), not the palette.
*   - the vectors at $FFF2-$FFFD point at $FEEE-$FEFD, the CoCo 3
*     addresses; in NitrOS-9 that is the kernel's BRA stubs in KrnBlk.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Initial version: Level 2, 6809, serial console.

arm6309             SET       1         conditional assembly symbol

********************************************************************
* The system tick is the video card's vertical blank (machine.md 4).
* 70.086 Hz in VMODE 00 and 10, 59.940 Hz in 01 and 11; the boot ROM
* leaves VMODE 00.  NOTE: TkPerSec is an assembly-time constant in the
* Level 2 clock, so a VMODE family change today makes the clock run
* 14 % slow.  docs/nitros9-av-plan.md X4.
TkPerSec            SET       70

HW.Page             SET       $FF       device descriptor hardware page
IO.Base             EQU       $FF00     the I/O page

********************************************************************
* Dynamic Address Translator
DAT.BlCt            EQU       8         blocks per address space
DAT.BlSz            EQU       (256/DAT.BlCt)*256 block size
DAT.ImSz            EQU       DAT.BlCt*2 DAT image size
DAT.Addr            EQU       -(DAT.BlSz/256) DAT MSB address bits
DAT.Task            EQU       $FFB0     TASK register (bit 0)
DAT.TkCt            EQU       32        number of DAT tasks
DAT.Regs            EQU       $FFA0     map entry low bytes
DAT.RegsHi          EQU       $FF90     map entry high bytes
DAT.Free            EQU       $333E     free block marker
DAT.BlMx            EQU       $FF       maximum block number
DAT.BMSz            EQU       $100      memory block map size
DAT.WrPr            EQU       0         no write protect
DAT.WrEn            EQU       0         no write enable
SysTask             EQU       0         system task number
RAM.Hi              EQU       $02       high byte: SIMM socket 0, 4.0-6.0 MB
ROM.Hi              EQU       $01       high byte: the boot ROM, 2.0-3.0 MB
KrnBlk              SET       $3F       RAM block holding the kernel

********************************************************************
* The boot ROM (machine.md 7.2).  ROM page 0 is the monitor and the
* vector page.  When page 1 starts "6309" the monitor jumps to $8004
* with pages 1 and 2 in blocks 4 and 5; that is rel_arm6309.  The ROM
* disk (an RBF image) starts at ROMDsk.Pg.
ROM.Pages           EQU       128       1 MB in 8K pages
ROMDsk.Pg           EQU       3         first ROM page of the ROM disk
ROMDsk.Sz           EQU       (ROM.Pages-ROMDsk.Pg)*32 sectors in the ROM disk

********************************************************************
* Level 2 boot layout: the boot module padded to 1K at Bt.Start, then
* krn at $EC00, padded so its vector stubs land at $FEEE.
Bt.Start            EQU       $E800
Bt.Size             EQU       $1700     Bt.Start to $FF00

********************************************************************
* I/O page (machine.md 3)
PS2.Base            EQU       IO.Base+$30 PS/2 (io/ps2/docs/ps2.md 8)
UART.Base           EQU       IO.Base+$38 TL16C550C (io/serial/docs/serial.md 7.1)
Audio.Base          EQU       IO.Base+$40 audio card (audio/docs/audio.md 9.2)
Video.Base          EQU       IO.Base+$60 video card (video/docs/graphics.md 13)

* Video card registers used by the system (graphics.md 13)
V.CTRL              EQU       $00       b7 display, b6 VBL IRQ enable, b5 CELL, b4-3 WMODE, b1-0 VMODE
V.VSTAT             EQU       $13       b7 SPANBUSY, b6 VBLANK, b5 HBLANK, b4 LRUN, b0 VBL pending; any write acknowledges
VSTAT.Busy          EQU       %10000000
VSTAT.LRun          EQU       %00010000
VSTAT.VBL           EQU       %00000001

* No shift key on a serial console
SHIFTBIT            EQU       0

                  ENDC
