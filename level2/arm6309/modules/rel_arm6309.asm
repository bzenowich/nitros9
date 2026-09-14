********************************************************************
* rel_arm6309 - ROM loader for NitrOS-9 Level 2 on arm6309
*
* Raw binary, not an OS-9 module: ROM pages 1 and 2 of the arm6309 boot
* ROM.  The boot monitor (arm6309 software/boot/boot.asm) sees "6309" at
* the start of page 1 and jumps to $8004 with pages 1 and 2 in blocks 4
* and 5, ROM page 0 in block 7, IRQ and FIRQ masked, and the display on.
*
*   1. set every map entry's high byte to RAM (SIMM socket 0), and map
*      RAM blocks 0-3 at slots 0-3 and KrnBlk at slot 6
*   2. clear the direct page (krn clears $0100-$1FFF itself)
*   3. set up the 16550 at 115200 8N1 for D.BtBug
*   4. copy OS9Kernel (boot module padded to 1K, then krn) from ROM to
*      Bt.Start, through slot 6
*   5. copy the D.BtBug/D.Crash routines and the final trampoline into
*      the unused tail of the boot module's 1K pad ($EB80-$EBFF)
*   6. map KrnBlk at slot 7 and jump to the trampoline, which maps RAM
*      blocks 4-6 over the ROM this code was running from and enters krn
*
* Everything copied to $EB80 is position independent (absolute I/O
* addresses and relative branches only), because it is assembled here
* and runs there.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Initial version.

                    nam       rel_arm6309
                    ttl       ROM loader for arm6309

                  IFP1
                    use       defsfile
                    use       16550.d
                  ENDC

Stub.Base           equ       $EB80     BtBug, Crash and the trampoline, in KrnBlk
Kern.Load           equ       $C000+(Bt.Start-$E000) Bt.Start as seen through slot 6

                    org       $8000
                    fcc       "6309"    the boot monitor's handoff signature

start               orcc      #IntMasks
                    clra
                    tfr       a,dp

* 1. the map.  Task 0 slots 0-3 and 6 go to RAM now; 4, 5 and 7 are still
* ROM (this code and the vectors) until the trampoline.  Task 1 gets a
* harmless all-RAM image with KrnBlk at slot 7; krn rewrites it.
                    ldx       #DAT.Regs
                    ldu       #DAT.RegsHi
                    ldb       #RAM.Hi
map@                cmpa      #4
                    beq       skip@
                    cmpa      #5
                    beq       skip@
                    cmpa      #7
                    beq       skip@
                    stb       a,u       high byte: RAM
                    sta       a,x       low byte: block = slot, for now
skip@               inca
                    cmpa      #16
                    blo       map@
                    lda       #KrnBlk
                    sta       DAT.Regs+6 slot 6: the kernel's block, to fill it
                    sta       DAT.Regs+15 task 1 slot 7: the kernel's block
                    clr       DAT.Task  task 0
                    lds       #$0800    krn sets its own; this is for us

* 2. the direct page
                    ldx       #$0000
                    clra
dp@                 sta       ,x+
                    cmpx      #$0100
                    blo       dp@

* 3. the console UART, polled, no interrupts (sc16550 takes it over)
                    ldx       #UART.Base
                    clr       UART_IER,x
                    lda       #LCR_DLB
                    sta       UART_LCR,x
                    lda       #7372800/16/115200 divisor: 4 at 7.3728 MHz
                    sta       UART_DLL,x
                    clr       UART_DLH,x
                    lda       #$03      8N1, divisor latch off
                    sta       UART_LCR,x
                    lda       #FCR_FIFOE+FCR_RXR+FCR_TXR
                    sta       UART_FCR,x
                    lda       #$03      DTR, RTS
                    sta       UART_MCR,x

* 4. OS9Kernel into KrnBlk at Bt.Start
                    leax      Kernel,pcr
                    ldu       #Kern.Load
                    ldy       #KernEnd-Kernel
kern@               lda       ,x+
                    sta       ,u+
                    leay      -1,y
                    bne       kern@

* 5. the stubs, through slot 6 again
                    leax      Stubs,pcr
                    ldu       #$C000+(Stub.Base-$E000)
                    ldb       #StubsEnd-Stubs
stub@               lda       ,x+
                    sta       ,u+
                    decb
                    bne       stub@
                    lda       #$7E      JMP extended
                    sta       <D.BtBug
                    sta       <D.Crash
                    ldd       #Stub.Base+(BtBug-Stubs)
                    std       <D.BtBug+1
                    ldd       #Stub.Base+(Crash-Stubs)
                    std       <D.Crash+1

* 6. KrnBlk at slot 7 - where the stubs are - and leave the ROM
                    lda       #KrnBlk
                    ldb       #RAM.Hi
                    stb       DAT.RegsHi+7
                    sta       DAT.Regs+7
                    lda       #'R       debug: the loader ran
                    jsr       <D.BtBug
                    jmp       Stub.Base+(Tramp-Stubs)

*------------------------------------------------------------
* Copied to Stub.Base.  Position independent.
Stubs

* D.BtBug: A to the UART, polled.  Preserves everything, CC included
* (I.VBlock's name printer tests N after the call).
BtBug               pshs      cc,a,b
                    anda      #$7F      the last character of an OS-9 name has bit 7 set
b@                  ldb       UART.Base+UART_LSR
                    bitb      #LSR_XMIT_EMPTY
                    beq       b@
                    sta       UART.Base+UART_TRHB
                    puls      cc,a,b,pc

* D.Crash: "!" and the error code in B, then stop.
Crash               orcc      #IntMasks
                    pshs      b
                    lda       #'!
                    bsr       BtBug
                    puls      a
                    pshs      a
                    lsra
                    lsra
                    lsra
                    lsra
                    bsr       hex@
                    puls      a
                    bsr       hex@
c@                  bra       c@
hex@                anda      #$0F
                    adda      #'0
                    cmpa      #'9
                    bls       h@
                    adda      #'A-'9-1
h@                  bra       BtBug

* The last thing in ROM: map RAM blocks 4-6 over slots 4-6 and enter krn.
Tramp               ldd       #$0405
                    sta       DAT.Regs+4
                    stb       DAT.Regs+5
                    lda       #6
                    sta       DAT.Regs+6
                    ldb       #RAM.Hi
                    stb       DAT.RegsHi+4
                    stb       DAT.RegsHi+5
                    ldx       #Bt.Start+$400 krn
                    ldd       M$Exec,x
                    jmp       d,x
StubsEnd

                  IFGT    StubsEnd-Stubs-128
                    error     the stubs overrun $EB80-$EBFF
                  ENDC

*------------------------------------------------------------
Kernel              includebin os9kernel
KernEnd

                  IFGT    KernEnd-$C000
                    error     rel_arm6309 overruns ROM pages 1 and 2
                  ENDC
                  IFNE    KernEnd-Kernel-(Bt.Size)
                    error     os9kernel is not Bt.Start to $FF00
                  ENDC

                    end
