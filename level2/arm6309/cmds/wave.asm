********************************************************************
* wave - a warp of a window's screen, by SS.Raster: a test client
*
*   wave >/w3
*
* Copies /DD/SYS/vgwave (escapes: a 640 x 200 screen of stripes and text,
* then Select) to its standard output, then rewrites the screen's display
* list once a frame for WV.Frames phases: band line i of the warp is
* scrolled (Tab[(ph + 2i) & 255] * Amp) >> 8 pixels, the arithmetic
* software/demo/gui.asm's opwave does.  Each list's tag is its phase (the
* video console's VG.MkPh).  arm6309 software/nitros9/tools/vgmodel.py
* writes both files, and is the model.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P3.

                    nam       wave
                    ttl       a warp by SS.Raster: a test client

                    ifp1
                    use       defsfile
                    use       armvid.d
                    endc

                    mod       eom,name,Prgrm+Objct,ReEnt+0,start,size

* /DD/SYS/wavedat
WV.Y0               equ       0         the warp's first scanline
WV.N                equ       2         band lines, two scanlines each
WV.Amp              equ       3         amplitude, 256ths
WV.Tab              equ       4         256 offsets, 0-255
WV.Frames           equ       260       phases to run
WV.Step             equ       261       phase step a frame
WV.Size             equ       262

                    org       0
path                rmb       1
k                   rmb       1
ph                  rmb       1
i                   rmb       1
buf                 rmb       256
dat                 rmb       WV.Size
tab                 rmb       10+2*256
                    rmb       250       stack
size                equ       .

name                fcs       /wave/
                    fcb       1

sname               fcs       "/DD/SYS/vgwave"
dname               fcs       "/DD/SYS/wavedat"

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
                    leax      dname,pcr the warp
                    lda       #READ.
                    os9       I$Open
                    lbcs      err
                    leax      dat,u
                    ldy       #WV.Size
                    os9       I$Read
                    lbcs      err
                    os9       I$Close
                    ldb       #40       Select's palette arrives sixteen entries a blank
w@                  lbsr      frame
                    decb
                    bne       w@

                    clr       k,u
f@                  lda       k,u       ph := k * step
                    ldb       dat+WV.Step,u
                    mul
                    stb       ph,u
                    leax      tab,u     the table's head
                    clr       RT.Kind,x HSCROLL,
                    lda       #2        two scanlines an entry
                    sta       RT.Lines,x
                    ldd       dat+WV.Y0,u
                    std       RT.Y0,x
                    clra
                    ldb       dat+WV.N,u
                    std       RT.N,x
                    clr       RT.Idx,x
                    clr       RT.Idx+1,x
                    clra
                    ldb       ph,u
                    std       RT.Tag,x  the tag is the phase
                    leax      RT.Tab,x
                    clr       i,u
l@                  lda       i,u       Tab[(ph + 2i) & 255] * Amp >> 8
                    lsla
                    adda      ph,u
                    pshs      x
                    leax      dat+WV.Tab,u
                    tfr       a,b
                    abx
                    lda       ,x
                    puls      x
                    ldb       dat+WV.Amp,u
                    mul
                    tfr       a,b
                    clra
                    std       ,x++
                    inc       i,u
                    lda       i,u
                    cmpa      dat+WV.N,u
                    bne       l@
                    lda       #1
                    ldb       #SS.Raster
                    leax      tab,u
                    os9       I$SetStt
                    bcs       err
                    bsr       frame
                    inc       k,u
                    lda       k,u
                    cmpa      dat+WV.Frames,u
                    bne       f@
                    lda       #1        the list off, and the screen unwarped
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
