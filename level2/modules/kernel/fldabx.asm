**************************************************
* System Call: F$LDABX
*
* Function: Load A from 0,X in task B
*
* Input:  B = Task number
*         X = Data pointer
*
* Output: A = Data byte at 0,x in task's address space
*
* Error:  CC = C bit set; B = error code
*
FLDABX              ldb       R$B,u     ; get task # to get byte from
                    ldx       R$X,u     ; get offset into task's DAT image to get byte from

* Load a byte from another task
* Entry: B=Task #
*        X=Pointer to data
* Exit : B=Byte from other task
FLdabxTarget        pshs      cc,a,x,u  ; save cc,a,x,u on the stack
                    bsr       FMoveTaskImageTable ; calculate offset into DAT image (fmove.asm)
                    ldd       a,u       ; [NAC HACK 2017Jan25] why ldd when a is never used??
                    orcc      #IntMasks ; set condition-code bits using #IntMasks
                  IFNE    mc09    ; begin conditional assembly for mc09
                    lda       <D.TINIT  ; current MMU mask - selects block 0
                    sta       >MMUADR   ; select block 0

                    stb       >MMUDAT   ; map selected block into $0000-$1FFF
                    ldb       ,x        ; load B from ,x
                    clr       >MMUDAT   ; restore mapping at $0000-$1FFF
                  ELSE
                  IFNE    picothing ; begin conditional assembly for picothing
* Pico-Thing: page $FF (KrnBlk) is the DAT "unavailable" sentinel and
* cannot be mapped into slot 0 (the access would fault NMI).  The kernel
* block is readable in place in the fixed $E000-$FFFF window.
                    cmpb      #KrnBlk   ; is the source the kernel block?
                    bne       lmap@     ; no, map it normally
                    ldb       >((DAT.BlCt-1)*DAT.BlSz),x ; read in place from the fixed window
                    bra       ldone@    ; skip the slot mapping
lmap@               equ       *         ; remap path for an ordinary block
                  ENDC
                  IFNE    arm6309 ; begin conditional assembly for arm6309
                    adda      #RAM.Hi   ; A = the block's high byte, from ldd a,u
                    sta       >DAT.RegsHi
                    stb       >DAT.Regs ; map block into $0000-$1FFF
                    ldb       ,x        ; load B from ,x
                    lda       #RAM.Hi   ; block 0 back
                    sta       >DAT.RegsHi
                    clr       >DAT.Regs
                  ELSE
                    stb       >DAT.Regs ; map block into $0000-$1FFF
                    ldb       ,x        ; load B from ,x
                    clr       >DAT.Regs ; restore mapping at $0000-$1FFF
                  ENDC
                    endif
ldone@              puls      cc,a,x,u  ; restore cc,a,x,u from the stack

                    stb       R$A,u     ; save into caller's A & return
                    clrb                ; set to no errors
                    rts                 ; return to caller

* Get pointer to task DAT image
* Entry: B=Task #
* Exit : U=Pointer to task image
*L0C09    ldu   <D.TskIPt    get pointer to task image table
*         lslb               multiply task # by 2
*         ldu   b,u          get pointer to task image (doesn't affect carry)
*         rts                restore & return


**************************************************
* System Call: F$STABX
*
* Function: Store A at 0,X in task B
*
* Input:  A = Data byte to store in task's address space
*         B = Task number
*         X = Logical address in task's address space
*
* Output: None
*
* Error:  CC = C bit set; B = error code
*
FSTABX              ldd       R$D,u     ; load D from R$D,u
                    ldx       R$X,u     ; load X from R$X,u

* Store a byte in another task
* Entry: A=Byte to store
*        B=Task #
*        X=Pointer to data
FLdabxCarry         andcc     #^Carry   ; clear condition-code bits using #^Carry
                    pshs      cc,d,x,u  ; save cc,d,x,u on the stack
                    bsr       FMoveTaskImageTable ; calculate offset into DAT image (fmove.asm)
                    ldd       a,u       ; get memory block
                  IFNE    mc09    ; begin conditional assembly for mc09
                    orcc      #IntMasks ; set condition-code bits using #IntMasks
                    lda       <D.TINIT  ; current MMU mask - selects block 0
                    sta       >MMUADR   ; select block 0

                    lda       1,s       ; haven't lost stack yet so this is safe

                    stb       >MMUDAT   ; map selected block into $0000-$1FFF
                    sta       ,x        ; store A at ,x
                    clr       >MMUDAT   ; restore mapping at $0000-$1FFF
                  ELSE
                  IFNE    arm6309 ; begin conditional assembly for arm6309
* NOTE: no stack between the first map write and the last - slot 0 is where
* the stack is.  U (pushed at entry) holds the map entry, Y the byte.
                    adda      #RAM.Hi   ; A = the block's high byte, from ldd a,u
                    tfr       d,u       ; U = the map entry, both bytes
                    pshs      y
                    ldb       3,s       ; the byte to store: A at entry, 1,s before this push
                    clra
                    tfr       d,y       ; Y = the byte
                    orcc      #IntMasks
                    tfr       u,d
                    sta       >DAT.RegsHi
                    stb       >DAT.Regs
                    tfr       y,d
                    stb       ,x
                    lda       #RAM.Hi   ; block 0 back
                    sta       >DAT.RegsHi
                    clr       >DAT.Regs
                    puls      y
                    puls      cc,d,x,u,pc
                  ENDC
                    lda       1,s       ; load A from 1,s
                    orcc      #IntMasks ; set condition-code bits using #IntMasks
                  IFNE    picothing ; begin conditional assembly for picothing
* Pico-Thing: page $FF (KrnBlk) cannot be mapped into slot 0 (NMI);
* write the kernel block in place via the fixed $E000-$FFFF window.
                    cmpb      #KrnBlk   ; is the destination the kernel block?
                    bne       smap@     ; no, map it normally
                    sta       >((DAT.BlCt-1)*DAT.BlSz),x ; write in place via the fixed window
                    bra       sdone@    ; skip the slot mapping
smap@               equ       *         ; remap path for an ordinary block
                  ENDC
                    stb       >DAT.Regs ; map selected block into $0000-$1FFF
                    sta       ,x        ; store A at ,x
                    clr       >DAT.Regs ; restore mapping at $0000-$1FFF
                    endif
sdone@              puls      cc,d,x,u,pc ; restore cc,d,x,u,pc from the stack
