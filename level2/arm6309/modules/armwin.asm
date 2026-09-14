********************************************************************
* armwin - a window device descriptor for ArmIO, the arm6309 video console
*
* Assembled once per window: -DWN=n gives /Wn, at the pseudo port address
* $FFC0+n so that IOMan gives each window its own statics (a CoCo 3's
* arrangement; ArmIO never addresses the port).  The real card bases are
* IT.VBase and IT.KBase, after the CoCo window defaults (defs/armvid.d).
*
* /W1 and /W2 open themselves at Init (IT.VAL), in fast text: /W1 80 x 25
* (VMODE 00, the 449-line family) and /W2 80 x 30 (VMODE 01, the 525-line
* family), white on black.  /W3 and up open nothing: a DWSet written to
* them makes their window.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*     1    2026/09/14  arm6309
* Plan phase P1.

                    ifp1
                    use       defsfile
                    use       armvid.d
                    endc

                    ifndef    WN
WN                  set       1
                    endc
WVAL                set       1
                    ifeq      WN-2
WSTY                set       STY.Txt30
WROWS               set       30
                    else
WSTY                set       STY.Txt25
WROWS               set       25
                    endc
                    ifge      WN-3
WVAL                set       0         /W3 up: no window until a DWSet makes one
WSTY                set       $10
                    endc

tylg                set       Devic+Objct
atrv                set       ReEnt+rev
rev                 set       $00

                    mod       eom,name,tylg,atrv,mgrnam,drvnam

                    fcb       UPDAT.    mode byte
                    fcb       HW.Page   extended controller address
                    fdb       $FFC0+WN  the pseudo port: one statics per window
                    fcb       initsize-*-1 initialization table size
                    fcb       DT.SCF    device type
                    fcb       $00       case: upper and lower
                    fcb       $01       backspace: BS, space, BS
                    fcb       $00       delete: backspace over the line
                    fcb       $01       echo
                    fcb       $01       auto line feed
                    fcb       $00       end of line null count
                    fcb       $00       no end of page pause
                    fcb       WROWS     lines per page
                    fcb       C$BSP     backspace character
                    fcb       C$DEL     delete line character
                    fcb       C$CR      end of record character
                    fcb       C$EOF     end of file character
                    fcb       C$RPRT    reprint line character
                    fcb       C$RPET    duplicate last line character
                    fcb       C$PAUS    pause character
                    fcb       C$INTR    interrupt character
                    fcb       C$QUIT    quit character
                    fcb       C$BSP     backspace echo character
                    fcb       C$BELL    line overflow character
                    fcb       $80       IT.PAR: a window device
                    fcb       $00       IT.BAU
                    fdb       name      copy of descriptor name address
                    fcb       $00       XON
                    fcb       $00       XOFF
                    fcb       80        IT.COL
                    fcb       WROWS     IT.ROW
                    fcb       WN        IT.WND
                    fcb       WVAL      IT.VAL: 1 opens the window at Init
                    fcb       WSTY      IT.STY
                    fcb       0         IT.CPX
                    fcb       0         IT.CPY
                    fcb       0         IT.FGC: CoWin's palette 0, white
                    fcb       2         IT.BGC: 2, black
                    fcb       2         IT.BDC
                    fdb       Video.Base IT.VBase
                    fdb       PS2.Base  IT.KBase
initsize            equ       *

name                fcc       /W/
                    fcb       '0+WN+$80
mgrnam              fcs       /SCF/
drvnam              fcs       /ArmIO/

                    emod
eom                 equ       *
                    end
