******************************************************
* F$Debug entry point
*
* Enter the debugger (or reboot)
*
* Input:  A = Function code
*

FDebug              equ       *         ; define assembler symbol FDebug
* Determine if this is a system process or super user
* Only they have permission to reboot
                    lda       R$A,u     ; load A from R$A,u
                    cmpa      #255      ; reboot request
                    bne       leave     ; nope
                    ldx       <D.Proc   ; load X from <D.Proc
                    ldd       P$User,x  ; get user ID
                    beq       REBOOT    ; branch if zero is set to REBOOT
                    comb                ; update processor state
                    ldb       #E$UnkSvc ; load B from #E$UnkSvc
leave               rts                 ; return to caller

* NOTE: HIGHLY MACHINE DEPENDENT CODE!
* THIS CODE IS SPECIFIC TO THE COCO 3!
                  IFNE    arm6309 ; begin conditional assembly for arm6309
* arm6309: a reboot is the power-on path again - the boot ROM's POST, then
* its handoff to page 1 and NitrOS-9 - without a /RESET, which software
* cannot assert.
*
* The boot monitor (arm6309 software/boot/boot.asm) runs correctly with the
* map already live: its first act writes all sixteen map entries, block 7
* pointing at ROM page 0, the page it runs from, and setting RUN again (it
* is one-way per reset) does nothing.  So the ROM needs only to be at $E000
* when it starts.  What it does NOT do is reset the cards, because at power-on
* /RESET already has - so every interrupt source it does not itself
* reprogram is turned off here, or the rebooted kernel would unmask a line
* nothing is ready to service:
*   the audio card   ACTRL (timer and master enable), AINTENA, ADMACON, AINTREQ
*   the PS/2 card    IOCTRL: IRQEN, and both ports' lines released
*   the UART         IER
*   the video card   CTRL: VBL's enable (boot.asm writes CTRL itself)
* Then a stub copied into block 0 - the one slot nothing here moves - maps ROM
* page 0 at slot 7, where this code is, and jumps through the reset vector.
REBOOT              orcc      #IntMasks ; masked until the kernel unmasks again
                    clr       >DAT.Task ; the system map
                    ldx       #Audio.Base
                    lda       #ArmRbAudN ; four register writes
                    leay      ArmRbAud,pcr
aud@                ldb       $0A,x     ; audio.md 9.2: ASTAT b6 clear before a write
                    bitb      #%01000000
                    bne       aud@
                    ldb       ,y+       ; register
                    pshs      a
                    lda       ,y+       ; value
                    sta       b,x
                    puls      a
                    deca
                    bne       aud@
                    clr       >PS2.Base+3 ; IOCTRL: IRQEN off, lines released
                    clr       >UART.Base+1 ; IER: no UART interrupt
vid@                lda       >Video.Base+V.VSTAT ; graphics.md 19 item 39: not
                    bmi       vid@      ; under a span
                    clr       >Video.Base+V.CTRL ; display and VBL off; boot.asm sets CTRL
                  IFNE    H6309
                    ldmd      #0        ; the boot ROM is 6809 code, in emulation mode
                  ENDC
                    leax      ArmRbStub,pcr
                    ldu       #$0000    ; block 0: slot 0 does not move
                    ldb       #ArmRbStubE-ArmRbStub
stub@               lda       ,x+
                    sta       ,u+
                    decb
                    bne       stub@
                    jmp       >$0000

* ACTRL, AINTENA, ADMACON, AINTREQ: every bit cleared (b7 = 0 clears)
ArmRbAud            fcb       $05,$00   ; ACTRL: timer off, master enable off
                    fcb       $03,$3F   ; AINTENA: every enable cleared
                    fcb       $02,$0F   ; ADMACON: every channel off
                    fcb       $04,$3F   ; AINTREQ: every request cleared
ArmRbAudE           equ       *
ArmRbAudN           equ       4

* Position independent: runs at $0000.
ArmRbStub           ldd       #ROM.Hi*256+$00 ; ROM page 0 ...
                    sta       >DAT.RegsHi+7
                    stb       >DAT.Regs+7 ; ... at slot 7
                    jmp       [$FFFE]   ; the reset vector: $E000, boot.asm
ArmRbStubE          equ       *
                  ELSE
REBOOT              orcc      #IntMasks ; turn off IRQ's
                    clrb                ; clear B
                    stb       >DAT.Regs ; map in block 0
                    stb       >$0071    ; cold reboot
                    lda       #$38      ; bottom of DECB block mapping
                    sta       >DAT.Regs ; map in block zero
                    stb       >$0071    ; and cold reboot here, too
                    ldu       #$0000    ; force code to go at offset $0000
                    leax      ReBootLoc,pc ; reboot code
                    ldy       #CodeSize ; load Y from #CodeSize
cit.loop            lda       ,x+       ; load A from ,x+
                    sta       ,u+       ; store A at ,u+
                    leay      -1,y      ; compute -1,y into Y
                    bne       cit.loop  ; branch if zero is clear to cit.loop
                    clr       >$FEED    ; cold reboot
                    clr       >$FFD8    ; go to low speed
                    jmp       >$0000    ; jump to the reset code

ReBootLoc
                    ldd       #$3808    ; block $38, 8 times
                    ldx       #DAT.Regs ; where to put it
Lp                  sta       8,x       ; put into map 1
                    sta       ,x+       ; and into map 0
                    inca                ; increment A
                    decb                ; count down
                    bne       Lp        ; branch if zero is clear to Lp

                    lda       #$4C      ; standard DECB mapping
                    sta       >$FF90    ; store A at >$FF90
                    clr       >DAT.Task ; go to map type 0
                    clr       >$FFDE    ; and to all-ROM mode
                    ldd       #$FFFF    ; load D from #$FFFF
*         clrd              executes as CLRA on a 6809
                    fdb       $104F     ; define word value(s) $104F
                    tstb                ; is it a 6809?
                    bne       Reset     ; yup, skip ahead
*         ldmd  #$00        go to 6809 mode!
                    fcb       $11,$3D,$00 ; define byte value(s) $11,$3D,$00
Reset               jmp       [$FFFE]   ; do a reset
CodeSize            equ       *-ReBootLoc ; define assembler symbol CodeSize
                  ENDC
