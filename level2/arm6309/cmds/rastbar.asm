********************************************************************
* rastbar - raster bars on a window's screen, by SS.Raster: a test client
*
*   rastbar >/w3
*
* Copies /DD/SYS/vgrast (escapes: a 640 x 200 screen with a band in
* palette entry RB.Idx, then Select) to its standard output, then rewrites
* the screen's display list once a frame for RB.Frames phases: the band's
* lines take the base colour, and three bars in gradients move across it -
* show.py's raster_colours, the arithmetic software/demo/gui.asm's opraster
* does.  Each list's tag is its phase, so a recording can say which phase
* each frame showed (the video console's VG.MkPh).  arm6309
* software/nitros9/tools/vgmodel.py writes both files, and is the model.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P3.

                    nam       rastbar
                    ttl       raster bars by SS.Raster: a test client

                    ifp1
                    use       defsfile
                    use       armvid.d
                    endc

                    mod       eom,name,Prgrm+Objct,ReEnt+0,start,size

* /DD/SYS/rastdat
RB.Y0               equ       0         the band's first scanline
RB.N                equ       2         band lines, two scanlines each
RB.Idx              equ       3         the palette entry
RB.Base             equ       4         the band's colour, RGB565
RB.Grad             equ       6         three bars x eight RGB565 words, by distance
RB.Sin              equ       54        256 band lines: bar b's centre at phase p is Sin[p + 85b]
RB.Frames           equ       310       phases to run
RB.Step             equ       311       phase step a frame
RB.Size             equ       312

                    org       0
path                rmb       1
k                   rmb       1
ph                  rmb       1
bar                 rmb       1
cen                 rmb       1
i                   rmb       1
buf                 rmb       256
dat                 rmb       RB.Size
tab                 rmb       10+2*256
                    rmb       250       stack
size                equ       .

name                fcs       /rastbar/
                    fcb       1

sname               fcs       "/DD/SYS/vgrast"
dname               fcs       "/DD/SYS/rastdat"

start               leax      sname,pcr the screen
                    lda       #READ.
                    os9       I$Open
                    lbcs      err
                    sta       path,u
c@                  lda       path,u
                    leax      buf,u
                    ldy       #256
                    os9       I$Read
                    bcs       e@
                    lda       #1
                    os9       I$Write
                    lbcs      err
                    bra       c@
e@                  cmpb      #E$EOF
                    lbne      err
                    lda       path,u
                    os9       I$Close
                    leax      dname,pcr the bars
                    lda       #READ.
                    os9       I$Open
                    lbcs      err
                    leax      dat,u
                    ldy       #RB.Size
                    os9       I$Read
                    lbcs      err
                    os9       I$Close
                    ldb       #40       Select's palette arrives sixteen entries a blank
w@                  lbsr      frame
                    decb
                    bne       w@

                    clr       k,u
f@                  lda       k,u       ph := k * step
                    ldb       dat+RB.Step,u
                    mul
                    stb       ph,u
                    leax      tab,u     the table's head
                    lda       #1        a palette entry,
                    sta       RT.Kind,x
                    lda       #2        two scanlines an entry
                    sta       RT.Lines,x
                    ldd       dat+RB.Y0,u
                    std       RT.Y0,x
                    clra
                    ldb       dat+RB.N,u
                    std       RT.N,x
                    lda       dat+RB.Idx,u
                    clrb
                    std       RT.Idx,x
                    clra
                    ldb       ph,u
                    std       RT.Tag,x  the tag is the phase
                    leax      RT.Tab,x  every band line the base colour
                    ldb       dat+RB.N,u
                    ldy       dat+RB.Base,u
b@                  sty       ,x++
                    decb
                    bne       b@
                    clr       bar,u     then three bars, later over earlier
r@                  lda       bar,u     centre := Sin[(ph + 85 bar) & 255]
                    ldb       #85
                    mul
                    addb      ph,u
                    leax      dat+RB.Sin,u
                    abx
                    lda       ,x
                    sta       cen,u
                    clr       i,u
l@                  lda       i,u       distance
                    suba      cen,u
                    bpl       p@
                    nega
p@                  cmpa      #8
                    bhs       n@
                    pshs      a         Grad[bar * 8 + d]
                    lda       bar,u
                    lsla
                    lsla
                    lsla
                    adda      ,s+
                    lsla
                    leax      dat+RB.Grad,u
                    leax      a,x
                    ldy       ,x
                    ldb       i,u       entry i
                    clra
                    lslb
                    rola
                    leax      tab+RT.Tab,u
                    leax      d,x
                    sty       ,x
n@                  inc       i,u
                    lda       i,u
                    cmpa      dat+RB.N,u
                    bne       l@
                    inc       bar,u
                    lda       bar,u
                    cmpa      #3
                    bne       r@
                    lda       #1
                    ldb       #SS.Raster
                    leax      tab,u
                    os9       I$SetStt
                    bcs       err
                    bsr       frame
                    inc       k,u
                    lda       k,u
                    cmpa      dat+RB.Frames,u
                    lbne      f@
                    lda       #1        the list off, and the band as it was
                    ldb       #SS.RastOff
                    os9       I$SetStt
                    bcs       err
                    clrb
err                 os9       F$Exit

* frame - until the next VBL has been served.  B is kept.
frame               pshs      b
                    lda       #1
                    ldb       #SS.FrmWait
                    os9       I$SetStt
                    puls      b,pc

                    emod
eom                 equ       *
                    end
