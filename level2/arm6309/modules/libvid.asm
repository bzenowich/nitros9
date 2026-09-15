********************************************************************
* libvid - drawing on the arm6309 video card from a process that holds the
* exclusive screen (SS.Excl): a subroutine module
*
* arm6309 docs/nitros9-av-plan.md 3.5.  A program F$Links it and calls
* through its entry table, with Y = the card's base (SS.Excl's X):
*
*   entry+0  VlWait  SPANBUSY and LRUN clear; carry set if they never do
*   entry+3  VlPut   X = b18-16 b15-8 b7-0 n, then n (1-16) bytes: WPTR := the
*                    address, the bytes written direct.  X := past them
*   entry+6  VlGet   the same record, and the n bytes after it are filled
*                    with VRAM's bytes from the address.  X := past them
*   entry+9  VlFill  X = b18-16 b15-8 b7-0 n c: n (1-16) bytes of c.  X := past
*   entry+12 VlRect  X = x y w h (words, ring pixels) c: span-solid, a row and
*                    256 pixels at a time.  X := past
*   entry+15 VlPoke  X = n (1-13), b18-16, then n x (b15-8 b7-0 byte): a byte
*                    each at n addresses in one 64 K window - a column of map
*                    cells, whose rows are 128 bytes apart.  X := past
*
* Each call keeps the card's rules (vidcore.asm's V1-V3, V10, V12): it waits
* for SPANBUSY and LRUN, reloads WPTR itself, puts CTRL's WMODE and WADV
* where it needs them - read back from the register file, since the owner
* and the VBL service's SS.Batch both move them - and masks /IRQ from its
* first register write to its last VDATA byte.  That is why a put is at
* most 16 bytes: 32 measured 0.7 ms masked, and the VBL service's SS.Batch
* may use WPTR between two calls.  D, X (as said) and CC change; Y and U do not.
*
* ⚠ libvid cannot see the video console's globals, so it does not know when
* the VBL service has armed a display list (vidsvc.asm VcGo): the list owns
* WPTR from that GO, in the blank, although LRUN is not set until the blank
* ends.  An owner that also uses SS.Raster must not call libvid between a VBL
* and the end of its blank.
*
* Not here yet: text, icons, polygons and images (gui.asm's text, icon,
* poly and image).  The overworld test client needs none of them.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P3.

                    nam       libvid
                    ttl       arm6309 video card drawing for an exclusive screen

                    ifp1
                    use       defsfile
                    use       armvid.d
                    endc

tylg                set       Sbrtn+Objct
atrv                set       ReEnt+rev
rev                 set       0
edition             set       1

                    mod       eom,name,tylg,atrv,entry,0

name                fcs       /libvid/
                    fcb       edition

VlPolls             equ       16384

entry               lbra      VlWait
                    lbra      VlPut
                    lbra      VlGet
                    lbra      VlFill
                    lbra      VlRect
                    lbra      VlPoke

* VlWait - SPANBUSY and LRUN clear, with /IRQ as the caller has it
VlWait              pshs      x
                    ldx       #VlPolls
w@                  lda       VR.VSTAT,y
                    bita      #VSTAT.Busy+VSTAT.LRun
                    beq       ok@
                    leax      -1,x
                    bne       w@
                    puls      x
                    comb
                    rts
ok@                 puls      x
                    andcc     #^Carry
                    rts

* Direct - masked, the card idle: direct mode, WADV 00, WPTR := the three
* bytes at X
Direct              lda       VR.CTRL,y
                    bita      #CT.WMode
                    beq       a@
                    anda      #^CT.WMode
                    sta       VR.CTRL,y
a@                  tst       VR.WADV,y
                    beq       p@
                    clr       VR.WADV,y
p@                  lda       2,x
                    sta       VR.WPTR0,y
                    lda       1,x
                    sta       VR.WPTR1,y
                    lda       ,x
                    sta       VR.WPTR2,y
                    rts

* Begin - the call's first steps: /IRQ masked (the caller's CC on the stack
* under the return), the card waited for.  Carry set if it never came ready.
Begin               puls      d         the return
                    pshs      cc
                    orcc      #IRQMask
                    pshs      d
                    bsr       VlWait
                    rts

VlPut               bsr       Begin
                    bcs       e@
                    bsr       Direct
                    ldb       3,x
                    leax      4,x
c@                  lda       ,x+
                    sta       VR.VDATA,y
                    decb
                    bne       c@
                    lbra      End
e@                  lbra      Fail

VlGet               bsr       Begin
                    bcs       e@
                    bsr       Direct
                    ldb       3,x
                    leax      4,x
c@                  lda       VR.VDATA,y a read steps WPTR, whatever the mode (V10)
                    sta       ,x+
                    decb
                    bne       c@
                    bra       End
e@                  bra       Fail

VlFill              bsr       Begin
                    bcs       Fail
                    bsr       Direct
                    ldb       3,x
                    lda       4,x
                    leax      5,x
c@                  sta       VR.VDATA,y
                    decb
                    bne       c@

* End - the caller's /IRQ back, no error; Fail - the same, E$NotRdy
End                 puls      cc
                    andcc     #^Carry
                    rts
Fail                puls      cc
                    comb
                    ldb       #E$NotRdy
                    rts

VlPoke              lbsr      Begin
                    bcs       Fail
                    lda       2,x       Direct's WPTR from the first poke's address:
                    ldb       3,x       its own three bytes, so set its mode alone
                    pshs      d
                    lda       1,x
                    pshs      a
                    pshs      x
                    leax      2,s
                    lbsr      Direct
                    puls      x
                    leas      3,s
                    ldb       ,x
                    lda       1,x
                    leax      2,x
                    pshs      a
p@                  lda       1,x
                    sta       VR.WPTR0,y
                    lda       ,x
                    sta       VR.WPTR1,y
                    lda       ,s
                    sta       VR.WPTR2,y
                    lda       2,x
                    sta       VR.VDATA,y
                    leax      3,x
                    decb
                    bne       p@
                    leas      1,s
                    lbra      End

* VlRect - rows y .. y+h-1 from column x, w pixels, colour c: a span-solid
* of up to 256 at a time, each with its own WPTR load and SPANLEN
VlRect              pshs      u
                    tfr       x,u       U = the parameters
                    ldd       6,u       rows to go
                    pshs      d
r@                  ldd       ,s
                    lbeq      done@
                    ldd       4,u       pixels to go in the row
                    pshs      d
                    ldd       ,u        the column
                    pshs      d         column 0,s  pixels 2,s  rows 4,s
s@                  ldd       2,s
                    beq       nr@
                    ldd       2,u       the ring row: y + h - rows to go
                    addd      6,u
                    subd      4,s
                    anda      #1
                    lslb
                    rola
                    lslb
                    rola
                    pshs      d         row << 2 0,s  column 2,s  pixels 4,s  rows 6,s
                    ldd       4,s       this span: up to 256
                    cmpd      #256
                    bls       n@
                    ldd       #256
n@                  pshs      d         length 0,s  row 2,s  column 4,s  pixels 6,s  rows 8,s
                    pshs      cc
                    orcc      #IRQMask
                    lbsr      VlWait
                    bcs       e@
                    lda       VR.CTRL,y
                    anda      #^CT.WMode
                    ora       #WM.Solid
                    sta       VR.CTRL,y
                    clr       VR.WADV,y
                    lda       8,u
                    sta       VR.WFG,y
                    ldd       5,s       the column: bits 9-0
                    stb       VR.WPTR0,y
                    anda      #3
                    ora       4,s       and the row's 15-10
                    sta       VR.WPTR1,y
                    lda       3,s       and 18-16
                    sta       VR.WPTR2,y
                    ldb       2,s       SPANLEN is the length - 1: 256 is $00 - 1
                    decb
                    stb       VR.SPANLEN,y
                    sta       VR.VDATA,y the trigger: any byte
                    puls      cc
                    ldd       4,s
                    addd      ,s
                    std       4,s
                    ldd       6,s
                    subd      ,s
                    std       6,s
                    leas      4,s
                    bra       s@
nr@                 leas      4,s
                    ldd       ,s
                    subd      #1
                    std       ,s
                    bra       r@
e@                  puls      cc
                    leas      10,s
                    comb
                    ldb       #E$NotRdy
                    puls      u,pc
done@               leas      2,s
                    leax      9,u
                    puls      u
                    clrb
                    rts

                    emod
eom                 equ       *
                    end
