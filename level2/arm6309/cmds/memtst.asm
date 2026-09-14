********************************************************************
* memtst - are RAM blocks past $FF really distinct memory?
*
* The check for arm6309's 16-bit block numbers (defs/arm6309.d).  A block
* whose map-entry high byte is not written maps block b - 256 instead, so
* every free block gets its own number written into it and read back:
*
*   1. F$AllRAM one block at a time until there is no more - so the test
*      takes all of RAM, and on an 8 MB machine that runs to $3FF.
*   2. For each: F$MapBlk into this process (the task switch writes the map:
*      krn's KrnActualMMUBlock), store the number and its complement, F$ClrBlk.
*   3. Give the six highest back, F$Fork pmap into them and wait.  A whole
*      process - its stack, its system calls, the IRQ path's F$LDABX of its
*      CC - then lives past $FF, and pass 4 checks it disturbed nothing.
*      (pmap prints a block's low byte only.)
*   4. For each still held, after ALL were written: F$MapBlk and compare, so a
*      block that aliased another has been overwritten by it.
*   5. For each: F$CpyMem the four bytes through a DAT image naming just that
*      block.  The kernel reads the image out of this process with F$LDDDXY
*      (fld.asm), so the image is put inside the highest block held, where
*      only a correct high byte finds it; the bytes come across by F$Move
*      (fmove.asm).
*   6. F$DelRAM every block.
*
* Prints   memtst: nnnn blocks to $xxxx, MapBlk ok, CpyMem ok
*    or    ... MapBlk ALIASED at $xxxx   (and/or CpyMem ALIASED at $xxxx)
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Initial version.

                    nam       memtst
                    ttl       16-bit block test

                    ifp1
                    use       defsfile
                    endc

MaxBlks             equ       1024
GiveBack            equ       6         blocks returned for pmap

                    mod       eom,name,Prgrm+Objct,ReEnt+0,start,size

                    org       0
n                   rmb       2         blocks held
blk                 rmb       2         the block in hand
idx                 rmb       2         pointer into tbl
badmap              rmb       2         first MapBlk failure + 1, 0 = none
badcpy              rmb       2         first CpyMem failure + 1, 0 = none
imgp                rmb       2         the DAT image, inside a high block
highest             rmb       2
n1                  rmb       2
got                 rmb       4
line                rmb       80
tbl                 rmb       MaxBlks*2 the blocks, in the order F$AllRAM gave them
                    rmb       400       stack
size                equ       .

name                fcs       /memtst/
                    fcb       2

pmapn               fcs       /pmap/
cr                  fcb       C$CR
m1                  fcc       "memtst: "
m1l                 equ       *-m1
m2                  fcc       " blocks to $"
m2l                 equ       *-m2
m3                  fcc       ", MapBlk "
m3l                 equ       *-m3
m4                  fcc       ", CpyMem "
m4l                 equ       *-m4
mok                 fcc       "ok"
mokl                equ       *-mok
mbad                fcc       "ALIASED at $"
mbadl               equ       *-mbad

start               clra
                    clrb
                    std       n,u
                    std       badmap,u
                    std       badcpy,u
                    std       highest,u

* 1. every free block
                    lbsr      GrabAll
                    ldd       n,u
                    std       n1,u      the first sweep's count: its last six are the highest
                    cmpd      #GiveBack+2
                    lbls      exit

* 2. write every block's number into it
                    lbsr      First
w@                  lbsr      Map
                    ldd       blk,u
                    std       ,x
                    coma
                    comb
                    std       2,x
                    lbsr      Unmap
                    lbsr      Next
                    bne       w@

* 3. the six highest back, and a process into them.  The system may have
* returned blocks while pass 2 ran (F$SRtMem gives an emptied block back), so
* take those too first - they land at the end of tbl - and then return the
* first sweep's last six, which are the highest, and close the gap.
                    lbsr      GrabAll
                    ldd       n1,u
                    subd      #GiveBack
                    lslb
                    rola
                    leax      tbl,u
                    leax      d,x       the first of the six
                    pshs      x
                    ldb       #GiveBack
                    pshs      b
g@                  pshs      x
                    ldx       ,x
                    ldb       #1
                    os9       F$DelRAM
                    puls      x
                    leax      2,x
                    dec       ,s
                    bne       g@
                    leas      1,s
                    puls      y         Y = the gap, X = past it
                    ldd       n,u       entries after the gap: n - n1
                    subd      n1,u
                    beq       closed@
                    lslb
                    rola
                    pshs      d
m@                  ldd       ,x++
                    std       ,y++
                    ldd       ,s
                    subd      #1
                    std       ,s
                    bne       m@
                    leas      2,s
closed@             ldd       n,u
                    subd      #GiveBack
                    std       n,u
                    pshs      u
                    leax      pmapn,pcr
                    leau      cr,pcr
                    ldy       #1
                    lda       #Prgrm+Objct
                    clrb
                    os9       F$Fork
                    puls      u
                    lbcs      exit
                    os9       F$Wait

* 4. read them back through F$MapBlk
                    lbsr      First
r@                  lbsr      Map
                    ldd       ,x
                    cmpd      blk,u
                    bne       rbad@
                    coma
                    comb
                    cmpd      2,x
                    beq       rok@
rbad@               ldd       badmap,u
                    bne       rok@
                    ldd       blk,u
                    addd      #1
                    std       badmap,u
rok@                lbsr      Unmap
                    lbsr      Next
                    bne       r@

* 5. through F$CpyMem, with the image inside the highest block still held
                    ldd       n,u
                    subd      #1
                    lslb
                    rola
                    leax      tbl,u
                    ldd       d,x
                    std       blk,u
                    std       highest,u
                    lbsr      Map
                    leax      $100,x    clear of the block's own four bytes
                    stx       imgp,u
                    lbsr      First
c@                  ldx       imgp,u
                    ldd       blk,u
                    std       ,x++      slot 0 of a one-block image
                    ldb       #7
                    pshs      b
f@                  ldd       #DAT.Free
                    std       ,x++
                    dec       ,s
                    bne       f@
                    leas      1,s
                    ldd       imgp,u    D = the image, in a high block
                    ldx       #0
                    ldy       #4
                    pshs      u
                    leau      got,u
                    os9       F$CpyMem
                    puls      u
                    lbcs      exit
                    ldd       got,u
                    cmpd      blk,u
                    bne       cbad@
                    coma
                    comb
                    cmpd      got+2,u
                    beq       cok@
cbad@               ldd       badcpy,u
                    bne       cok@
                    ldd       blk,u
                    addd      #1
                    std       badcpy,u
cok@                lbsr      Next
                    bne       c@
                    ldx       imgp,u
                    leax      -$100,x
                    lbsr      Unmap

* 6. every block back
                    lbsr      First
d@                  ldx       blk,u
                    ldb       #1
                    os9       F$DelRAM
                    lbsr      Next
                    bne       d@

* the report
                    leay      line,u
                    leax      m1,pcr
                    ldb       #m1l
                    lbsr      Copy
                    ldd       n,u
                    addd      #GiveBack
                    lbsr      Hex4
                    leax      m2,pcr
                    ldb       #m2l
                    lbsr      Copy
                    ldd       highest,u
                    lbsr      Hex4
                    leax      m3,pcr
                    ldb       #m3l
                    lbsr      Copy
                    ldd       badmap,u
                    lbsr      Verdict
                    leax      m4,pcr
                    ldb       #m4l
                    lbsr      Copy
                    ldd       badcpy,u
                    lbsr      Verdict
                    lda       #C$CR
                    sta       ,y+
                    tfr       y,d
                    leax      line,u
                    pshs      x
                    subd      ,s++
                    tfr       d,y
                    lda       #1
                    os9       I$WritLn
                    clrb
exit                os9       F$Exit

* GrabAll: F$AllRAM one block at a time onto the end of tbl until none are left
GrabAll             ldd       n,u
                    lslb
                    rola
                    leay      tbl,u
                    leay      d,y
all@                ldd       n,u
                    cmpd      #MaxBlks
                    bhs       took@
                    ldb       #1
                    pshs      y
                    os9       F$AllRAM
                    puls      y
                    bcs       took@
                    std       ,y++
                    cmpd      highest,u
                    bls       lo@
                    std       highest,u
lo@                 ldd       n,u
                    addd      #1
                    std       n,u
                    bra       all@
took@               rts

* First: blk := tbl[0], idx := tbl.  Next: to the following entry, Z set
* past the n held.
First               leax      tbl,u
                    stx       idx,u
                    ldd       ,x
                    std       blk,u
                    rts
Next                ldx       idx,u
                    leax      2,x
                    stx       idx,u
                    ldd       ,x
                    std       blk,u
                    tfr       x,d
                    pshs      u
                    subd      ,s++
                    subd      #tbl
                    lsra
                    rorb
                    cmpd      n,u
                    rts

* Map: F$MapBlk blk,u -> X
Map                 ldx       blk,u
                    ldb       #1
                    pshs      u
                    os9       F$MapBlk
                    tfr       u,x
                    puls      u
                    bcs       fail@
                    rts
fail@               leas      2,s
                    lbra      exit
* Unmap: F$ClrBlk the block at X
Unmap               pshs      u
                    tfr       x,u
                    ldb       #1
                    os9       F$ClrBlk
                    puls      u,pc

* Verdict: D = 0 -> "ok", else "ALIASED at $" and D - 1
Verdict             subd      #1
                    bcc       b@
                    leax      mok,pcr
                    ldb       #mokl
                    bra       Copy
b@                  pshs      d
                    leax      mbad,pcr
                    ldb       #mbadl
                    bsr       Copy
                    puls      d
                    bra       Hex4

Copy                lda       ,x+
                    sta       ,y+
                    decb
                    bne       Copy
                    rts

* Hex4: D as four hex digits at Y
Hex4                pshs      b
                    bsr       Hex2
                    puls      a
Hex2                pshs      a
                    lsra
                    lsra
                    lsra
                    lsra
                    bsr       Nib
                    puls      a
Nib                 anda      #$0F
                    adda      #'0
                    cmpa      #'9
                    bls       n@
                    adda      #'A-'9-1
n@                  sta       ,y+
                    rts

                    emod
eom                 equ       *
                    end
