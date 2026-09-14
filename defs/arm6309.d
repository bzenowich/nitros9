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
*     A NitrOS-9 block number is 16 bits, as the DAT image already holds
*     it, and block b is physical page $200 + b: the map entry's low byte
*     is b's low byte and its high byte is RAM.Hi + b's high byte.  Every
*     kernel site that points a slot at a block writes both (the arm6309
*     conditionals in krn, fld, fldabx, fmove, fallram, krnp2).
*   - so RAM is contiguous from SIMM socket 0: blocks 0-$1FF are socket 0,
*     $200-$3FF socket 1.  The block map holds ArmBlkMax = 1024 blocks,
*     8 MB, because F$GBlkMp's callers (mfree, pmap, smap) pass a 1,024
*     byte buffer; the other 8 MB of a full bank would need a different
*     call.  The loader reads how much there is from the boot ROM's
*     memory descriptor (arm6309 software/boot/README.md) into D.BlkCnt.
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
* The system tick is the video card's vertical blank (machine.md 4):
* 25,175,000 / (800 x 449) = 70.086 Hz in VMODE 00 and 10, and
* 25,175,000 / (800 x 525) = 59.940 Hz in 01 and 11.  Neither is an
* integer, and a program can change VMODE, so the clock does not count
* TkPerSec ticks to the second.  Each tick adds its own length in 2^-20 s
* to a 24-bit accumulator, choosing the length from CTRL's VMODE0 as it
* acknowledges the tick (level2/modules/clock.asm):
*   Tk.P449 = 2^20 x 800 x 449 / 25,175,000 = 14,961.4 -> 14,961  (-2.5 s/day)
*   Tk.P525 = 2^20 x 800 x 525 / 25,175,000 = 17,493.4 -> 17,493  (-2.0 s/day)
* against a 50 ppm crystal's 4.3 s/day.  TkPerSec stays for what counts
* ticks rather than seconds (F$Sleep's callers, D.Tick), at the family the
* boot ROM leaves.
TkPerSec            SET       70
Tk.P449             EQU       14961
Tk.P525             EQU       17493
* The accumulator and the period live in os9.d's GIME video shadows, which
* nothing on this machine has: D.VIDMD-D.VIDRS and D.BORDR-D.VOFF2.
D.TkPer             EQU       D.VIDMD   2 bytes: this tick's length, 2^-20 s
D.TkAcc             EQU       D.BORDR   3 bytes: the second so far, 2^-20 s
* The video console's globals (defs/armvid.d's VG), or 0.  When set, the
* clock hands each VBL to the service at their offset 0 instead of
* acknowledging it itself: jsr [,x] with X = the globals, in the IRQ, and
* the service returns carry = VMODE0 of the CTRL it last wrote.  The kernel's
* idle loop calls jsr [2,x] with IRQs masked, for work too long for an IRQ
* (the mouse pointer); carry set if it did some.  It is
* os9.d's D.VOFF1-D.VOFF0, GIME shadows nothing here has.
D.VBLSt             EQU       D.VOFF1

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
DAT.BlMx            EQU       ArmBlkMax-1 maximum block number
DAT.BMSz            EQU       ArmBlkMax memory block map size
DAT.WrPr            EQU       0         no write protect
DAT.WrEn            EQU       0         no write enable
SysTask             EQU       0         system task number
RAM.Hi              EQU       $02       high byte of block 0: SIMM socket 0, from 4.0 MB
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

* The video console's status calls (arm6309 docs/nitros9-av-plan.md 5.3), on
* a window path; defs/armvid.d has the tables they take
SS.Excl             EQU       $D4       Set: Y = 1 claim the displayed screen, 0 release; X := the card's base
SS.Scroll           EQU       $D5       Set: X = HSCROLL, Y = VSCROLL, at the next VBL (exclusive)
SS.Batch            EQU       $D7       Set: X = a batch (BT.*), Y = its length: committed in one VBL
SS.FrmSig           EQU       $D8       Set: X = the signal, Y = every n frames (0: off)
SS.FrmWait          EQU       $D9       Set: sleep until a VBL is served; X := frames served
SS.Raster           EQU       $DA       Set: X = a list table (RT.*): the screen's list from the next frame
SS.RastOff          EQU       $DB       Set: no list
SS.TileLd           EQU       $DC       Set: X = 16,384 bytes, Y = the bank (TILEBASE value)
SS.MapWr            EQU       $DD       Set: X = a map rectangle (MW.*), Y = its length
SS.TBank            EQU       $DE       Set: X = TILEBASE, at the next VBL

********************************************************************
* /FIRQ (krn.asm's ArmFIRQ).  The audio card is the only source
* (machine.md 4).  An owner installs a service with interrupts masked:
*
*     orcc  #IntMasks
*     ldd   <D.FIRQ          save the previous service ...
*     std   PrevSvc,u
*     ldd   <D.FIRQSt        ... and its static pointer
*     std   PrevSt,u
*     stu   <D.FIRQSt
*     leax  Service,pcr
*     stx   <D.FIRQ
*     andcc #^IntMasks
*
* and puts both back in Term.  The service is called with jsr:
*   entry  U = D.FIRQSt, DP = 0, the system map, IRQ and FIRQ masked,
*          S = the kernel's FIRQ stack (ArmFIRQStkSz bytes, shared with
*          any system call the service makes)
*   exit   rts; may destroy D, X, Y, U and DP.  It must acknowledge its
*          source: /FIRQ is a level, and it comes straight back.
* An unowned FIRQ reaches D.Crash, as on every other Level 2 port.
*
* D.FIRQSt is the two bytes os9.d names D.FRQER and D.TIMMS: the CoCo 3
* GIME's FIRQ-enable and timer shadows, which nothing on this machine has.
D.FIRQSt            EQU       D.FRQER
ArmFIRQStkSz        EQU       192

********************************************************************
* RAM beyond 2 MB (docs/nitros9-av-plan.md X2)
ArmBlkMax           EQU       1024      blocks the block map holds: 8 MB
ArmBlkMap           EQU       $E000     the block map, in KrnBlk below Bt.Start
* D.BlkCnt: the loader's count of RAM blocks contiguous from socket 0,
* capped at ArmBlkMax.  os9.d's D.RESV1-D.RESV2, GIME shadows no one here has.
D.BlkCnt            EQU       D.RESV1

* No shift key on a serial console
SHIFTBIT            EQU       0

                  ENDC
