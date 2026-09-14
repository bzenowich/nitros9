********************************************************************
* ps2tst - initialise both PS/2 ports the way ps2.md says, and echo bytes
*
* A test of the arm6309 PS/2 card (io/ps2/docs/ps2.md) and of the emulator's
* model of it, before the keyboard and mouse drivers exist (plan phase P1).
* It is ps2.md 7's software transmit and 11.2's initialisation, polled,
* with IRQEN left 0 - nothing in the system handles the card's interrupt yet.
*
*   ps2tst     prints
*     kbd: FA AA FA AB 83 FA ED ... then 3 more bytes (the scan codes)
*     mouse: FA AA 00 FA FA FA ... then 3 more bytes (one packet)
*
* The bytes are every one received, in order, after each command:
*   keyboard  FF -> FA AA,  F2 -> FA AB 83,  F4 -> FA,  then three
*   mouse     FF -> FA AA 00,  F3 3C -> FA FA,  F4 -> FA,  then three
*
* Transmit follows ps2.md 7 step for step, in REGISTER polarity: hold KRST,
* mask /IRQ (not /FIRQ), CLK low >= 100 us, start bit, release CLK; for each
* of eight data bits, parity and stop, wait for IOSTAT.KCLK = 1 (the line
* low) and write KDATD = the complement of the bit; release DATA; wait for
* the ACK (IOSTAT.KDAT = 1); release KRST once KCLK reads 0.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Initial version.

                    nam       ps2tst
                    ttl       PS/2 initialisation test

                    ifp1
                    use       defsfile
                    endc

* ps2.md 8
KDATA               equ       0
MDATA               equ       1
IOSTAT              equ       2
IOCTRL              equ       3

                    mod       eom,name,Prgrm+Objct,ReEnt+0,start,size

                    org       0
port                rmb       1         0 keyboard, 1 mouse
shadow              rmb       1         IOCTRL is write-only
tbyte               rmb       1
tpar                rmb       1
datbit              rmb       1         this port's IOCTRL DATD bit
clkbit              rmb       1         this port's IOSTAT CLK bit
datst               rmb       1         this port's IOSTAT DAT bit
count               rmb       1
vals                rmb       10        the frame's ten IOCTRL values
line                rmb       80
lptr                rmb       2
                    rmb       300       stack
size                equ       .

name                fcs       /ps2tst/
                    fcb       1

kmsg                fcc       "kbd:"
mmsg                fcc       "mouse:"

start               clr       shadow,u
                    lbsr      PutCtl

* ---- the keyboard ----
                    clr       port,u
                    leay      line,u
                    leax      kmsg,pcr
                    ldb       #4
                    lbsr      Copy
                    lbsr      Phase     11.2 step 0
                    lda       #$FF
                    ldb       #2        FA AA
                    lbsr      Cmd
                    lda       #$F2
                    ldb       #3        FA AB 83
                    lbsr      Cmd
                    lda       #$F4
                    ldb       #1        FA
                    lbsr      Cmd
                    ldb       #3        three scan codes
                    lbsr      Recv
                    lbsr      Emit

* ---- the mouse ----
                    lda       #1
                    sta       port,u
                    leay      line,u
                    leax      mmsg,pcr
                    ldb       #6
                    lbsr      Copy
                    lbsr      Phase
                    lda       #$FF
                    ldb       #3        FA AA 00
                    lbsr      Cmd
                    lda       #$F3
                    ldb       #1        FA
                    lbsr      Cmd
                    lda       #$3C      60 samples/s, ps2.md 5.2
                    ldb       #1        FA
                    lbsr      Cmd
                    lda       #$F4
                    ldb       #1        FA
                    lbsr      Cmd
                    ldb       #3        one packet
                    lbsr      Recv
                    lbsr      Emit
                    clrb
                    os9       F$Exit

* Cmd: send A, then receive B bytes into the line.
Cmd                 pshs      b
                    lbsr      Send
                    puls      b
* Recv: B bytes into the line, each as " XX"; a timeout prints " --".
Recv                pshs      b
r@                  lbsr      Get
                    bcc       ok@
                    ldd       #$2D2D    "--"
                    bra       put@
ok@                 lbsr      Hex
put@                pshs      d
                    lda       #' 
                    sta       ,y+
                    puls      d
                    std       ,y++
                    dec       ,s
                    bne       r@
                    puls      b,pc

* Get: A = the next byte on this port, carry set after ~0.5 s of nothing.
Get                 ldx       #0
g@                  ldb       >PS2.Base+IOSTAT
                    tst       port,u
                    beq       k@
                    lsrb                MDR is b1
k@                  lsrb                KDR is b0
                    bcs       have@
                    leax      -1,x
                    bne       g@
                    comb
                    rts
have@               ldb       port,u
                    ldx       #PS2.Base
                    lda       b,x       KDATA or MDATA; the read clears DR
                    andcc     #^Carry
                    rts

* Phase: 11.2 step 0 - hold the counter, wait for CLK idle, release.
* It also drains DR: the device's power-on bytes (AA, and the mouse's 00)
* arrived long before anything read them, and the one-byte latch still
* holds the last (ps2.md 5 - there is no FIFO to have kept the rest).
Phase               lbsr      RstOn
p@                  lbsr      ClkLow
                    bne       p@
                    lbsr      RstOff
                    ldb       port,u
                    ldx       #PS2.Base
                    lda       b,x       the read clears KDR/MDR
                    rts

* ClkLow: Z clear if IOSTAT's CLK bit for this port reads 1 (the line low).
ClkLow              lda       #%00000100
                    tst       port,u
                    beq       c@
                    lda       #%00010000
c@                  bita      >PS2.Base+IOSTAT
                    rts
* DatLow: likewise for DATA.
DatLow              lda       #%00001000
                    tst       port,u
                    beq       d@
                    lda       #%00100000
d@                  bita      >PS2.Base+IOSTAT
                    rts

* the IOCTRL bits for this port: A = mask
RstOn               lda       #%00010000
                    lbsr      Shift
                    ora       shadow,u
                    bra       Put
RstOff              lda       #%00010000
                    lbsr      Shift
                    coma
                    anda      shadow,u
                    bra       Put
ClkOn               lda       #%00000001
                    lbsr      Shift2
                    ora       shadow,u
                    bra       Put
ClkOff              lda       #%00000001
                    lbsr      Shift2
                    coma
                    anda      shadow,u
                    bra       Put
DatOn               lda       #%00000010
                    lbsr      Shift2
                    ora       shadow,u
                    bra       Put
DatOff              lda       #%00000010
                    lbsr      Shift2
                    coma
                    anda      shadow,u
Put                 sta       shadow,u
PutCtl              lda       shadow,u
                    sta       >PS2.Base+IOCTRL
                    rts
* Shift: the mouse's KRST is MRST, one bit up.  Shift2: two bits up.
Shift               tst       port,u
                    beq       s@
                    lsla
s@                  rts
Shift2              tst       port,u
                    beq       t@
                    lsla
                    lsla
t@                  rts

* Send: A, by ps2.md 7.  Returns carry set on a timeout.
*
* The device holds CLK low for one 30-50 us half-period per bit, and the bit
* must be on DATA before it lets CLK rise - about 80 E cycles at 2 MHz.  So
* the ten IOCTRL values (8 data, parity, stop) are worked out BEFORE the
* frame, and the loop per bit is a poll and a store: the budget ps2.md 7 is
* talking about when it calls the transmit cheap, and the one subroutine
* calls per bit would overrun.
Send                pshs      y         the line pointer
                    sta       tbyte,u
                    ldb       #1        odd parity: 1 + the data bits, mod 2
                    ldx       #8
par@                lsra
                    adcb      #0
                    leax      -1,x
                    bne       par@
                    andb      #1
                    stb       tpar,u
                    lbsr      RstOn     1. hold the receive counter
                    lda       #%00000010 this port's DATD bit
                    lbsr      Shift2
                    sta       datbit,u
                    lda       #%00000100 this port's IOSTAT CLK bit ...
                    tst       port,u
                    beq       k@
                    lda       #%00010000
k@                  sta       clkbit,u
                    lda       #%00001000 ... and DAT bit
                    tst       port,u
                    beq       k2@
                    lda       #%00100000
k2@                 sta       datst,u
* the ten IOCTRL values: DATD set for a 0 bit, clear for a 1
                    leay      vals,u
                    lda       tbyte,u
                    ldb       #8
v@                  lsra
                    pshs      a,b
                    lda       shadow,u
                    bcs       one@
                    ora       datbit,u
                    bra       st@
one@                ldb       datbit,u
                    comb
                    pshs      b
                    anda      ,s+
st@                 sta       ,y+
                    puls      a,b
                    decb
                    bne       v@
                    lda       shadow,u  parity
                    tst       tpar,u
                    bne       p1@
                    ora       datbit,u
                    bra       p2@
p1@                 ldb       datbit,u
                    comb
                    pshs      b
                    anda      ,s+
p2@                 sta       ,y+
                    ldb       datbit,u  stop: released
                    comb
                    pshs      b
                    lda       shadow,u
                    anda      ,s+
                    sta       ,y+
                    pshs      cc
                    orcc      #IRQMask  2. /IRQ only: FIRQ stays live
                    lbsr      ClkOn     3. inhibit ...
                    ldx       #60       ... >= 100 us
dly@                leax      -1,x
                    bne       dly@
                    lbsr      DatOn     ... the start bit
                    lbsr      ClkOff    ... and release CLK
* 4. for each value: wait for CLK low, store it, wait for CLK high
                    leay      vals,u
                    ldb       clkbit,u
                    lda       #10
                    sta       count,u
                    ldx       #0        15 ms for the device to start
bit@                bitb      >PS2.Base+IOSTAT
                    bne       low@
                    leax      -1,x
                    bne       bit@
                    bra       tmo@
low@                lda       ,y+
                    sta       >PS2.Base+IOCTRL
                    ldx       #0
hi@                 bitb      >PS2.Base+IOSTAT
                    beq       rise@
                    leax      -1,x
                    bne       hi@
                    bra       tmo@
rise@               ldx       #0
                    dec       count,u
                    bne       bit@
                    lda       -1,y      the stop value: DATA released
                    sta       shadow,u
* 5. the ACK: the device pulls DATA low on the next clock
                    ldb       datst,u
                    ldx       #0
ack@                bitb      >PS2.Base+IOSTAT
                    bne       acked@
                    leax      -1,x
                    bne       ack@
                    bra       tmo@
* 6. KRST off once both lines are idle
acked@              ldx       #0
idle@               lda       >PS2.Base+IOSTAT
                    bita      datst,u
                    bne       i2@
                    bita      clkbit,u
                    beq       rel@
i2@                 leax      -1,x
                    bne       idle@
rel@                lbsr      RstOff
                    puls      cc,y
                    andcc     #^Carry
                    rts
tmo@                lbsr      DatOff
                    lbsr      RstOff
                    puls      cc,y
                    comb
                    rts

* Hex: A as two ASCII digits in D.
Hex                 tfr       a,b
                    lsra
                    lsra
                    lsra
                    lsra
                    bsr       nib@
                    exg       a,b
                    anda      #$0F
                    bsr       nib@
                    exg       a,b
                    rts
nib@                adda      #'0
                    cmpa      #'9
                    bls       n@
                    adda      #'A-'9-1
n@                  rts

Copy                lda       ,x+
                    sta       ,y+
                    decb
                    bne       Copy
                    rts

* Emit: the line up to Y and a CR.
Emit                lda       #C$CR
                    sta       ,y+
                    tfr       y,d
                    leax      line,u
                    pshs      x
                    subd      ,s++
                    tfr       d,y
                    lda       #1
                    os9       I$WritLn
                    rts

                    emod
eom                 equ       *
                    end
