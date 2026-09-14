                  IFNE    ARMVID.D-1

ARMVID.D            SET       1

********************************************************************
* armvid.d - the arm6309 video console: ArmIO, CoArm, KbdArm, VidCore
*
* arm6309 docs/nitros9-av-plan.md is the plan this implements.  The card's
* register map is arm6309 video/docs/graphics.md 13; the PS/2 card's is
* io/ps2/docs/ps2.md 8.
*
*   ArmIO    SCF driver, in the system map: one statics per window device,
*            the input buffer, the VBL service (vidsvc.asm), and the calls
*            into CoArm
*   KbdArm   the PS/2 keyboard: initialisation and the /IRQ service
*   CoArm    output, in a task of its own: control codes, escapes,
*            screens, and the card through VidCore (vidcore.asm)
*
* ⭐ COARM IS NOT IN THE SYSTEM MAP (plan 3.2).  With P1's modules in the
* bootfile the system map had 15 K free after boot, and loading firqtst
* failed with E$MFull; CoArm is the module that grows.  So it is CoCo 3
* GrfDrv's arrangement, which this port's kernel already has: ArmIO loads
* CoArm with F$NMLoad (not mapped), builds software task 1's DAT image
* from its blocks and four of its own, and enters it through D.Flip1; CoArm
* returns through D.Flip0.  CoArm makes no system calls - where it must
* wait for a blank it yields, and ArmIO sleeps and resumes it.
*
* What both maps see is block 0: VG, the video globals, at VG.Addr in the
* page CoCo 3 gives GrfDrv's globals, and CoArm's stack below D.CCStk.  The
* I/O page is decoded ahead of the map, so it is in every map too.
*
* Every window device (/W1 ...) has its own pseudo port address, as on a
* CoCo 3, so IOMan gives each its own statics.  The real card bases come
* from the descriptor (IT.VBase, IT.KBase): plan 8's rule, since /IOPAGE
* may move.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P1: VidCore, the fast-text screen, the keyboard.

********************************************************************
* The video card's registers (graphics.md 13), offsets from its base
VR.CTRL             EQU       $00       b7 display, b6 VBL IRQ, b5 CELL, b4-3 WMODE, b1-0 VMODE
VR.VSCR             EQU       $01       VSCROLL, bits 7-0
VR.VSCRH            EQU       $02       VSCROLLH, bit 8
VR.HSCR             EQU       $03       HSCROLL, bits 7-0
VR.HSCRH            EQU       $04       HSCROLLH, bits 9-8
VR.SPANLEN          EQU       $05       span-solid length - 1
VR.WFG              EQU       $06
VR.WBG              EQU       $07
VR.WPTR0            EQU       $08       WPTR, little-endian: the column's low byte
VR.WPTR1            EQU       $09
VR.WPTR2            EQU       $0A       bits 18-16
VR.BCTRL            EQU       $0E       b0 GO
VR.PIDX             EQU       $10
VR.PDATL            EQU       $11       GGGBBBBB
VR.PDATH            EQU       $12       RRRRRGGG; the write commits and PIDX steps
VR.VSTAT            EQU       $13       b7 SPANBUSY b6 VBLANK b5 HBLANK b4 LRUN b0 VBL
VR.WADV             EQU       $14       00 continue, 01 next row same column
VR.VDATA            EQU       $15       VRAM at WPTR, post-increment
VR.TBASE            EQU       $17       TILEBASE, 5 bits
VR.MBASE            EQU       $19       MAPBASE, 7 bits

* CTRL
CT.Disp             EQU       %10000000
CT.VIRQ             EQU       %01000000
CT.Cell             EQU       %00100000
CT.WMode            EQU       %00011000
CT.VMode            EQU       %00000011
WM.Direct           EQU       %00000000
WM.Mask             EQU       %00001000
WM.Solid            EQU       %00010000
WM.Sprite           EQU       %00011000

* VSTAT (V.VSTAT and VSTAT.* are in arm6309.d, for the clock)
VSTAT.VBlk          EQU       %01000000

********************************************************************
* The PS/2 card (ps2.md 8), offsets from its base
PR.KDATA            EQU       0         read clears KDR
PR.MDATA            EQU       1
PR.IOSTAT           EQU       2         b0 KDR b1 MDR b2 KCLK b3 KDAT b4 MCLK b5 MDAT (1 = line low)
PR.IOCTRL           EQU       3         write-only: b0 KCLKD b1 KDATD b2 MCLKD b3 MDATD b4 KRST b5 MRST b6 IRQEN

********************************************************************
* The descriptor's window defaults are scf.d's CoCo window additions
* (IT.WND .. IT.BDC, with the size in IT.COL/IT.ROW), then the bases
                    ORG       IT.BDC+1
IT.VBase            RMB       2         video card base address
IT.KBase            RMB       2         PS/2 card base address

* Screen types (plan 5.1)
STY.Txt25           EQU       $18       fast text 80x25, VMODE 00, cell mode
STY.Txt30           EQU       $19       fast text 80x30, VMODE 01, cell mode
STY.Tile25          EQU       $1C       tiles 640x200, VMODE 00, cell mode (exclusive-oriented)
STY.Tile30          EQU       $1D       tiles 640x240, VMODE 01, cell mode
TL.TBank            EQU       30        a tile screen's TILEBASE when displayed: ring rows 480-495
TL.MBase            EQU       124       and its MAPBASE: rows 496-499, the 32-row map ring

WinMax              EQU       16        window devices: /W1 .. /W15 (0 is unused)

********************************************************************
* VG - the video globals, in block 0 (seen by both maps).  D.VBLSt points
* at them while the console is up; the clock calls VG.Svc on every VBL.
VG.Addr             EQU       $1100     CoCo 3's GrfDrv globals page: nothing here uses it
                    ORG       0
VG.Svc              RMB       2         VBL service: clock does jsr [,x] with X = VG
VG.Idle             RMB       2         idle work: the kernel's idle loop does jsr [2,x]
* the frame words, at a fixed place (VG.Addr+4) for a test harness to read:
* the emulator's MARKS=1104 records them with every frame
VG.MkCk             RMB       2         0: the console has no checkpoints
VG.MkPh             RMB       2         the tag + 1 of the list the service started this frame, or 0
VG.MkCam            RMB       2         SS.Batch's two tags, as the last batch committed them
VG.MkHero           RMB       2
VG.MkMiss           RMB       2         batches that waited a blank for a busy one
VG.Base             RMB       2         video card base
VG.KBase            RMB       2         PS/2 card base
VG.Users            RMB       1         ArmIO devices initialised
VG.KbEnt            RMB       2         KbdArm's entry table
VG.KbMod            RMB       2
VG.CurDev           RMB       2         statics of the displayed window: the keyboard's
VG.WinDev           RMB       WinMax*2  each window number's statics
* CoArm, the task (ArmIO sets up, CoArm reads)
VG.CoEnt            RMB       2         CoArm's entry, in its task's map
VG.CoImg            RMB       16        software task 1's DAT image
VG.CoBlk            RMB       2         the first of CoArm's data blocks (F$AllRAM)
VG.OldImg           RMB       2         D.TskIPt's task 1 entry before ArmIO took it
* a call into CoArm: ArmIO fills, CoArm answers
VG.CFn              RMB       1         CF.* below
VG.CWin             RMB       1         the window
VG.CA               RMB       1         arguments in, answers out
VG.CB               RMB       1
VG.CX               RMB       2
VG.CY               RMB       2
VG.CErr             RMB       1         0, or an error code
VG.CWait            RMB       1         CoArm yielded: 1 until the batch is empty, 2 until a VBL
VG.CBusy            RMB       1         a call is in progress (it may be sleeping)
VG.CSel             RMB       1         the window CoArm last displayed, for the keyboard
VG.CParm            RMB       8         CF.Init: STY CPX CPY SZX SZY PRN1 PRN2 PRN3
VG.SysStk           RMB       2         the system stack while CoArm runs
VG.SysCC            RMB       1
* the card's shadows (V4: the register file reads back, but not safely under a span)
VG.Ctrl             RMB       1         CTRL as last written, WMODE included
VG.VScr             RMB       2         VSCROLL as last written, hi lo
VG.HScr             RMB       2
VG.WFG              RMB       1
VG.WBG              RMB       1
VG.WAdv             RMB       1
VG.SpLen            RMB       1
VG.TBase            RMB       1
VG.MBase            RMB       1
VG.IOCtl            RMB       1         the PS/2 card's IOCTRL (write-only)
VG.KbFlag           RMB       1         KbdArm: prefixes and modifiers
VG.KbSkip           RMB       1         KbdArm: bytes of Pause still to swallow
VG.KbTmp            RMB       1         KbdArm: scratch, Init only
VG.KbBuf            RMB       10        KbdArm: a frame's ten IOCTRL values
VG.KbPort           RMB       1         KbdArm: the port being talked to, 0 or 1
VG.KbDat            RMB       1         and its IOCTRL and IOSTAT bits
VG.KbClk            RMB       1
VG.KbSDat           RMB       1
VG.KbSClk           RMB       1
* WPTR (V3): where the main line loaded it, and the writes since
VG.Ptr              RMB       3         bits 18-16, 15-8, 7-0
VG.PtrN             RMB       2         VDATA writes since VG.Ptr was loaded
VG.PtrGen           RMB       1         bumped by the service each time it uses WPTR
VG.PtrSeen          RMB       1         the generation VG.Ptr was loaded in
* a stream in progress (VcPutN, VcFillN): CoArm is not re-entered
VG.SCnt             RMB       2
VG.SByte            RMB       1
VG.SFill            RMB       1
* the frame batch (plan 3.4 step 4): CoArm queues, the VBL service commits
VG.BFlag            RMB       1         BF.* below
VG.BCtrl            RMB       1         CTRL without WMODE
VG.BVScr            RMB       2
VG.BHScr            RMB       2
VG.BTBase           RMB       1
VG.BMBase           RMB       1
VG.PalLo            RMB       1         the palette entries still to commit: PalN from PalLo
VG.PalN             RMB       2
* the pointer (vidptr.asm), drawn on the displayed bitmap screen
VG.PtrOn            RMB       1         GCSet chose one
VG.PtrVis           RMB       1         it is on the card
VG.PtrBusy          RMB       1         ArmIO is moving it (not re-entered from the IRQ)
VG.PtrX             RMB       2         where it is to be: the mouse, or PutGC
VG.PtrY             RMB       2
VG.PtrDX            RMB       2         where it is drawn
VG.PtrDY            RMB       2
VG.PtrCX            RMB       2         a column being written
VG.PtrH             RMB       1         the rows of it on the screen
VG.PtrI             RMB       1
VG.DBit             RMB       1         the displayed screen is a bitmap
VG.DTop             RMB       2         its ring row of row 0
VG.DH               RMB       2         its height
VG.PtrSave          RMB       256       the pixels under it
* the mouse (KbdArm)
VG.MsX              RMB       2
VG.MsY              RMB       2
VG.MsBtn            RMB       1         b0 left, b1 right, b2 middle
VG.MsIdx            RMB       1         the byte of a packet next
VG.MsB0             RMB       1
VG.MsB1             RMB       1
VG.MsPkt            RMB       32        SS.Mouse's packet (cocovtio.d's Pt.*)
* counters
VG.Frames           RMB       2         VBLs served
VG.LRunV            RMB       2         VBLs that found a display list still running
VG.PalCar           RMB       2         VBLs whose palette commit carried to the next
VG.Pal              RMB       512       the displayed palette, RGB565 hi lo
* display lists (SS.Raster): CoArm composes one, the VBL service starts it
VG.LOn              RMB       1         start the list at VG.LRow each frame
VG.LScr             RMB       1         the screen it belongs to, + 1
VG.DScr             RMB       1         the displayed screen, + 1 (CoArm's CG.Disp)
VG.LRow             RMB       2         the ring row it is in
VG.LTag             RMB       2         its tag + 1, for VG.MkPh
VG.LAlt             RMB       1         which of the two list rows is composed next
VG.LLate            RMB       2         VBLs served too late in the blank to start it
* frame signals (SS.FrmSig)
VG.FSPID            RMB       1         the process, or 0
VG.FSSig            RMB       1         the signal
VG.FSN              RMB       1         every n frames
VG.FSC              RMB       1         frames to the next
* a status call's table, moved from the caller (SS.Raster, SS.MapWr)
VG.XBuf             RMB       RT.Max
* the exclusive screen (SS.Excl)
VG.XScr             RMB       1         the claimed screen + 1, or 0
VG.XPID             RMB       1         the process that claimed it
VG.XPtr             RMB       1         VG.PtrOn before the claim
VG.CPID             RMB       1         the process making the call in progress (ArmIO's ToCo)
* SS.Batch: the next VBL commits it
VG.BtOn             RMB       1         a batch is waiting for the VBL
VG.XEnd             RMB       2         ArmIO's scratch, under VG.CBusy (vidxcl.asm)
VG.XRow             RMB       1
VG.XCol             RMB       1
VG.XLeft            RMB       1
VG.XRows            RMB       1
VG.XN               RMB       1
VG.BtCtl            RMB       1         the service's: CTRL and WADV as it found them
VG.BtAdv            RMB       1
VG.BtBuf            RMB       BT.Max+1
VG.Size             EQU       .

* SS.Raster's table.  Lines are the card's scanlines, so a row of a
* line-doubled screen is two.  The list is y0 WAITs, then for each entry its
* MOVEs and `lines` WAITs, then the register put back and END: it must fit a
* ring row, 1,024 bytes.
RT.Kind             EQU       0         0 HSCROLL, 1 a palette entry
RT.Lines            EQU       1         scanlines each entry holds, 1-255
RT.Y0               EQU       2         the scanline of the first entry
RT.N                EQU       4         entries
RT.Idx              EQU       6         the palette entry (kind 1)
RT.Tag              EQU       8         any word: VG.MkPh is it + 1 while this list runs
RT.Tab              EQU       10        N words: HSCROLL 0-1023, or RGB565
RT.MaxN             EQU       256
RT.Max              EQU       RT.Tab+2*RT.MaxN

* SS.Batch's records: what one VBL commits, in order, after the frame
* batch's own.  A batch is at most BT.Max bytes, and ends with BT.End.
BT.End              EQU       0
BT.Reg              EQU       1         r v: register r := v - VSCROLL, VSCROLLH, HSCROLL, HSCROLLH, TILEBASE, MAPBASE
BT.Put              EQU       2         b18-16 b15-8 b7-0 n, n bytes: WPTR := the address, n bytes to VDATA
BT.Tags             EQU       3         cam hero: two words for VG.MkCam and VG.MkHero
BT.Poke             EQU       4         n b18-16, n x (b15-8 b7-0 v): a byte at each of n addresses in one 64 K
BT.Max              EQU       256

* a side of a polygon being filled (ca_ext.asm PEdge)
PE.P                EQU       0         the edge's first vertex
PE.N                EQU       2         vertices from it to the chain's end
PE.YB               EQU       4         the line the edge ends on
PE.X8               EQU       6         x, 16.8
PE.St               EQU       9         its step a line, 16.8, signed
PE.Len              EQU       12

* SS.MapWr's rectangle
MW.Col              EQU       0         the map's column (the ring's 128 wrap)
MW.Row              EQU       1         and row (its 32)
MW.W                EQU       2
MW.H                EQU       3
MW.Codes            EQU       4         W x H codes, row by row

BF.VScr             EQU       %00000001
BF.HScr             EQU       %00000010
BF.Ctrl             EQU       %00000100
BF.TBase            EQU       %00001000
BF.MBase            EQU       %00010000
BF.Pal              EQU       %00100000

* CoArm's calls (VG.CFn)
CF.Boot             EQU       0         once, after the task is built: CoArm's own globals
CF.Init             EQU       1         a window: VG.CWin, VG.CA = IT.VAL, VG.CParm
CF.Write            EQU       2         VG.CA = the byte
CF.GetStt           EQU       3         VG.CA = the code; VG.CB/CX/CY hold the caller's B X Y
CF.SetStt           EQU       4
CF.Term             EQU       5
CF.Resume           EQU       6         what CoArm yielded for is done: carry on

* What CoArm yields for (VG.CWait)
CW.Batch            EQU       1         the frame batch to reach the card
CW.Frame            EQU       2         a VBL to be served
CW.Alloc            EQU       3         VG.CB blocks: VG.CX := the first, VG.CErr
CW.Free             EQU       4         VG.CB blocks from VG.CX

* CoArm's task map: block 0, its code, its data, two block windows, the kernel
Co.Code             EQU       $2000     slots 1-2: CoArm (up to 16 K)
Co.Data             EQU       $6000     slots 3-4: two blocks of ArmIO's
Co.DBlks            EQU       2
Co.WinA             EQU       $A000     slot 5: a block of CoArm's choosing (sources)
Co.WinB             EQU       $C000     slot 6: another (screen stores)
Co.Stack            EQU       $1F00     in block 0, under the flip's frame at D.CCStk

********************************************************************
* The ArmIO device statics: SCF's, then ours
                    ORG       V.SCF
V.WinNum            RMB       1         IT.WND
V.SSigID            RMB       1         data ready signal: process
V.SSigSg            RMB       1         and signal
V.InPtr             RMB       1         next byte to read from V.InBuf
V.EndPtr            RMB       1         next byte the keyboard stores
V.InBuf             RMB       128       the keyboard ring
V.ArmSiz            EQU       .

********************************************************************
* CoArm's windows.  A device window (DWSet) and an overlay (OWSet) share
* the layout; every pixel figure is in screen pixels.
WinDev              EQU       WinMax    device windows 1-15: CG.Win's first WinMax entries
WinOvl              EQU       16        overlay windows, after them
                    ORG       0
WT.Used             RMB       1
WT.Scr              RMB       1         the screen's number
WT.Par              RMB       1         an overlay's parent (the window it covers), or $FF
WT.Cur              RMB       1         a device: the window its bytes go to (itself, or its top overlay)
WT.X                RMB       2         the window: DWSet's or OWSet's rectangle
WT.Y                RMB       2
WT.W                RMB       2
WT.H                RMB       2
WT.AX               RMB       2         the working area (CWArea)
WT.AY               RMB       2
WT.AW               RMB       2
WT.AH               RMB       2
WT.CX               RMB       1         the text cursor, in cells of the working area
WT.CY               RMB       1
WT.FG               RMB       1
WT.BG               RMB       1
WT.Attr             RMB       1         WA.* below
WT.PX               RMB       2         the draw pointer, working-area pixels
WT.PY               RMB       2
WT.Pat              RMB       1         the pattern's GP buffer entry + 1, or 0
WT.Logic            RMB       1         LSet: 0 none, 1 AND, 2 OR, 3 XOR
WT.Font             RMB       1         the font's GP buffer entry + 1, or 0: the built-in
WT.SvBlk            RMB       2         an overlay's save-behind: first block ...
WT.SvN              RMB       1         ... and how many, or 0
* the parser (a device window's)
WT.EscVct           RMB       2         where the next byte goes
WT.PrmCnt           RMB       1         parameter bytes still to collect
WT.PrmPtr           RMB       2         where the next one goes
WT.PrmFn            RMB       2         the routine that runs when they are in
WT.Parms            RMB       16
WT.Skip             RMB       2         data bytes a sequence still has to take (GPLoad)
WT.P8               RMB       1         the PatDef pattern + 1, or 0 (ca_ext.asm)
WT.Ansi             RMB       1         a device in ANSI mode (AnsiSw)
WT.AnSt             RMB       1         0 text, 1 after ESC, 2 in a CSI
WT.AnN              RMB       1         the CSI parameter being read
WT.AnP              RMB       4         its parameters
WT.AnFg             RMB       1         SGR's colours, 0-7, and bold
WT.AnBg             RMB       1
WT.AnBold           RMB       1
WT.Poly             RMB       64        Poly's vertices, as they arrive
WT.Size             EQU       .

WA.Rev              EQU       %00000001 reverse video
WA.Cur              EQU       %00000010 the cursor is enabled
WA.CurOn            EQU       %00000100 the cursor is drawn
WA.Trans            EQU       %00001000 TCharSw: transparent text
WA.Bold             EQU       %00010000 BoldSw
WA.Undl             EQU       %00100000 underline

********************************************************************
* CoArm's screens (fixed records, by number)
ScrMax              EQU       8
SH.Rows             EQU       32        a fast-text map ring's cell rows (graphics.md 6.4.6)
SH.Cols             EQU       80
                    ORG       0
SC.Used             RMB       1
SC.Type             RMB       1         STY
SC.VMode            RMB       1
SC.W                RMB       2         pixels
SC.H                RMB       2
SC.Cols             RMB       1         cells
SC.Rows             RMB       1
SC.Top              RMB       2         the card's ring row of screen row 0, while displayed
SC.StBlk            RMB       2         bitmap: the store (640 x H in blocks), used while not displayed
SC.StN              RMB       1         fast text: the shadow's one block
SC.Wins             RMB       1         windows on it
SC.Pal              RMB       512       its palette
* fast text: the screen is its one window's
SC.TFG              RMB       1         the colour pair the screen is in
SC.TBG              RMB       1
SC.TTop             RMB       1         the ring row of text row 0
SC.Size             EQU       .

* The fast-text VRAM layout: one screen is displayed at a time
TX.TBank            EQU       1         TILEBASE: glyphs at $04000-$07FFF
TX.MBase            EQU       0         MAPBASE: the map at $00000-$00FFF

********************************************************************
* CoArm's GP buffers
GPMax               EQU       48
                    ORG       0
GB.Grp              RMB       1         0: the entry is free
GB.Buf              RMB       1
GB.Sty              RMB       1         GPLoad's type: $10-$13 are 8bpp, 5 is 1bpp
GB.XS               RMB       2
GB.YS               RMB       2
GB.Size             RMB       2         bytes
GB.Blk              RMB       2         the data's first block
GB.NBlk             RMB       1
GB.Len              EQU       .

********************************************************************
* CoArm's globals, at Co.Data in its own map
                    ORG       0
CG.YieldS           RMB       2         S where CoArm yielded
CG.Dev              RMB       2         the device window this call is for
CG.CurS             RMB       2         the current window's screen record, as Cur found it
CG.PtrHid           RMB       1         the pointer was taken off for this call's drawing
CG.SPtr             RMB       2         a screen record, held across a loop
CG.WPtr             RMB       2         a window record, likewise
CG.FH               RMB       2         FillRect: rows
CG.BBlk             RMB       2         a block stream at Co.WinA: its block ...
CG.BPtr             RMB       2         ... and where in the window it has got to
CG.Disp             RMB       1         the displayed screen's number + 1, or 0
CG.FontFG           RMB       1         the colour pair the tile bank holds glyphs in
CG.FontBG           RMB       1         (FG = BG: no bank built)
CG.TxN              RMB       1         fast text: cells in a card write
CG.Tmp              RMB       2
CG.Buf              RMB       128
CG.WinA             RMB       2         the block at Co.WinA, or $FFFF
CG.WinB             RMB       2         at Co.WinB
* the row layer (ca_row.asm)
CG.TStr             RMB       2         the target: 0 the card, else a store's first block
CG.TTop             RMB       2         the card's ring row of screen row 0
CG.RY               RMB       2
CG.RX               RMB       2
CG.RN               RMB       2
CG.MFg              RMB       1
CG.MBg              RMB       1
CG.MTr              RMB       1
CG.Off              RMB       3
CG.DBlk             RMB       2
* drawing (ca_draw.asm): a window's clip, in screen pixels, inclusive
CG.CX0              RMB       2
CG.CY0              RMB       2
CG.CX1              RMB       2
CG.CY1              RMB       2
CG.OX               RMB       2         working-area origin
CG.OY               RMB       2
CG.Colour           RMB       1
CG.SY               RMB       2         a span, screen pixels, before clipping
CG.SX0              RMB       2
CG.SX1              RMB       2
CG.L                RMB       8         a line's ends, or a box's corners
CG.LDx              RMB       2         Bresenham
CG.LDy              RMB       2
CG.LSx              RMB       2
CG.LSy              RMB       2
CG.LErr             RMB       2
CG.LE2              RMB       2
CG.Move             RMB       1         LineM
CG.Rel              RMB       1         the R- forms
CG.RunOn            RMB       1         Plot's run (CG.SY, SX0, SX1) is open
CG.PlX              RMB       2
CG.PlY              RMB       2
CG.ERx              RMB       2         ellipses
CG.ERy              RMB       2
CG.ECx              RMB       2
CG.ECy              RMB       2
CG.EDy              RMB       2
CG.EAdy             RMB       2
CG.EW               RMB       2
CG.EK               RMB       2
CG.EX               RMB       2
CG.EX1              RMB       2
CG.ESy              RMB       2
CG.Fill             RMB       1
CG.Arc              RMB       1
CG.Ma               RMB       2         arithmetic
CG.Mb               RMB       2
CG.Dv               RMB       2
CG.Rm               RMB       2
CG.Q                RMB       4
CG.Q2               RMB       4
CG.Q3               RMB       4
CG.Neg              RMB       1
CG.FTgt             RMB       1         FFill: the colour being filled
CG.FIn              RMB       1         in a run of it
CG.PatW             RMB       2         a pattern's width, up to 128
CG.Cnt              RMB       2
CG.FStk             RMB       2         FFill's stack pointer
CG.GP               RMB       2         GPLoad's write pointer: the entry
CG.GPOff            RMB       2         and the bytes so far
CG.Row              RMB       640       a row of pixels
CG.FSt              RMB       600       FFill's seeds: 150 of (x, y)
CG.Scr              RMB       ScrMax*SC.Size the screens
CG.Win              RMB       (WinDev+WinOvl)*WT.Size the windows
CG.GPB              RMB       GPMax*GB.Len the GP buffers
CG.LBuf             RMB       1024      a display list being composed (ca_list.asm)
CG.Pats             RMB       256       PatDef's 32 patterns
CG.PYE              RMB       2         PatBar's and Poly's last row
CG.PLE              RMB       PE.Len    Poly's left side
CG.PRE              RMB       PE.Len    and its right
CG.Size             EQU       .

* KbdArm's entry table
Kb.Init             EQU       0         U = VG
Kb.Term             EQU       3

                  ENDC
