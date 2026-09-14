********************************************************************
* overworld - the demo's tile-map game on an exclusive tile screen: a test
* client
*
*   overworld >/w3
*
* software/demo/demo.asm's game loop, moved under NitrOS-9 (arm6309
* docs/nitros9-av-plan.md 7, the overworld row).  It copies /DD/SYS/vggame
* to its standard output - DWSet $1C, the RGB332 palette by PalRange, Select
* - claims the screen with SS.Excl, uploads /DD/SYS/tiles.bin with SS.TileLd
* and writes the first view with SS.MapWr.  Then once a frame (SS.FrmWait)
* it steps the camera through /DD/SYS/frames.bin by the frames that passed,
* writes the map strips that scroll into view directly with libvid, builds
* the hero's fifteen tiles a tile a frame - reading the background tiles
* back out of VRAM - and hands the scroll, the hero's flip and the two
* record numbers to the VBL service in one SS.Batch.  So the camera and the
* hero on the screen change in the same blank, and VG.MkCam and VG.MkHero
* say which records a recorded frame shows: software/demo/tools/mkgame.py's
* render() is the model.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P3.

                    nam       overworld
                    ttl       the demo's overworld on an exclusive screen

                    ifp1
                    use       defsfile
                    use       armvid.d
                    endc

                    mod       eom,name,Prgrm+Objct,ReEnt+0,start,size

SPRKEY              equ       $E3       mkgame.py's KEY: a transparent sprite byte
SPRA                equ       226       the first of the hero's 30 tile codes
WORLDB              equ       19456     76 rows x 256
TILES               equ       16384
VL.Wait             equ       0         libvid's entries
VL.Put              equ       3
VL.Get              equ       6
VL.Poke             equ       15

                    org       0
path                rmb       1
lvent               rmb       2
base                rmb       2
nfr                 rmb       2
lastf               rmb       2
k                   rmb       2
pk                  rmb       2
herok               rmb       2
pcamx               rmb       2
pcamy               rmb       2
cl                  rmb       1
rt                  rmb       1
hvis                rmb       1
hbase               rmb       1
hc0                 rmb       1
hr0                 rmb       1
jstate              rmb       1         0 idle, 1 composing, 2 ready to flip, 3 flipped this frame
jx                  rmb       2
jy                  rmb       2
jf                  rmb       1
jk                  rmb       2
jtile               rmb       1
jbase               rmb       1
jstage              rmb       1
tx                  rmb       2
ty                  rmb       2
tf                  rmb       1
gcol                rmb       1
grow                rmb       1
gtmp                rmb       1
gcol2               rmb       1
grow2               rmb       1
gdelta              rmb       2
ocol                rmb       1
orow                rmb       1
ohvis               rmb       1
frow                rmb       1
fcol                rmb       1
fcode               rmb       1
ci                  rmb       1
cj                  rmb       1
cpr                 rmb       1
csy                 rmb       1
ccol                rmb       1
bp                  rmb       2         the batch being built
cnt                 rmb       1
pkp                 rmb       2         the count of the flip's BT.Poke, or 0
rec                 rmb       4+16      a libvid record
poke                rmb       2+3*13    half a column of map cells, for libvid
cbuf                rmb       64        a tile being built
mw                  rmb       MW.Codes+81 an SS.MapWr row
batch               rmb       BT.Max
iobuf               rmb       64
tilefr              rmb       TILES     the tiles, then the frame records
world               rmb       WORLDB
sprites             rmb       4096
                    rmb       300       stack
size                equ       .
* ⚠ five blocks, no more: the module and libvid each take a block of the
* 64 K map, and the kernel's is the eighth
                    ifgt      size-40960
                    error     overworld's data is more than five blocks
                    endc

name                fcs       /overworld/
                    fcb       1

sname               fcs       "/DD/SYS/vggame"
tname               fcs       "/DD/SYS/tiles.bin"
wname               fcs       "/DD/SYS/world.bin"
pname               fcs       "/DD/SYS/sprites.bin"
fname               fcs       "/DD/SYS/frames.bin"
lname               fcs       "libvid"

********************************************************************
start               leax      sname,pcr the screen, its palette, Select
                    lda       #READ.
                    os9       I$Open
                    lbcs      err
                    sta       path,u
c@                  lda       path,u
                    leax      iobuf,u
                    ldy       #64
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
                    ldb       #40       the palette arrives sixteen entries a blank
w@                  lbsr      frame
                    decb
                    bne       w@
                    pshs      u         libvid: linked, or loaded from the execution directory
                    leax      lname,pcr
                    lda       #Sbrtn+Objct
                    os9       F$Link
                    bcc       l@
                    leax      lname,pcr
                    lda       #Sbrtn+Objct
                    os9       F$Load
l@                  puls      u
                    lbcs      err
                    sty       lvent,u
                    lda       #1        the screen is ours
                    ldb       #SS.Excl
                    ldy       #1
                    os9       I$SetStt
                    lbcs      err
                    stx       base,u
                    leax      tname,pcr the tiles, up to the card
                    leay      tilefr,u
                    ldd       #TILES
                    lbsr      load
                    lda       #1
                    ldb       #SS.TileLd
                    leax      tilefr,u
                    ldy       #TL.TBank
                    os9       I$SetStt
                    lbcs      err
                    leax      wname,pcr
                    leay      world,u
                    ldd       #WORLDB
                    lbsr      load
                    leax      pname,pcr
                    leay      sprites,u
                    ldd       #4096
                    lbsr      load
                    leax      fname,pcr the frame records, where the tiles were
                    leay      tilefr,u
                    ldd       #TILES
                    lbsr      load
                    lsra                records: bytes / 8
                    rorb
                    lsra
                    rorb
                    lsra
                    rorb
                    std       nfr,u

* the first view: record 0's camera, every covered row, by SS.MapWr
                    clra
                    clrb
                    std       k,u
                    lbsr      readrec
                    ldd       pcamx,u
                    lbsr      shr3
                    stb       cl,u
                    ldd       pcamy,u
                    lbsr      shr3
                    stb       rt,u
                    clr       hvis,u
                    clr       jstate,u
                    ldd       #$FFFF    no hero on the screen yet
                    std       herok,u
                    clr       gtmp,u
fv@                 lda       rt,u
                    adda      gtmp,u
                    sta       grow,u
                    leax      mw,u
                    lda       cl,u
                    sta       MW.Col,x
                    lda       grow,u
                    sta       MW.Row,x
                    lda       #81
                    sta       MW.W,x
                    lda       #1
                    sta       MW.H,x
                    leax      MW.Codes,x
                    lda       cl,u
                    sta       gcol,u
                    lda       #81
                    sta       cnt,u
fc@                 lda       grow,u
                    ldb       gcol,u
                    lbsr      cellcode
                    sta       ,x+
                    inc       gcol,u
                    dec       cnt,u
                    bne       fc@
                    lda       #1
                    ldb       #SS.MapWr
                    leax      mw,u
                    ldy       #MW.Codes+81
                    os9       I$SetStt
                    lbcs      err
                    inc       gtmp,u
                    lda       gtmp,u
                    cmpa      #26
                    bne       fv@
                    leax      batch,u   the camera, in the next blank
                    stx       bp,u
                    lbsr      scroll
                    lbsr      frame
                    stx       lastf,u

********************************************************************
* the game: a frame at a time
gloop               lbsr      frame     X := VBLs served
                    lda       jstate,u  the last frame's flip has been committed now: the
                    cmpa      #3        buffer it replaced may be built into again
                    bne       f@
                    clr       jstate,u
f@                  tfr       x,d
                    subd      lastf,u
                    std       gdelta,u
                    stx       lastf,u
                    leax      batch,u
                    stx       bp,u
* the hero, if one is built: its flip goes in this frame's batch
                    lda       jstate,u
                    cmpa      #2
                    bne       g2@
                    lbsr      flip
* the camera
g2@                 ldd       k,u
                    addd      gdelta,u
                    cmpd      nfr,u
                    lblo      g4@
                    lbra      done
g4@                 std       k,u
                    lbsr      readrec
                    ldd       pcamx,u
                    lbsr      shr3
                    stb       gcol2,u
g5@                 lda       cl,u
                    cmpa      gcol2,u
                    beq       g7@
                    bhi       g6@
                    inc       cl,u      right: the new column is cl + 80
                    lda       cl,u
                    adda      #80
                    lbsr      wcol
                    bra       g5@
g6@                 dec       cl,u      left: the new column is cl
                    lda       cl,u
                    lbsr      wcol
                    bra       g5@
g7@                 ldd       pcamy,u
                    lbsr      shr3
                    stb       grow2,u
g8@                 lda       rt,u
                    cmpa      grow2,u
                    beq       g10@
                    bhi       g9@
                    inc       rt,u      down: the new row is rt + 25
                    lda       rt,u
                    adda      #25
                    lbsr      wrow
                    bra       g8@
g9@                 dec       rt,u
                    lda       rt,u
                    lbsr      wrow
                    bra       g8@
g10@                lbsr      scroll    scroll, flip and records: one batch
* the hero: if nothing is being built and the record's hero is not the one
* on the screen, start building it
                    lda       jstate,u
                    bne       cmp@
                    tst       hvis,u
                    beq       g11@
                    ldd       tx,u
                    cmpd      jx,u
                    bne       g11@
                    ldd       ty,u
                    cmpd      jy,u
                    bne       g11@
                    lda       tf,u
                    cmpa      jf,u
                    lbeq      gloop
g11@                ldd       tx,u
                    std       jx,u
                    ldd       ty,u
                    std       jy,u
                    lda       tf,u
                    sta       jf,u
                    ldd       pk,u
                    std       jk,u
                    clr       jtile,u
                    clr       jstage,u
                    lda       #SPRA     the buffer that is not on the screen
                    tst       hvis,u
                    beq       g12@
                    cmpa      hbase,u
                    bne       g12@
                    adda      #15
g12@                sta       jbase,u
                    lda       #1
                    sta       jstate,u
cmp@                lda       jstate,u  a tile of it a frame
                    cmpa      #1
                    lbne      gloop
                    lda       #10
                    sta       cnt,u
c@                  lbsr      compose1
                    dec       cnt,u
                    bne       c@
                    lbra      gloop

done                lda       #1        the screen given back
                    ldb       #SS.Excl
                    ldy       #0
                    os9       I$SetStt
                    clrb
err                 os9       F$Exit

********************************************************************
* frame - until a VBL has been served: X := VBLs served.  B is kept.
frame               pshs      b
                    lda       #1
                    ldb       #SS.FrmWait
                    os9       I$SetStt
                    puls      b,pc

* load - X = a file's name, Y = where, D = at most how many: read it.
* D := the bytes read
load                pshs      d,y
                    lda       #READ.
                    os9       I$Open
                    bcs       e@
                    ldx       2,s
                    ldy       ,s
                    pshs      a
                    os9       I$Read
                    puls      a
                    bcs       e@
                    sty       ,s
                    os9       I$Close
                    puls      d,y,pc
e@                  leas      4,s
                    leas      2,s       the caller's return: out
                    os9       F$Exit

* scroll - the batch: HSCROLL and VSCROLL to the pending camera, the two
* records, END; then SS.Batch
scroll              ldx       bp,u
                    lda       #BT.Reg
                    sta       ,x+
                    lda       #VR.HSCR
                    sta       ,x+
                    lda       pcamx+1,u
                    sta       ,x+
                    lda       #BT.Reg
                    sta       ,x+
                    lda       #VR.HSCRH
                    sta       ,x+
                    lda       pcamx,u
                    anda      #3
                    sta       ,x+
                    lda       #BT.Reg
                    sta       ,x+
                    lda       #VR.VSCR  cell mode's ring is 32 rows: VSCROLL[7:3]
                    sta       ,x+
                    lda       pcamy+1,u
                    sta       ,x+
                    lda       #BT.Reg
                    sta       ,x+
                    lda       #VR.VSCRH
                    sta       ,x+
                    clr       ,x+
                    lda       #BT.Tags
                    sta       ,x+
                    ldd       pk,u
                    std       ,x++
                    ldd       herok,u
                    std       ,x++
                    clr       ,x+
                    tfr       x,d
                    pshs      u
                    subd      ,s
                    subd      #batch
                    puls      u
                    tfr       d,y
                    lda       #1
                    ldb       #SS.Batch
                    leax      batch,u
                    os9       I$SetStt
                    lbcs      err
                    rts

* readrec - record k into pcamx, pcamy, pk and the hero target tx, ty, tf
readrec             ldd       k,u
                    lslb
                    rola
                    lslb
                    rola
                    lslb
                    rola
                    leax      tilefr,u
                    leax      d,x
                    ldd       ,x
                    std       pcamx,u
                    ldd       2,x
                    std       pcamy,u
                    lda       4,x
                    lsra
                    lsra
                    lsra
                    lsra
                    sta       tf,u
                    lda       4,x
                    anda      #$0F
                    ldb       5,x
                    std       tx,u
                    ldd       6,x
                    std       ty,u
                    ldd       k,u
                    std       pk,u
                    rts

* cellcode - A = world row, B = world column: A := the code the map should
* hold there, one of the hero's if his cells cover it, else the world's.
* B and X are kept.
cellcode            pshs      x,b
                    tst       hvis,u
                    beq       w@
                    subb      hc0,u
                    cmpb      #5
                    bhs       w@
                    pshs      a
                    suba      hr0,u
                    cmpa      #3
                    bhs       o@
                    stb       ccol,u    A = row within, B = column within
                    ldb       #5
                    mul
                    addb      ccol,u
                    addb      hbase,u
                    tfr       b,a
                    leas      1,s
                    puls      x,b,pc
o@                  puls      a
w@                  ldb       ,s        world[(row << 8) | col]
                    leax      world,u
                    leax      d,x
                    lda       ,x
                    puls      x,b,pc

* maddr - A = world row, B = world column: D := the cell's map address's
* low 16 bits, MAPBASE 124: $C000 + (row & 31) * 128 + (column & 127)
maddr               pshs      b
                    anda      #31
                    tfr       a,b
                    clra
                    lsrb                row * 128: A = row >> 1, B's bit 7 = row & 1
                    rora
                    exg       a,b
                    adda      #$C0
                    pshs      a
                    lda       1,s
                    anda      #127
                    pshs      a
                    orb       ,s+
                    puls      a
                    leas      1,s
                    rts

* vput - rec's head is set: libvid's put
vput                pshs      y
                    leax      rec,u
                    ldy       base,u
                    pshs      u
                    ldu       lvent,u
                    jsr       VL.Put,u
                    puls      u
                    puls      y,pc

* wcol - A = world column: rows rt .. rt+25 of it into the map, two pokes
* of 13
wcol                sta       gcol,u
                    lda       rt,u
                    sta       grow,u
                    bsr       w13
w13                 leax      poke,u
                    lda       #13
                    sta       gtmp,u
                    sta       ,x+
                    lda       #7
                    sta       ,x+
c@                  lda       grow,u
                    ldb       gcol,u
                    lbsr      maddr
                    std       ,x++
                    lda       grow,u
                    ldb       gcol,u
                    lbsr      cellcode
                    sta       ,x+
                    inc       grow,u
                    dec       gtmp,u
                    bne       c@
                    pshs      y,u
                    leax      poke,u
                    ldy       base,u
                    ldu       lvent,u
                    jsr       VL.Poke,u
                    puls      y,u,pc

* wrow - A = world row: columns cl .. cl+80 of it into the map, a put at
* most 16 cells long and none across the ring's column wrap
wrow                sta       grow,u
                    lda       cl,u
                    sta       gcol,u
                    lda       #81
                    sta       gtmp,u
r@                  lda       grow,u    a put from here
                    ldb       gcol,u
                    lbsr      maddr
                    std       rec+1,u
                    lda       #7
                    sta       rec,u
                    clr       rec+3,u
                    leax      rec+4,u
c@                  lda       grow,u
                    ldb       gcol,u
                    lbsr      cellcode
                    sta       ,x+
                    inc       rec+3,u
                    inc       gcol,u
                    dec       gtmp,u
                    beq       p@
                    lda       gcol,u
                    bita      #127
                    beq       p@        the ring wraps here
                    lda       rec+3,u
                    cmpa      #16
                    bne       c@
p@                  lbsr      vput
                    tst       gtmp,u
                    bne       r@
                    rts

* shr3 - D := D >> 3
shr3                lsra
                    rorb
                    lsra
                    rorb
                    lsra
                    rorb
                    rts

********************************************************************
* compose1 - one stage of building the hero's tile jtile into buffer
* jbase, demo.asm's: stage 0 the background tile (read back from VRAM),
* 1-8 a pixel row of the sprite over it, 9 out to VRAM
compose1            lda       jtile,u   i, j
                    clrb
c1@                 cmpa      #5
                    blo       c2@
                    suba      #5
                    incb
                    bra       c1@
c2@                 sta       ci,u
                    stb       cj,u
                    lda       jstage,u
                    lbne      s1@
                    ldd       jx,u      the world's code under the cell
                    lbsr      shr3
                    addb      ci,u
                    stb       ccol,u
                    ldd       jy,u
                    lbsr      shr3
                    addb      cj,u
                    tfr       b,a
                    ldb       ccol,u
                    leax      world,u
                    leax      d,x
                    lda       #4        four gets of 16
                    sta       ccol,u
                    ldb       ,x
                    lda       #64       its tile, read back: $78000 + code * 64
                    mul
                    addd      #$8000
                    leay      cbuf,u
g@                  pshs      d
                    lbsr      tget
                    leax      rec+4,u
                    lbsr      copy16
                    puls      d
                    addd      #16
                    dec       ccol,u
                    bne       g@
                    lbra      next@
s1@                 cmpa      #9
                    lbeq      s9@
                    deca                stages 1-8: a pixel row
                    sta       cpr,u
                    lda       jy+1,u    sy = j * 8 + row - (y & 7)
                    anda      #7
                    sta       ccol,u
                    lda       cj,u
                    lsla
                    lsla
                    lsla
                    adda      cpr,u
                    suba      ccol,u
                    cmpa      #16
                    lbhs      next@
                    sta       csy,u
                    lda       jf,u      the frame's row sy: frame * 512 + sy * 32
                    lsla
                    clrb
                    pshs      d
                    lda       csy,u
                    ldb       #32
                    mul
                    addd      ,s++
                    leay      sprites,u
                    leay      d,y
                    lda       cpr,u     the buffer's row
                    ldb       #8
                    mul
                    leax      cbuf,u
                    leax      d,x
                    lda       jx+1,u    sx = i * 8 - (x & 7), for column 0
                    anda      #7
                    sta       ccol,u
                    lda       ci,u
                    lsla
                    lsla
                    lsla
                    suba      ccol,u
                    clrb
p@                  cmpa      #32       0 <= sx < 32
                    bhs       q@
                    pshs      a
                    lda       a,y       A is 0-31 here
                    cmpa      #SPRKEY
                    beq       t@
                    sta       b,x
t@                  puls      a
q@                  inca
                    incb
                    cmpb      #8
                    bne       p@
                    bra       next@
s9@                 lda       #4        stage 9: out, at the tile's address, four puts of 16
                    sta       ccol,u
                    lda       jbase,u
                    adda      jtile,u
                    ldb       #64
                    mul
                    addd      #$8000
                    leax      cbuf,u
o@                  std       rec+1,u
                    pshs      d
                    leay      rec+4,u
                    bsr       copy16
                    pshs      x
                    lda       #7
                    sta       rec,u
                    lda       #16
                    sta       rec+3,u
                    lbsr      vput
                    puls      x
                    puls      d
                    addd      #16
                    dec       ccol,u
                    bne       o@
                    clr       jstage,u
                    inc       jtile,u
                    lda       jtile,u
                    cmpa      #15
                    bne       x@
                    lda       #2
                    sta       jstate,u
                    rts
next@               inc       jstage,u
x@                  rts

* tget - D = a VRAM address's low 16 bits, above $70000: its 16 bytes into
* rec+4.  Y is kept.
tget                std       rec+1,u
                    lda       #7
                    sta       rec,u
                    lda       #16
                    sta       rec+3,u
                    pshs      y,u
                    leax      rec,u
                    ldy       base,u
                    ldu       lvent,u
                    jsr       VL.Get,u
                    puls      y,u,pc

* copy16 - 16 bytes from X to Y, both moved past them
copy16              ldb       #16
c@                  lda       ,x+
                    sta       ,y+
                    decb
                    bne       c@
                    rts

********************************************************************
* flip - the built buffer into the map at the new cells, and the old cells
* given back to the world: as SS.Batch records at bp, for the next blank
flip                lda       hc0,u     the old rectangle
                    sta       ocol,u
                    lda       hr0,u
                    sta       orow,u
                    lda       hvis,u
                    sta       ohvis,u
                    ldd       jx,u
                    lbsr      shr3
                    stb       hc0,u
                    ldd       jy,u
                    lbsr      shr3
                    stb       hr0,u
                    lda       jbase,u
                    sta       hbase,u
                    sta       fcode,u
                    lda       #1
                    sta       hvis,u
* the new cells: five a row, unless the ring's column wraps inside them
                    clr       frow,u
                    lda       hc0,u
                    anda      #127
                    cmpa      #123
                    bhi       sl@
n@                  lda       #5
                    sta       gtmp,u
                    lda       hr0,u
                    adda      frow,u
                    ldb       hc0,u
                    lbsr      emit
                    inc       frow,u
                    lda       frow,u
                    cmpa      #3
                    bne       n@
                    bra       old@
sl@                 clr       fcol,u    one a cell
s2@                 lda       #1
                    sta       gtmp,u
                    lda       hr0,u
                    adda      frow,u
                    ldb       hc0,u
                    addb      fcol,u
                    lbsr      emit
                    inc       fcol,u
                    lda       fcol,u
                    cmpa      #5
                    bne       s2@
                    inc       frow,u
                    lda       frow,u
                    cmpa      #3
                    bne       sl@
* the old cells outside the new rectangle go back to the world.  The two
* moves the hero nearly always makes - a column across, or a row up or down
* - give back one edge, demo.asm's fast paths; anything else, every cell.
old@                clr       pkp,u
                    clr       pkp+1,u
                    tst       ohvis,u
                    lbeq      k@
                    lda       orow,u
                    cmpa      hr0,u
                    bne       vr@
                    lda       ocol,u    same row: one column across?
                    inca
                    cmpa      hc0,u
                    bne       l1@
                    clrb                right: the old left column
                    bra       col@
l1@                 suba      #2
                    cmpa      hc0,u
                    lbne      gen@
                    ldb       #4        left: the old right column
col@                stb       fcol,u
                    clr       frow,u
cc@                 lda       orow,u
                    adda      frow,u
                    ldb       ocol,u
                    addb      fcol,u
                    lbsr      give
                    inc       frow,u
                    lda       frow,u
                    cmpa      #3
                    bne       cc@
                    lbra      k@
vr@                 lda       ocol,u    same column: one row up or down, no ring wrap?
                    cmpa      hc0,u
                    bne       gen@
                    anda      #127
                    cmpa      #123
                    bhi       gen@
                    lda       orow,u
                    inca
                    cmpa      hr0,u
                    bne       u1@
                    clrb                down: the old top row
                    bra       row@
u1@                 suba      #2
                    cmpa      hr0,u
                    bne       gen@
                    ldb       #2        up: the old bottom row
row@                lda       orow,u    five contiguous cells, one put
                    pshs      b
                    adda      ,s+
                    sta       grow,u
                    ldb       ocol,u
                    lbsr      maddr
                    ldx       bp,u
                    pshs      d
                    lda       #BT.Put
                    sta       ,x+
                    lda       #7
                    sta       ,x+
                    puls      d
                    std       ,x++
                    lda       #5
                    sta       ,x+
                    clr       fcol,u
rc@                 pshs      x
                    lda       grow,u
                    ldb       ocol,u
                    addb      fcol,u
                    leax      world,u
                    leax      d,x
                    lda       ,x
                    puls      x
                    sta       ,x+
                    inc       fcol,u
                    lda       fcol,u
                    cmpa      #5
                    bne       rc@
                    stx       bp,u
                    lbra      k@
gen@                clr       frow,u
r@                  clr       fcol,u
c@                  lda       orow,u
                    adda      frow,u
                    suba      hr0,u
                    cmpa      #3
                    bhs       g@        the row is outside
                    lda       ocol,u
                    adda      fcol,u
                    suba      hc0,u
                    cmpa      #5
                    blo       s@        inside the new rectangle: already done
g@                  lda       orow,u
                    adda      frow,u
                    ldb       ocol,u
                    addb      fcol,u
                    bsr       give
s@                  inc       fcol,u
                    lda       fcol,u
                    cmpa      #5
                    bne       c@
                    inc       frow,u
                    lda       frow,u
                    cmpa      #3
                    bne       r@
k@                  ldd       jk,u
                    std       herok,u
                    lda       #3        not built into again until the batch is on the card
                    sta       jstate,u
                    rts

* give - A = world row, B = world column: the cell back to the world's code
* (not the ring's), as one more cell of the BT.Poke at pkp, started if pkp
* is 0
give                pshs      d,x
                    ldx       pkp,u
                    bne       a@
                    ldx       bp,u      a poke record: type, n, b18-16
                    lda       #BT.Poke
                    sta       ,x+
                    stx       pkp,u
                    clr       ,x+
                    lda       #7
                    sta       ,x+
                    stx       bp,u
                    ldx       pkp,u
a@                  inc       ,x
                    ldd       ,s
                    lbsr      maddr
                    ldx       bp,u
                    std       ,x++
                    ldd       ,s
                    pshs      x
                    leax      world,u
                    leax      d,x
                    lda       ,x
                    puls      x
                    sta       ,x+
                    stx       bp,u
                    puls      d,x,pc

* emit - A = world row, B = world column, gtmp = n, fcode = the first code:
* a BT.Put of n codes fcode, fcode+1 ... at bp, and bp past it
emit                pshs      d
                    lbsr      maddr
                    ldx       bp,u
                    pshs      d
                    lda       #BT.Put
                    sta       ,x+
                    lda       #7
                    sta       ,x+
                    puls      d
                    std       ,x++
                    ldb       gtmp,u
                    stb       ,x+
                    lda       fcode,u
c@                  sta       ,x+
                    inca
                    decb
                    bne       c@
                    sta       fcode,u
                    stx       bp,u
                    puls      d,pc

                    emod
eom                 equ       *
                    end
