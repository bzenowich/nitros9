# Introduction to NitrOS-9

A tour of this repository for someone who has never worked on it: what the
operating system is, how the source tree is arranged, and where each capability
actually lives.

This document is orientation, not specification. It points at the files that are
authoritative. When this text and the source disagree, the source is right.

---

## Contents

1. [Overview](#1-overview)
2. [First concepts: modules, service calls, the I/O stack](#2-first-concepts-modules-service-calls-the-io-stack)
3. [Levels 1, 2 and 3](#3-levels-1-2-and-3)
4. [Filesystem](#4-filesystem)
5. [Boot process](#5-boot-process)
6. [Commands](#6-commands)
7. [Supported hardware](#7-supported-hardware)
8. [Libraries and modules](#8-libraries-and-modules)
9. [Graphics](#9-graphics)
10. [Wildbits](#10-wildbits)
11. [Networking and DriveWire](#11-networking-and-drivewire)
12. [Building: recipes, bootlists, toolchain](#12-building-recipes-bootlists-toolchain)
13. [Source conventions and tooling](#13-source-conventions-and-tooling)
14. [Where to look for what](#14-where-to-look-for-what)
15. [Glossary](#15-glossary)

---

## 1. Overview

NitrOS-9 is a community-maintained continuation of **Microware OS-9** for the
Motorola 6809 and Hitachi 6309 processors. OS-9 was a genuine multi-user,
multitasking, ROM-able operating system from 1979-80, built around position
independent relocatable *memory modules*. The Tandy Color Computer shipped it as
"OS-9 Level One" and later "OS-9 Level Two"; NitrOS-9 picked up that lineage,
added 6309 native-mode support, fixed decades of bugs, and ported the system to
machines Microware never saw.

What you get on a booted system: preemptive multitasking with priorities and
time slicing, per-process memory, a hierarchical filesystem with owners and
permissions, device independence through file managers and drivers, pipes,
signals, a Unix-ish shell, and — on Level 2 — a full bitmap windowing system with
fonts, patterns, drawing primitives and mouse support.

Almost everything here is **6809/6309 assembly language**, assembled with
`lwasm` from LWTOOLS. There are roughly 800 assembly sources across the
maintained tree. A few utilities are BASIC09 (`.b09`) or built through the
RMA/RLINK-style `.as` object path.

Three ideas explain most of the layout:

- **Everything is a module.** The kernel, every driver, every command, every
  font, every disk descriptor is an OS-9 memory module with a standard header.
  Modules are relocatable, re-entrant and shareable; two processes running
  `shell` share one copy in memory.
- **Levels are memory models.** Level 1 is a flat 64 KB machine. Level 2 adds
  a memory management unit so each process gets its own 64 KB view. Level 3 was
  an experiment to go further. Almost all source is shared between levels with
  `ifeq Level-1` conditionals.
- **Source is separate from product.** `level1/`, `level2/`, `defs/` and `lib/`
  hold source. `recipes/` holds the makefiles that select modules, assemble
  them, and lay out a bootable disk image or ROM. You build recipes, not the
  source tree.

### Repository map

```text
defs/        shared assembler definition files (.d) - the system's header files
level1/      Level 1 source: shared cmds/, modules/, sys/, plus one dir per port
level2/      Level 2 source, same shape
level3/      experimental Level 3 (not built, not in CI)
lib/         reusable linkable libraries (alib, net, per-platform syscall glue)
recipes/     the supported builds: one directory per product image
scripts/     formatter, pre-commit hook, disassemblers, GDB helpers
archive/     historical and unsupported material; nothing here is built
docs/        repository layout and the supported-port matrix
```

Within a level, the pattern is consistent:

| Directory | Holds |
| --- | --- |
| `cmds/` | commands shared by every port at that level |
| `modules/` | kernels, file managers, drivers, descriptors shared by ports |
| `modules/kernel/` | the kernel and its per-service-call source files |
| `sys/` | system data files: help text, fonts, patterns, message catalogs |
| `<port>/` | `port.mak`, `defsfile`, port-only `modules/`, `cmds/`, `bootlists/`, `startup` |

---

## 2. First concepts: modules, service calls, the I/O stack

### The memory module

Every OS-9 object begins with a module header (`defs/os9.d`, "Module
Definitions"):

```text
$87 $CD      sync bytes (M$ID1/M$ID2)
M$Size       module size
M$Name       offset to the module's name string
M$Type       type nibble | language nibble
M$Revs       attributes nibble | revision nibble
M$Parity     header parity
```

followed by a CRC over the whole module. In source this is all produced by the
`mod` pseudo-op; look at the top of nearly any `.asm` file:

```asm
tylg     set   Prgrm+Objct
atrv     set   ReEnt+rev
         mod   eom,name,tylg,atrv,start,size
name     fcs   /WCreate/
         fcb   edition
```

Module **types**: `Devic` (device descriptor), `Drivr` (device driver), `FlMgr`
(file manager), `Systm` (system module), `Data`, `Multi`, `Sbrtn` (subroutine
module), `Prgrm` (program), and NitrOS-9's `ShellSub`. **Languages**: `Objct`
(6809 object code), `Obj6309` (6309 object code), `ICode` (BASIC09), plus P-code,
C, Cobol and Fortran codes inherited from Microware. **Attributes**: `ReEnt`
(re-entrant/shareable) and `ModNat` (6309 native mode).

Because modules are self-describing, "merging" modules is literally
concatenation. The build does exactly that — `cat` — to make the bootfile, to
make the multi-module `shell`, and to make `utilpak1`.

### Service calls

The kernel exposes two families, both invoked via the `os9` macro (an `SWI2`
plus an opcode byte). The full list is in `defs/os9.d`.

- **`F$xxxx`, opcodes `$00-$7F` — function/system calls.**
  `F$Link`, `F$Load`, `F$UnLink`, `F$Fork`, `F$Wait`, `F$Chain`, `F$Exit`,
  `F$Mem`, `F$Send`, `F$Icpt`, `F$Sleep`, `F$ID`, `F$SPrior`, `F$PErr`,
  `F$PrsNam`, `F$CmpNam`, `F$SchBit`/`F$AllBit`/`F$DelBit`, `F$Time`, `F$STime`,
  `F$CRC`.
  Level 2 adds the memory-mapping family: `F$GPrDsc`, `F$GBlkMp`, `F$GModDr`,
  `F$CpyMem`, `F$SUser`, `F$UnLoad`, `F$Alarm`, `F$NMLink`/`F$NMLoad`,
  `F$AllRAM`, `F$AllImg`/`F$DelImg`, `F$SetImg`, `F$AllTsk`/`F$DelTsk`,
  `F$SetTsk`, `F$DATLog`, `F$LDAXY`/`F$LDDDXY`/`F$LDABX`/`F$STABX`,
  `F$MapBlk`, `F$ClrBlk`, `F$AlHRAM`, and the NitrOS-9 additions `F$ReBoot`,
  `F$CRCMod`, `F$XTime`, `F$VBlock`.
  `F$Debug` drops the machine into the debugger.
- **`I$xxxx`, opcodes `$80-$91` — I/O calls.**
  `I$Attach`, `I$Detach`, `I$Dup`, `I$Create`, `I$Open`, `I$MakDir`, `I$ChgDir`,
  `I$Delete`, `I$Seek`, `I$Read`, `I$Write`, `I$ReadLn`, `I$WritLn`,
  `I$GetStt`, `I$SetStt`, `I$Close`, `I$DeletX`, `I$ModDsc`.

`I$GetStt`/`I$SetStt` are the escape hatch: a large `SS.xxxx` code space
(`defs/os9.d`) carries everything from `SS.Ready` and `SS.Size` to
`SS.ScSiz`, `SS.Mouse`, `SS.Joy`, `SS.Palet` and `SS.DScrn`. Ports add their own
in the port defs file — see `SS.FntLoadM`, `SS.SOLIRQ` in `defs/wildbits.d`.

### The four-layer I/O stack

```text
       application
            |  I$Open / I$Read / I$SetStt ...
         IOMan                       level1/modules/ioman.asm
            |
      file manager      RBF / SCF / PipeMan / RFM
            |
      device driver     rb1773, rbdw, vtio, sc6551, piper, ...
            |
    device descriptor   d0.dd, term.dt, w1.dw, pipe.dd, ...
```

A **device descriptor** is a small data module that names its file manager and
driver and carries the port address plus an initialization table — for RBF, the
drive geometry (`IT.DRV`, `IT.STP`, `IT.CYL`, `IT.SID`, `IT.SCT` …, see
`defs/rbf.d`); for SCF, the terminal defaults (echo, auto-LF, page length,
edit keys). This is why the same `rb1773.dr` driver serves `d0_35s`,
`d0_40d` and `d0_80d`: only the descriptor differs, and the build generates them
by re-assembling one source with different `-D` flags.

The naming convention used through the recipes and bootlists is worth learning:
`.mn` = file **man**ager, `.dr` = **dr**iver, `.dd` = **d**evice **d**escriptor,
`.dt` = **t**erminal descriptor, `.dw` = **w**indow descriptor, `.sb` =
**s**u**b**routine module, `.io` = I/O subroutine (co-)module.

---

## 3. Levels 1, 2 and 3

### Level 1

A flat 64 KB address space, no memory management hardware required. All
processes and the OS share the one map; process memory is carved out of that
single 64 KB. The kernel is compact and the system boots on unexpanded or
lightly expanded machines.

- Source: `level1/`. Kernel in `level1/modules/kernel/` (`krn.asm`, `krnp2.asm`,
  plus one file per service call — `ffork.asm`, `flink.asm`, `fsleep.asm`, …).
- What it offers: multitasking, RBF/SCF/PipeMan, the full standard command set,
  the enhanced shell, and — through the VTIO "CO-module" scheme — text consoles
  from 32×16 VDG up to 80-column hardware text and 51×24/42×24 hi-res graphics
  text.
- What it does not offer: the Level 2 windowing system, per-process address
  spaces, or memory beyond 64 KB (RAM disks aside).
- `Bt.Start` is `$EE00` on the CoCo (`defs/coco.d`).

### Level 2

Requires a memory management unit — the GIME on the CoCo 3, an equivalent MMU on
the other Level 2 targets. Physical memory is divided into 8 KB blocks; a
**DAT** (Dynamic Address Translator) image of 8 block registers defines each
task's 64 KB view (`DAT.BlCt`, `DAT.BlSz`, `DAT.Regs` in the port defs).

- Source: `level2/`, which layers on top of `level1/` — the Level 2 recipes put
  both `level1` and `level2` directories on the assembler's `vpath`, so a module
  that exists only in `level1/modules` is used unchanged at Level 2.
- What it adds over Level 1:
  - Per-process address spaces. Each task still sees 64 KB, but the physical
    memory behind it is limited only by the block map: `DAT.BlMx`/`DAT.BMSz` in
    the port defs set it to 64 blocks (512 KB) on the CoCo 3 and Wildbits, and
    considerably more on newer ports (arm6309 uses 16-bit block numbers for an
    8 MB map).
  - The mapping service calls listed above, and the ability to move data between
    maps (`F$Move`, `F$CpyMem`, `F$LDABX`/`F$STABX`).
  - The **window system**: multiple screens and up to 32 windows, graphics
    primitives, fonts, patterns, get/put buffers. See [Graphics](#9-graphics).
  - Memory protection groundwork, `F$SUser` for user IDs, named pipes
    (`level2/modules/pipeman_named.asm`).
  - Optional kernel add-ons merged into the bootfile: `krnp3_perr` (printerr
    from the kernel) and `krnp4_regdump` (`F$RegDmp`).
  - A 6309 native-mode kernel and a 6309 native `RBF`/`GrfDrv` when built with
    `-DH6309=1`.
- `Bt.Start` is `$ED00`, the kernel lives at `$F000` on the CoCo 3
  (`Where` in `level2/modules/kernel/krn.asm`; `$EE00` on Wildbits, `$EC00` on
  Pico-Thing and arm6309).

### Level 3

Experimental, historical, **not built and not in CI**. The idea (see
`level3/ReadMe.l3` and `level3/Level3.doc`): file managers and their local memory
are mapped in and out of the system map dynamically, so SCF and RBF never occupy
the system map at the same time, relieving Level 2's chronic system-map
pressure. `$2000-$3FFF` becomes "file manager local memory", swapped on every
system call and IRQ; IOMan intercepts `F$SRqMem`/`F$SRtMem` and satisfies
requests originating from that region out of local memory. The ReadMe notes
known limits — CC3IO and WindInt cannot live in local memory because they are
reached through `D.AltIRQ`.

Retained for study. `level3/` contains little more than a kernel defsfile,
`sfree.asm`, bootlists and setup scripts.

---

## 4. Filesystem

### RBF — the Random Block File Manager

RBF is the disk filesystem: `level1/modules/rbf.asm`, `level2/modules/rbf.asm`
and the 6309 native `level2/modules/rbf2.asm`. Its on-disk structures are
declared in `defs/rbf.d`.

**LSN 0 — the identification sector.** Sector 0 of every RBF volume:

| Field | Size | Meaning |
| --- | --- | --- |
| `DD.TOT` | 3 | total sectors on the volume |
| `DD.TKS` | 1 | track size in sectors |
| `DD.MAP` | 2 | bytes in the allocation bitmap |
| `DD.BIT` | 2 | sectors per bitmap bit (the cluster size) |
| `DD.DIR` | 3 | LSN of the root directory's file descriptor |
| `DD.OWN` | 2 | owner |
| `DD.ATT` | 1 | attributes |
| `DD.DSK` | 2 | disk ID |
| `DD.FMT` | 1 | sides / density / track density |
| `DD.SPT` | 2 | sectors per track |
| `DD.BT` | 3 | LSN of the bootstrap file |
| `DD.BSZ` | 2 | size of the bootstrap file |
| `DD.DAT` | 5 | creation date |
| `DD.NAM` | 32 | volume name |
| `DD.OPT` | 32 | option area (a copy of descriptor defaults) |

`DD.BT`/`DD.BSZ` are what `os9gen` and `cobbler` write: they tell the boot code
where `OS9Boot` lives, with no directory lookup needed.

**File descriptors.** Every file has a one-sector FD: `FD.ATT` attributes,
`FD.OWN` owner, `FD.DAT` modified date, `FD.LNK` link count, `FD.SIZ` 4-byte
size, `FD.Creat` creation date, then a **segment list** of (3-byte starting
LSN, 2-byte length) pairs. Files are extent-based, not FAT- or inode-chained,
which is why fragmentation matters and why `DD.BIT`/`IT.SAS` (segment allocation
size) tuning shows up in every descriptor.

**Directories** are ordinary files whose records are 32 bytes: 29 bytes of name
(last character has the high bit set) plus a 3-byte FD pointer. A deleted entry
has a zero first byte — which is what makes RBF's un-delete patch possible
(`level2/modules/rbf2.asm`).

**Attributes and ownership.** Directory bit, and separate read/write/execute
bits for owner and public; `attr` sets them, `dir -e` shows them. Record locking
is supported through the path-extension structures (`PD.Exten`, `PE.Lock`,
`RcdLock`/`FileLock`/`EofLock`).

**Device naming.** `/d0`, `/d1`, `/dd` (the default device), `/h0`, `/x0`-`/x3`
(DriveWire), `/r0` (RAM disk), `/md` (memory device). `/dd` is a descriptor like
any other; recipes decide what it points at. Pathnames are `/device/dir/file`;
a leading `/` is absolute, otherwise the path is relative to the current data
directory. There are two current directories per process — the **data**
directory (`chd`, shown by `pwd`) and the **execution** directory (`chx`, shown
by `pxd`), which is where the shell looks for commands.

**Disk formats.** The build's `os9 format` variants (`recipes/rules.mak`) cover
35/40/80-track single- and double-sided double-density floppies, a 29126-sector
DriveWire/SD volume, and a 64-track 16-sector cartridge format. `dcheck`
verifies structure; `format`, `backup`, `verify`, `dsave` and `dirsort` round out
the disk tools.

### SCF — the Sequential Character File Manager

`level1/modules/scf.asm`. Terminals, serial ports, printers, windows — anything
character-at-a-time. SCF provides line editing, echo, backspace/delete handling,
pause-at-end-of-page, auto line feed, and the control keys (interrupt, quit,
end-of-file) whose values come from the device descriptor. NitrOS-9 adds an
`SS.Fill` SetStat that stuffs a string into any SCF device's input buffer.

Drivers under SCF in this tree: `vtio` (the CoCo video terminal),
`scbbt`/`scbbp` (bit-banger terminal and printer), `sc6551`, `sc6850`, `sc16550`,
`modpak`, `scdwv`/`scdwp` (DriveWire virtual channels and printer), `vrn`
(VIRQ/RAM/Nil), and the per-port terminal drivers.

### PipeMan

`level1/modules/pipeman.asm` with the `piper` driver and `pipe` descriptor;
`level2/modules/pipeman_named.asm` adds named pipes. This is what makes shell
pipelines (`dir ! more`) work.

### Other file managers

- **RFM** — Remote File Manager (`level1/modules/rfm.asm`), forwards operations
  to a DriveWire server.
- **RBSuper** (`level1/modules/rbsuper.asm`) — not a file manager but a
  high-level RBF driver that fetches *physical* sectors (512 bytes on IDE/SCSI,
  2048 on CD-ROM) and presents 256-byte logical sectors, with caching. Low-level
  transport drivers plug in underneath: `llide`, `llscsi`, `lltc3`, `llcocosdc`,
  `llwbsd`.
- **CDF** — HawkSoft's CD file manager, referenced (commented out) in the CoCo 3
  bootlist; not maintained here.

### System directories on a built disk

A recipe-produced image looks like:

```text
/DD/CMDS        executable modules
/DD/SYS         helpmsg, errmsg, motd, password, inetd.conf,
                stdfonts, stdpats_*, stdptrs, ibmedcfont, isolatin1font
/DD/DEFS        os9.d, rbf.d, scf.d and the port defs (assembler reference)
/DD/startup     the boot script
/DD/sysgo       the kickstart program
OS9Boot         the bootfile (not in a directory; pointed at by LSN 0)
```

---

## 5. Boot process

The details vary by machine, but the CoCo shape is the reference. Four pieces
cooperate: **REL**, **Boot**, **Krn**, and the **bootfile**.

### 1. The boot track

On a CoCo disk, track 34 is reserved as the boot track and holds a merged file —
the recipes call it `kerneltrack` — containing three modules in order:

```text
rel_80          REL, the relocation/startup routine (level1/coco1/modules/rel.asm)
boot_1773_6ms   the Boot module for this device (boot_1773, boot_dw, boot_rom, ...)
krn             the kernel (level2/modules/kernel/krn.asm)
```

`os9gen -t=kerneltrack` writes that onto the boot track. REL starts with the ASCII
sync bytes `OS` followed by a branch, so the machine's own ROM loader (DECB's
`DOS` command, the cartridge ROM, or a firmware loader) can recognize and jump
into it. REL copies the image to `Bt.Start` (`$ED00` Level 2, `$EE00` Level 1),
sets the machine into its initial video mode, prints the boot banner, and enters
the kernel.

### 2. Kernel cold start

`krn.asm` sets up the direct page globals, the DAT/MMU for the system task,
the process and path descriptor tables, the IRQ polling table, then:

- links to the **`Init`** module (`level1/modules/init.asm`) — the configuration
  module. Init is pure data: maximum memory, polling-table and device-table
  sizes, the name of the first program to fork (`SysGo`), the default disk
  device, the default console, the bootstrap module name, the OS level/version,
  feature bytes (6309? CRC checking on?), and on Level 2 the VTIO block
  (monitor type, mouse resolution, key repeat constants).
- calls **`F$Boot`**, which enters the **Boot** module. Boot's job is
  device-specific: read `OS9Boot` into memory. `boot_1773` drives the WD1773
  floppy controller using `DD.BT`/`DD.BSZ` from LSN 0; `boot_dw` pulls the
  bootfile over the DriveWire link; `boot_rom` copies it out of ROM;
  `boot_romdisk` (arm6309), `boot_sdc`, `boot_ide`, `boot_scsi`, `boot_mmc`,
  `boot_emu` do the equivalent for their hardware. `level1/coco1/modules/` holds
  the full set.
- validates every module in the loaded bootfile (`F$VModul`) and builds the
  module directory.

### 3. The bootfile

`OS9Boot` is a plain concatenation of modules chosen by a **bootlist** — a
CoCo-era text file where a leading `*` comments a line out. The canonical
example is `level2/coco3/bootlists/standard.bl`, which is organized into
sections and doubles as documentation of what a system can contain:

```text
kernel/system   krnp2, ioman, init                      (mandatory)
RBF             rbf.mn, a driver, and its descriptors
SCF             scf.mn, vtio.dr, co3hires.sb, snddrv, joydrv,
                cowin.io (or cogrf.io / covdg.io), a /term descriptor,
                w.dw ... w15.dw window descriptors, serial and printer drivers
Pipe            pipeman.mn, piper.dr, pipe.dd
Clock           clock_60hz or clock_50hz, plus a clock2 for the real-time clock
```

Modern recipes express the same selection as makefile variables (`RBF`, `SCF`,
`PIPE`, `CLOCK`, `BOOTMODS`) and build the bootfile by `cat`. The bootlists
remain useful as a menu of what exists and for on-machine `merge`-based boot
creation via `level2/coco3/scripts/mb.floppy`.

### 4. SysGo and startup

`Init` names `SysGo` as the first program. `level1/modules/sysgo.asm` prints the
copyright banner and build string, sets its priority, and forks
`shell startup` — falling back to `shell` alone if `/DD/startup` is missing.
Holding SHIFT at boot skips the startup script. A typical startup
(`level2/coco3/startup`):

```text
echo * Welcome to NitrOS-9 Level 2 *
link shell
load utilpak1
setime </1
date -t
```

`link` locks the shell into memory; `load utilpak1` pulls in a merged bundle of
common commands so they don't need a disk read each time.

### Variations worth knowing

- **Pico-Thing** carries *two* boot files: `OS9Kernel` (Boot padded to 1 KB
  followed by `krn`, loaded by a small raw loader `rel_picothing` at `$E800`)
  and `OS9Boot` (everything else). See `recipes/picothing/README.md`.
- **arm6309** boots from a 1 MB ROM: page 0 is the machine's boot monitor, pages
  1-2 hold `rel_arm6309` + Boot + krn, and pages 3-127 are an RBF image served
  as `/DD` by `rbromdisk`.
- **Wildbits** uses **FEU** (First Execution Unit, `level1/wildbits/feu/`), a
  firmware-level menu/loader that reads a script and loads the bootfile into
  RAM; the kernel then allocates the already-loaded image rather than calling
  `F$Boot`.
- **ROM systems** use `boot_rom` and `padrom`, and `Init` conditionals drop the
  disk-oriented defaults.
- `cobbler` rebuilds a bootfile from the currently running system; `os9gen`
  builds one from a file; both then update `DD.BT`/`DD.BSZ`.

---

## 6. Commands

Commands are ordinary `Prgrm` modules. Shared ones live in `level1/cmds/` (97
sources) and `level2/cmds/` (15 Level 2-only sources); ports may add their own in
`<port>/cmds/`. Each has a matching one-screen help entry in `level1/sys/*.hp`
or `level2/sys/*.hp`, and the build concatenates those into `/DD/SYS/helpmsg`
for the `help` command.

`STDCMDS` in `recipes/rules.mak` is the set every recipe installs:

```text
asm attr backup bawk binex build cmp copy date dcheck debug ded deiniz del
deldir devs dir dirsort disasm display dmode dsave dump echo edit error exbin
format free grep help ident iniz irqs keyrpt link list load login makdir
megaread mdir merge mfree more padrom park pick printerr procs prompt pwd pxd
rename save setime sleep tee tmode touch tsmon unlink verify xmode
```

Grouped by what they do:

- **Filesystem** — `dir`, `copy`, `del`, `rename`, `makdir`, `deldir`, `attr`,
  `list`, `more`, `dump`, `cmp`, `touch`, `build`, `tee`, `pick`, `dirsort`,
  `dsave`, `backup`, `verify`, `free`, `format`, `dcheck`, `park`.
- **Modules and memory** — `load`, `link`, `unlink`, `merge`, `mdir`, `mfree`,
  `ident`, `save`, `deiniz`/`iniz`, `padrom`. Level 2 adds `mmap`, `smap`,
  `pmap`, `dmem`, `modpatch`.
- **Processes** — `procs`, `kill` (via shell), `sleep`, `tsmon` (timesharing
  monitor for login ports), `login`. Level 2 adds `proc`.
- **Devices and system** — `devs`, `irqs`, `dmode`, `xmode`/`tmode` (one source,
  `xmode.asm`, built twice), `keyrpt`, `setime`, `date`, `mpi` (Multi-Pak slot
  select), `tuneport`, `cputype`, `config`, `montype`, `reboot`.
- **Development** — `asm` (the assembler), `debug`, `disasm`, `ded` (disk/file
  editor), `edit`, `minted`, `bawk`, `grep`, `binex`/`exbin`, `error`,
  `printerr`, `calldbg`.
- **Boot construction** — `os9gen`, `cobbler` (and `_d64` variants),
  `format_d64`.
- **Graphics/window** — `grfdrv` (the graphics driver itself, kept in CMDS and
  loaded on demand), `wcreate`, `hirestest`.
- **Networking/DriveWire** — `dw`, `inetd`, `telnet`, `httpd`, `modem`,
  `megaread`, `go51`, and the FujiNet `fn*` family.

### The shell

`level1/cmds/shellplus.asm` — "Shell+", L. Curtis Boyle's enhanced shell, built
as `shell`. It is far more than a command launcher; the built-in table at label
`CmdList` is the best inventory:

- **Directories and processes** — `chd`/`cd`, `chx`/`cx`, `.pwd`, `.pxd`, `ex`
  (chain instead of fork), `kill`, `setpr`, `cls`, `w` (wait).
- **Redirection and job control** — `<` input, `>` output, `>>` error, and the
  combined forms `>>>`, `<>`, `<>>`, `<>>>`; `!` and `|` pipes; `&` background;
  `;` separator; `#` to size the forked process's memory.
- **Scripting** — `var.` variables, `path=`, `if`/`then`/`else`/`fi`/`endif`/
  `clrif`, `goto`, `onerr`, `inc.`/`dec.`, `pause`, `i=`, `r=`, `m=`, `z=`.
- **Modes** — `p`/`-p` prompting, `t`/`-t` echo, `x`/`-x` exit-on-error,
  `v`/`-v`, `l`/`-l`, and command history bound to signals 2 and 3.

`shell_21` is the older Microware 2.1 shell, still used by some Level 1
recipes.

The shipped `shell` module is actually a **merge**: `shellplus` plus `date`,
`deiniz`, `echo`, `iniz`, `link`, `load`, `save`, `unlink`, so those commands are
resident with the shell. `utilpak1` is a second merge of `attr build copy del
deldir dir display list makdir mdir merge mfree procs rename tmode`.

---

## 7. Supported hardware

`docs/supported-ports.md` is the maintained matrix; `recipes/` is the
authoritative list of what is routinely built. Each port directory carries a
`port.mak` (machine name, CPU, level, DriveWire baud, telnet/httpd ports) and a
`defsfile` that sets `Level` and pulls in the right `.d` files.

| Port dir | Machine | Level | CPU |
| --- | --- | --- | --- |
| `level1/coco1`, `coco1_6309` | TRS-80 Color Computer 1 | 1 | 6809 / 6309 |
| `level1/coco2`, `coco2_6309`, `coco2b` | Color Computer 2 | 1 | 6809 / 6309 |
| `level1/d64`, `tano`, `dalpha`, `dplus` | Dragon 64, Tano Dragon, Dragon Alpha, Dragon Plus | 1 | 6809 |
| `level1/atari` | Atari XL/XE with Liber809 | 1 | 6809 |
| `level1/corsham` | Corsham 6809 SS-50 | 1 | 6809 |
| `level1/mc09` | Multicomp09 FPGA | 1 | 6809 |
| `level1/deluxe` | Deluxe Color Computer | 1 | 6809 |
| `level1/picothing` | Pico-Thing (RP2350 + MC6809) | 1 | 6809 / 6309 |
| `level1/wildbits` | Wildbits 6809 | 1 | 6809 |
| `level2/coco3`, `coco3_6309` | Tandy Color Computer 3 | 2 | 6809 / 6309 |
| `level2/coco3fpga`, `realcocofpga` | CoCo3FPGA cores | 2 | 6809 |
| `level2/mc09l2` | Multicomp09 FPGA | 2 | 6809 |
| `level2/picothing` | Pico-Thing | 2 | 6809 / 6309 |
| `level2/wildbits` | Wildbits 6809 | 2 | 6809 |
| `level2/arm6309` | arm6309 backplane machine | 2 | 6809 / 6309 |
| `level3/coco3`, `coco3_6309` | CoCo 3 (experimental) | 3 | 6809 / 6309 |

Peripheral support present in the tree:

- **Disk** — WD1773 floppy (Tandy and Disto Super Controller II variants),
  IDE/PATA, SCSI (including the TC³), CoCo SDC, MMC/SD, Burke & Burke, WD1002,
  RAM packs, emulator virtual disks (`emudsk`), RAM disks (`rammer`, `r0`,
  `myram`, `md`), DriveWire virtual drives.
- **Serial** — bit-banger, 6551 ACIA, 6850 ACIA, 16550 UART, Tandy Modem Pak,
  Deluxe RS-232.
- **Video** — VDG, CoCo 3 GIME, PBJ WordPak I/II/RS, CoCoVGA, Dragon Plus,
  the CoCo3FPGA extended modes, the Wildbits VICKY-class core, and the arm6309
  video card.
- **Real-time clocks** — Disto 2 and 4, Dallas DS1315, Eliminator, Harris,
  SmartWatch, the MC09 RTC, the Wildbits RTC, plus `clock2_soft` (software) and
  `clock2_dw` (time from the DriveWire server).
- **Input/sound** — the CoCo keyboard matrix, PS/2 keyboards and mice, hi-res
  joystick adapters, Microsoft/Logitech serial mice on 6551 or 6552, the CoCo 3
  6-bit DAC, SID and PSG on Wildbits.
- **6309 support** is a build-wide `-DH6309=1` conditional. Sources carry
  `IFNE H6309` blocks that use `Q`/`W`/`E`/`F` registers, `TFM`, `LDQ`/`STQ`,
  `AIM`/`TIM`, and native mode. The `--6309` switch to `lwasm` only enables
  instruction parsing; `H6309` is what turns the code on.

---

## 8. Libraries and modules

### `defs/` — the header files

`.d` files `use`d by sources. Each is idempotent (`IFNE FOO.D-1 / FOO.D SET 1`).

| File | Contents |
| --- | --- |
| `os9.d` | service call codes, `SS.` codes, error codes, module header layout, process and path descriptors, direct-page globals, device table |
| `rbf.d` | RBF descriptor init table, LSN 0, file descriptors, directory entries, RBF statics |
| `scf.d` | SCF descriptor and path descriptor layout, SCF driver statics |
| `pipe.d`, `rfm.d`, `rbsuper.d`, `scsi.d`, `ide.d` | per-manager/transport |
| `coco.d`, `dragon.d`, `atari.d`, `mc09.d`, `corsham.d`, `wildbits.d`, `picothing.d`, `arm6309.d` | per-machine hardware map, memory map, DAT/MMU, boot constants |
| `cocovtio.d`, `atarivtio.d`, `wildbits_vtio.d`, `armvid.d` | video/terminal statics, window and screen tables, window globals |
| `drivewire.d` | DriveWire wire protocol opcodes and addresses |
| `midi.d`, `cocosdc.d`, `16550.d` | peripheral registers |

A port's `defsfile` is the single include that ties them together:

```asm
Level    equ   2
         use   os9.d
         use   scf.d
         use   rbf.d
         use   coco.d
```

### `lib/` — linkable libraries

Built by `recipes/libs.mak` into `.a` archives with `lwar`, linked by `lwlink`.

- `lib/sys6809l1.as`, `sys6809l2.as`, `sys6309l2.as` — the OS-9 system call glue
  for `.as`-format programs (`libnos96809l1.a` etc.).
- `lib/coco.as`, `coco3.as`, `coco3_6309.as`, `dragon.as`, `atari.as`, `mc09.as`,
  `wildbitsl1.as`, `wildbitsl2.as` — per-platform support.
- `lib/net.as` → `libnet.a` — TCP helpers for the DriveWire virtual-channel
  network devices: open a connection to a server, set raw mode, echo and
  auto-linefeed control. Used by `telnet`, `httpd`, `inetd`.
- `lib/fuji.as` → `libfuji.a` — FujiNet device access.
- `lib/alib/` → `libalib.a` — Bob van der Poel's RMA library: number conversion
  (`ASC_BIN`, `BIN_DEC`, `BIN_HEX`, `DEC_BIN`, `HEX_BIN`), 8/16-bit multiply and
  divide, string and memory routines (`STRCAT`, `STRCMP`, `STRLEN`, `MEMMOVE`,
  `MEMSET`), character classification (`is_alpha`, `is_digit`, …), file and
  console I/O helpers (`FGETS`, `FPUTS`, `GETS`, `PUTS`, `PRINT_DEC`,
  `PRINT_HEX`), `LINEDIT`, `OPTS` option parsing, `RND`, date/time formatting.
  Documented in `lib/alib/alib.doc` and `alib.intro`.
- `lib/kreiderclib/` — a 130-file C runtime: `malloc`/`calloc`/`free`,
  `printf`-family support, `str*`/`mem*`, `atoi`/`atol`/`atof`, floating point,
  `qsort`/`bsearch`, `open`/`read`/`write`/`close`, `chmod`/`chown`, `time`,
  `system`, `syscall`. Support for C programs built against OS-9.

Note the two source conventions: `.asm` files assemble directly to a finished
OS-9 module (`lwasm --format=os9`), while `.as` files assemble to relocatable
objects (`--format=obj`) that `lwlink` combines with libraries. Commands written
as `.as` — `dw`, `telnet`, `httpd`, `inetd`, `grep`, `pick`, the `fn*` FujiNet
tools — use the second path.

### Where modules live

- `level1/modules/` — `ioman`, `init`, `sysgo`, `rbf`, `scf`, `pipeman`,
  `piper`, `pipe`, `rfm`, `rbsuper`, `rb1773`, `rbdw`, `emudsk`, `vrn`, `nil`,
  the DriveWire transport (`dwio`, `dwread`, `dwwrite`, `dwinit`), serial
  drivers (`sc6551`, `sc6850`, `mc6850`), clocks, and their descriptors.
- `level1/modules/kernel/` — `krn.asm`, `krnp2.asm`, and one file per service
  call (`ffork`, `flink`, `fsleep`, `fsrqmem`, `fvmodul`, `iocall`, …).
- `level2/modules/` — Level 2 `rbf`/`rbf2`, named PipeMan, `clock`,
  `krnp3_perr`, `krnp4_regdump`.
- `level2/modules/kernel/` — the Level 2 kernel plus the mapping service calls
  (`fallimg`, `fallram`, `falltsk`, `fmapblk`, `fclrblk`, `fdatlog`, `fcpymem`,
  `fmove`, `fgblkmp`, `fgprdsc`, …) and `ccbkrn.asm`/`ccbkrn.txt`.
- `level2/coco3/modules/` — the CoCo 3 window system (`cowin`, `covdg`,
  `co3hires`, `vtio`), sound and joystick sub-drivers, RAM disks, and every
  window/screen descriptor (`w.asm` … `w15.asm`, `v1` … `v7`, `term_*`).

---

## 9. Graphics

Two distinct systems live in this tree. Do not confuse them.

### Level 1: VTIO and CO-modules

At Level 1 the console driver is **VTIO** (`level1/wildbits/modules/vtio.asm`,
`level1/atari/modules/vtio.asm`, and the CoCo equivalent). VTIO owns the
keyboard, the bell, escape-sequence parameter collection and the device statics;
the actual screen rendering is delegated to a pluggable **CO-module**, a
subroutine module registered through a vector table (`V.CoVDGE`, `V.CoHRE`,
`V.Co42E`, `V.Co80E`, `V.CoWPE`, `V.CoVGAE`, `V.CoDPlusE` in `defs/cocovtio.d`).

| CO-module | Display |
| --- | --- |
| `covdg` | 32×16 VDG text (and a 64×32 CoCoVGA mode) |
| `co42` | 42×24 text rendered on a graphics screen |
| `cohr` | 51×24 hi-res text on a graphics screen |
| `co80` | 80 columns on a CRT9128 WordPak prototype |
| `cowprs` | 80 columns on the PBJ WordPak RS |

Level 1 also exposes VDG-compatible graphics to BASIC09 through the `gfx`
subroutine module (help: `level1/sys/gfx.hp`).

**Display codes.** The CO-module dispatch table (`level1/coco1/modules/covdg.asm`)
defines the standard control codes, which are the same vocabulary the Level 2
window system speaks:

| Code | Action |
| --- | --- |
| `$01` | home cursor |
| `$02 x+32 y+32` | cursor to X,Y |
| `$03` | erase line |
| `$04` | clear to end of line |
| `$05 $20/$21` | cursor off / on |
| `$06` | cursor right |
| `$07` | bell |
| `$08` | cursor left |
| `$09` | cursor up |
| `$0A` | cursor down |
| `$0B` | erase to end of screen |
| `$0C` | clear screen |
| `$0D` | carriage return |
| `$0E` | display alpha |
| `$1F xx` | extended display functions (VDG-era graphics, color set, mode) |

### Level 2: the window system

Three modules cooperate on the CoCo 3:

- **`vtio.dr`** — the SCF driver. Keyboard, mouse packet assembly, the bell
  vector, escape parameter collection, and the co-module dispatch
  (`G.CoTble`).
- **`cowin.io`** (or **`cogrf.io`**, the same source with `CoGrf` set) — the
  *window interface*. Parses `ESC`-prefixed window commands, maintains window and
  screen tables, and translates each command into a GrfDrv function code. Use
  `cowin` for full Multi-Vue-capable windowing; `cogrf` is the smaller
  text-and-basic-graphics variant. `level2/coco3/modules/cowin.asm`.
- **`grfdrv`** — the graphics driver proper, kept in `/DD/CMDS` and loaded on
  demand by CoWin's Init. GrfDrv **moves itself into its own task-1 memory map**
  and is entered through a fake-RTI trampoline (`D.Flip1`), which is how a
  driver that would never fit in the system map gets a full 64 KB to work in.
  `level2/cmds/grfdrv.asm` — 7,390 lines with a 30-year changelog of
  cycle-counting optimizations, it is the largest single source here
  (`cowin.asm` is second at 5,760).

**Escape command set.** `ESC` (`$1B`) followed by a function byte in `$20-$55`,
then that function's parameter bytes. The table at label `L0027` in `cowin.asm`
is the definitive list; the dispatcher subtracts `$20` and indexes 4-byte
entries (parameter count, GrfDrv function code, vector).

| Code | Command | Params | Purpose |
| --- | --- | --- | --- |
| `$20` | `DWSet` | 7 | define and display a window on a new screen |
| `$21` | `Select` | 0 | bring this window's screen to the display |
| `$22` | `OWSet` | 7 | overlay window (save what's underneath) |
| `$23` | `OWEnd` | 0 | remove overlay, restore underneath |
| `$24` | `DWEnd` | 0 | delete the device window |
| `$25` | `CWArea` | 4 | change the current working area |
| `$29` | `DefGPB` | 4 | define a get/put buffer group |
| `$2A` | `KillBuf` | 2 | delete a buffer |
| `$2B` | `GPLoad` | 9 | load data into a get/put buffer |
| `$2C` | `GetBlk` | 10 | copy a screen rectangle into a buffer |
| `$2D` | `PutBlk` | 6 | draw a buffer onto the screen |
| `$2E` | `PSet` | 2 | select a pattern buffer |
| `$2F` | `LSet` | 1 | select a line-style buffer |
| `$30` | `DefPal` | 0 | restore default palette |
| `$31` | `Palette` | 2 | set one palette register |
| `$32` | `FColor` | 1 | foreground color |
| `$33` | `BColor` | 1 | background color |
| `$34` | `Border` | 1 | border color |
| `$35` | `ScaleSw` | 1 | automatic coordinate scaling on/off |
| `$36` | `DWProtSw` | 1 | device-window protection on/off |
| `$39` | `GCSet` | 2 | select the graphics cursor |
| `$3A` | `Font` | 2 | select a font buffer |
| `$3C` | `TCharSw` | 1 | transparent characters on/off |
| `$3D` | `Bold` | 1 | bold on/off |
| `$3F` | `PropSw` | 1 | proportional spacing on/off |
| `$40`/`$41` | `SetDPtr` / `RSetDPtr` | 4 | move the draw pointer (absolute / relative) |
| `$42`/`$43` | `Point` / `RPoint` | 4 | plot a point |
| `$44`-`$47` | `Line`, `RLine`, `LineM`, `RLineM` | 4 | draw lines (`M` = move pointer) |
| `$48`/`$49` | `Box` / `RBox` | 4 | outline rectangle |
| `$4A`/`$4B` | `Bar` / `RBar` | 4 | filled rectangle |
| `$4E` | `PutGC` | 4 | place the graphics cursor |
| `$4F` | `FFill` | 0 | flood fill |
| `$50` | `Circle` | 2 | circle |
| `$51` | `Ellipse` | 4 | ellipse |
| `$52` | `Arc` | 12 | arc |
| `$53`/`$54` | filled circle / filled ellipse | 2 / 4 | filled conics |

BASIC09 reaches all of this through the **`gfx2`** subroutine module
(`RUN GFX2(path,"Bar",x1,y1,x2,y2)`); `level2/sys/gfx2.hp` is its help entry.
The `wcreate` command does `DWSet`/`OWSet` from the shell.

**Screen types and resolutions.** A window lives on a screen; the screen has a
type (`St.Sty`). High bit set means hardware text, clear means graphics
(`defs/cocovtio.d`):

| Type | Screen |
| --- | --- |
| 1 | 640×200 × 2 colors |
| 2 | 320×200 × 4 colors |
| 3 | 640×200 × 4 colors |
| 4 | 320×200 × 16 colors |
| `$85` | 80-column hardware text |
| `$86` | 40-column hardware text |
| `$FF` | current screen |

GrfDrv holds the GIME register pairs for each type in tables selected at
assembly time by line count (24-line/192-scanline vs 25-line, and on TV/composite
vs RGB the 25-line mode uses 200 rather than 225 scanlines). A `MATCHBOX`
conditional carries additional 48/50/56/60-line tables for extended GIME cores.

**Windows.** Up to **32** windows, tracked by the `G.WUseTb` bitmap, with a
`$40`-byte window table per window starting at `WinBase` (`$1290`). The window
table (`Wt.` offsets in `defs/cocovtio.d`) holds screen-table pointer, cursor
position and physical address, working-area origin and size, X/Y scaling
factors, foreground/background palette numbers, attribute and switch bytes,
bytes-per-row, max X/Y, and the block/offset of the font, pattern (PSet),
line-style (LSet), overlay-save and graphics-cursor buffers. Screen tables
(`St.` offsets) hold type, starting RAM block, logical start, bytes per row,
border/foreground/background palette registers, screen size in lines, and a
16-entry palette save area.

Device descriptors `w.dw` through `w15.dw` predefine windows; `v1.dw` through
`v7.dw` are VDG-mode windows; `term_win40.dt`/`term_win80.dt`/`term_vdg.dt`
select what `/term` is. Each descriptor is a small assembly file setting
`szx`, `szy`, `sty`, `cpx`, `cpy` and three palette numbers — easy to copy and
edit.

**Character attributes** (`Wt.BSW`, the "character binary switches"):
blink (hardware text only), transparent, underline, bold, proportional,
auto-scaling, inverse, no-cursor, and device-window protect.

**Fonts.** A font is a data module in "GPLoad format": a two-byte `$1B $2B`
header, group number, buffer number, style, X size, Y size and byte count,
followed by the bitmap. Group `$C8` is the font group.

- `level2/sys/stdfonts.asm` — the standard 8×8 set, buffer 1, plus graphics
  characters appended for scroll bars and box drawing.
- `level2/sys/ibmedcfont.asm` — IBM EDC set, buffer `$40`.
- `level2/sys/isolatin1font.asm` — ISO Latin-1, buffer `$3F`.
- Wildbits adds 28 more under `level1/wildbits/sys/fonts/` (Commodore, MSX,
  Apple II-ish, Phoenix EGA, gothic, uncial, emoji, banner faces, …).

Select a font with `ESC $3A group buffer`; load one at runtime by `display`ing
the font file to the window, since the file *is* a stream of GPLoad commands.

**Patterns.** Fill patterns for `Bar`, `FFill` and pattern-filled shapes, group
`$CD`, in `level2/sys/stdpats_2.asm`, `stdpats_4.asm` and `stdpats_16.asm` — one
set per color depth. `ESC $2E` (`PSet`) selects the active pattern buffer;
`ESC $2F` (`LSet`) selects a line style.

**Pointers.** Mouse/graphics cursors, group `$CA`: `level2/sys/stdptrs.asm`
(arrow, pencil, and friends) and `stdptrs_alt.asm`. `level2/sys/stdmv.asm`
carries the Multi-Vue scroll-bar arrows as group `$CE`. `ESC $39` (`GCSet`)
selects one; `ESC $4E` (`PutGC`) positions it.

**Get/put buffers.** The general mechanism behind all of the above:
`DefGPB` reserves a buffer group, `GPLoad` fills a numbered buffer with image
data, `GetBlk` captures a screen rectangle into a buffer, `PutBlk` blits it back
(with a logic operation), `KillBuf` frees it. Fonts, patterns and pointers are
just conventional group numbers in this same space. GrfDrv allocates buffer
memory in 8 KB blocks and tracks the next free offset in the window table
(`Wt.BLen`, `Wt.NBlk`, `Wt.NOff`).

**Scrolling.** Handled inside GrfDrv rather than exposed as an escape command:
writing past the last line, or issuing insert-line/delete-line, moves the window
contents. GrfDrv has separate optimized paths for full-width and partial-width
windows, for hardware text and for each graphics depth, and on 6309 uses `TFM`
block moves. The changelog at the top of `grfdrv.asm` is largely a record of
shaving cycles off these loops. Hardware-text screens can also be scrolled by
changing `St.LStrt` (the GIME logical start address) instead of moving bytes.

**Shared application screens.** `co3hires.sb` (`level2/coco3/modules/co3hires.asm`)
provides `SS.AScrn` (allocate), `SS.DScrn` (display), `SS.PScrn` (prepare),
`SS.FScrn` (free) and the CoVDG form of `SS.ScInf` — the interface games and
non-window applications use to grab a raw high-resolution screen. Up to three
such screens are tracked. `vrn.dr` with the `vi` and `ftdd` descriptors exists
for the same reason: specific commercial titles (King's Quest III, Leisure Suit
Larry, Flight Simulator II) expect them.

---

## 10. Wildbits

The **Wildbits 6809** is a modern FPGA-based 6809 single-board computer, and it
is the most actively developed non-CoCo target here. Two platform variants exist,
`k2` (default) and `jr2`, selected with `make PLATFORM=`. It runs both Level 1
and Level 2 (`level1/wildbits/`, `level2/wildbits/`, `defs/wildbits.d`,
`defs/wildbits_vtio.d`).

**Hardware, from `defs/wildbits.d`:**

- 8-slot MMU with four switchable LUT banks (`MMU_MEM_CTRL` at `$FFA0`,
  slot registers at `$FFA8`), 64 blocks of 8 KB.
- A **VICKY-class video core** (Foenix lineage) at `$FFC0`: hardware text mode
  with a foreground/background color LUT and two loadable font banks, a graphics
  mode with three **bitmap** layers each with its own CLUT, a **tilemap**
  engine, a **sprite** engine, gamma correction, hardware cursor with
  programmable flash rate, raster line interrupts, double-X/double-Y pixel
  doubling, and a text-over-graphics overlay mode.
- PS/2 keyboard and PS/2 mouse (with a hardware mode where the core interprets
  PS/2 packets and draws the pointer itself), plus a K2 optical keyboard with
  hardware typematic.
- Two W65C22S VIAs, two hardware timers with compare registers, a battery-backed
  real-time clock, two joystick ports, a 16550-class UART, an audio CODEC, a SID
  and a PSG, a buzzer, LEDs, and an SD card interface.
- Wi-Fi through a **WizFi** module and Ethernet through a **W6100**.

**What the port provides:**

- `vtio.asm` and `vtio_dma_scroll.asm` — the console driver, the latter using
  the video core's block move for scrolling. Keyboard drivers `keydrv_k`,
  `keydrv_k2`, `keydrv_ps2`; `mousedrv_ps2`.
- Storage: `llwbsd` (SD card) under RBSuper, `rbmem` (RAM disk), and DriveWire
  over either the serial UART or WizFi (`dwinit/dwread/dwwrite_wildbits_serial`
  and `..._wizfi`).
- Sound: `snddrv_sid`, the `SOLdrv`/`fSOL` sound-object layer, `libs/wbsnd`,
  and the `melody`, `play`, `snddemo` commands.
- **FEU — First Execution Unit** (`level1/wildbits/feu/`): a pre-OS menu and
  script interpreter that lives in flash, presents a boot menu, and loads the
  bootfile into RAM. Built by `recipes/wildbits/feu/`, which also produces
  flashable packages (`make flash`, `make upload`).
- **`wild`** (`level1/wildbits/cmds/wild.asm`) — a BASIC09 subroutine module
  exposing the whole machine to BASIC09 in one call. Its function names give the
  clearest inventory of what the port can do:
  - console/text: `Display`, `Clear`, `CurHome`, `CurXY`, `CurUp/Dwn/Lft/Rgt`,
    `CurOn/Off`, `ErLine`, `ErEOLine`, `ErEOWndw`, `InsLin`, `DelLin`, `CrRtn`,
    `Bell`, `Color`, `Palette`, `WInfo`
  - fonts: `FNLoad`, `FNChar`, `FNSet`
  - graphics: `GOn`, `GOff`, `Bitmap`, `BMStatus`, `BMOff`, `BMLoad`, `BMSave`,
    `BMClear`, `ClutLoad`, `ClutFree`, `GFree`, `Pixel`, `GetPixel`, `Line`,
    `Box`, `Bar`, `Circle`, `Layers`
  - sprites: `SPCreate`, `SPConfig`, `SPAssign`, `SPPos`, `SPLoad`, `SPSave`,
    `SPKill`
  - tiles and tilemaps: `TSAlloc`, `TSLoad`, `TSSave`, `TSKill`, `TSAddr`,
    `TMAlloc`, `TMLoad`, `TMSave`, `TMKill`, `TMCfg`, `TMXYScrl`, `TMOn`,
    `TMOff`, `TMAddr`
  - input: `Inkey`, `Mouse`, `MouseHR`, `JoyA`, `JoyB`, `JoyL`, `JoyR`
  - system: `ID`, `GetDate`, `GetTime`, `GetDayOfWeek`, `Tone`, `Random`,
    `Seed`, `Mult`, `Real`, `DWSet`
- Utilities: `wbinfo`, `wbreset`, `wildspeed`, `scfg`, `wmset`, `view`,
  `lcdload`, `bootos9`, `sprtest2`, `w6100eth`/`w6100recv`; Level 2 adds
  `drawtest`, `fadein`/`fadeout`, `pixview`, `xtclut`, `gfxstatus`, `shellbg`,
  `hexed`, `fm`, `ntptime`, `wizfitool`.
- Assets: 28 fonts and 12 background images (paired `pixmap*`/`clut*` modules) in
  `level1/wildbits/sys/`.

**Builds** (`recipes/wildbits/`): `l1`, `l2` (SD boot), `l1dw`, `l2dw`
(DriveWire boot), `l2_mega`/`l2dw_mega` (adds the native C compiler, Forth09,
the Infocom interpreter with Zork I-III and Raaka-Tu, and the OS-9 Level 2 BBS),
`feu` (flash artifacts), and `l2win` (a Windows/cygwin build host variant whose
README documents a real, reproduced module-ordering bug worth reading before
touching `SHELLMODS`).

---

## 11. Networking and DriveWire

**DriveWire** is a serial protocol between the 6809 machine and a host PC
running a DriveWire server. The host provides virtual disks, a clock, printing,
and up to 15 virtual serial channels — including a TCP/IP stack by proxy.

- Protocol: `defs/drivewire.d`. Opcodes are mostly ASCII letters — `'R'` read
  sector, `'W'` write, `'G'`/`'S'` getstat/setstat, `'#'` time, `'Z'`
  init/boot, `'P'`/`'F'` print and flush, `'C'`/`'c'` serial read,
  `'C'+128` serial write. Also WireBug remote debugging opcodes (read/write the
  CoCo's registers and memory, then `'G'` to continue) and FujiNet passthrough.
- Transport: `level1/modules/dwio.asm` with per-machine `dwinit`, `dwread`,
  `dwwrite` (bit-banger, 6551, 16550, Becker port, WizFi…). Selecting the right
  trio is the main per-port DriveWire work.
- Consumers: `rbdw.dr` + `x0`-`x3` descriptors (virtual disks), `scdwv.dr` +
  `n0`-`n14`/`z1`-`z7` descriptors (virtual channels), `scdwp.dr` + `p` (printer),
  `clock2_dw` (time), `boot_dw` (booting), `rfm` (remote files).
- Commands: `dw` talks to the server; `telnet` and `httpd` run over virtual
  channels; `inetd` listens and forks, configured by `/DD/SYS/inetd.conf`:

  ```text
  # ListenPort <server opts>,Process,Params,PathOpts
  %TELNET_PORT% telnet protect banner,login,
  %HTTPD_PORT%,httpd,
  ```

  The placeholders are substituted at build time from `TELNET_PORT` and
  `HTTPD_PORT` in the port's `port.mak` (6802 and 8802 for `coco1`, for
  example), so two ports' images can coexist on one server.
- **FujiNet** support is optional (`FUJINET=1` in a recipe): `lib/fuji.as` plus
  the `fngethost`, `fnsethost`, `fnlisthosts`, `fnlistdevs`, `fngetdevfile`,
  `fnsetdevfile`, `fnmount`, `fnmountimg`, `fnstatus` commands.

---

## 12. Building: recipes, bootlists, toolchain

### Prerequisites

- **LWTOOLS** — `lwasm`, `lwlink`, `lwar` (<http://lwtools.projects.l-w.ca>)
- **ToolShed** — the `os9` utility suite (<https://github.com/n6il/toolshed>),
  used for `format`, `gen`, `copy`, `attr`, `ident`, `padrom`
- `make`, and `zip` for FEU packaging

Recipes that include BASIC09 need a sibling checkout of
[`nitros9-languages`](https://github.com/nitros9project/nitros9-languages); the
expanded "mega" recipes also want
[`nitros9-apps`](https://github.com/nitros9project/nitros9-apps), `git`, and
CMOC:

```text
parent/
  nitros9/
  nitros9-apps/
  nitros9-languages/
```

Override with `LANGUAGES` and `NITROS9_APPS_DIR` if your layout differs. Games,
including the Sierra AGI support, live in a separate `nitros9-games` repository.

### Building

```sh
export NITROS9DIR=$HOME/code/nitros9
make -C recipes/coco3/floppy          # -> l2_coco3.dsk
```

Every recipe writes into its own directory and keeps intermediates local:
`.obj/` objects, `.lib/` archives, `.mods/` assembled modules. `make clean`
inside a recipe directory removes them.

The recipe directories:

| Path | Product |
| --- | --- |
| `recipes/coco/floppy`, `coco/dw` | CoCo 1/2 Level 1 floppy and DriveWire images |
| `recipes/coco3/floppy`, `coco3/dw`, `coco3/dw_mega`, `coco3/basic09` | CoCo 3 Level 2 |
| `recipes/coco3_6309/` | CoCo 3 Level 2, 6309 native |
| `recipes/picothing/{l1,l2,l1dw,l2dw}` and `_6309` variants | Pico-Thing |
| `recipes/wildbits/{l1,l2,l1dw,l2dw,l2_mega,l2dw_mega,feu,l2win}` | Wildbits |
| `recipes/arm6309/l2` | arm6309 1 MB boot ROM |

Common knobs, mostly set in a recipe's own `recipe.mak`:

- `TRACKS=40|80`, `MINIMAL=1`, `PLATFORM=k2|jr2`, `CPU=6809|6309`
- `TERM_COLS=32|40|80` and `TERM_ALTCOLOR=1` on the CoCo 3 — 32 selects
  `covdg.io` + `term_vdg.dt`, 40/80 select `cowin.io` + `term_win40/80.dt`
- `KEYRPT=0` to disable key repeat (helps fast-forwarded MAME runs)
- `FUJINET=1`
- `RECIPE` (output name), `CMDS_EXTRA`, `BOOTMODS_EXTRA`, `AFLAGS_EXTRA`,
  `LFLAGS_EXTRA`

To make your own product, copy a recipe directory and add a `recipe.mak` — the
shared platform makefile `-include`s it, so you never edit shared makefiles:

```sh
cp -R recipes/coco3/floppy recipes/coco3/myrecipe
cp recipes/coco3/recipe-template.mak recipes/coco3/myrecipe/recipe.mak
make -C recipes/coco3/myrecipe
```

### How a disk image is produced

Read `recipes/coco3/coco3.mak` alongside `recipes/rules.mak` and the sequence is
plain:

1. `libs` — build the `.a` archives from `lib/`.
2. `kernelfile` — `cat` the boot-track modules (`rel_80 boot_1773_6ms krn`).
3. `bootfile` — `cat` the `BOOTMODS` list into `OS9Boot`.
4. `os9 format` the image, `os9 gen -b=bootfile -t=kerneltrack`.
5. `makdir` `CMDS`, `SYS`, `DEFS`; build the system assets through
   `recipes/support/coco3-system.mak` (which concatenates all `.hp` files into
   `helpmsg` and generates `motd` and `inetd.conf`); copy everything in and set
   OS-9 attributes with `os9 attr`.
6. Copy `sysgo` and `startup`.

`recipes/rules.mak` also defines the pattern rules that give each module its
extension (`%.mn`, `%.dr`, `%.dd`, `%.dt`, `%.dw`, `%.sb`, `%.io`) and the
`-D` variations that turn one source into several modules (`pwd`/`pxd` from
`pd.asm`; `xmode`/`tmode` from `xmode.asm`; `clock_50hz`/`clock_60hz` from
`clock.asm`; every floppy descriptor from `rb1773desc.asm`).

### Continuous integration

`.github/workflows/nitros9.sh` greps the whole tree for unresolved merge
markers, dry-runs `clean` in every recipe to catch makefile parse errors, then
builds `coco/floppy`, `coco/dw`, `coco3/floppy`, `coco3/dw`, and the four base
Pico-Thing recipes. Run it locally before submitting shared-build changes:

```sh
bash .github/workflows/nitros9.sh
```

---

## 13. Source conventions and tooling

### Formatting

Assembly formatting is mechanical, not a style guide to memorize.
`scripts/asmprettyprint.py` applies the canonical column layout and normalizes
instruction comments to lowercase `; …` form, and `scripts/pre-commit` runs it on
staged assembly. Install the hook and stop thinking about it.

### File header convention

Almost every source starts with the same block, and keeping it up to date is the
project's change log:

```asm
********************************************************************
* Name - One-line description
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*   3      2026/05/12  Someone
* What changed and why.
```

The `edition` byte in the module (`fcb edition` after the name string) should
track the `Edt` column; `ident` prints it on a running system.

### Reverse-engineering tools

A large part of this tree began as disassembly of Microware binaries, and the
tooling for that is maintained:

| Tool | Use |
| --- | --- |
| `scripts/dis6809.py` | disassemble raw 6809 machine code |
| `scripts/os9dis.py` | disassemble OS-9 modules and data structures |
| `scripts/fcb2bin.py` | turn `fcb` byte declarations back into binary |
| `scripts/debug/list2crc.pl` | rename `lwasm` listings by module CRC |
| `scripts/debug/os9.gdb` | GDB commands that map a loaded module to its listing |

There is also an **`annotate-asm` skill** (`.claude/skills/annotate-asm/`, mirrored
in `.codex/skills/`) that turns raw disassembly into legible source — renaming
`L0047`-style labels, commenting every instruction, fixing code-decoded-as-data
— under a strict byte-oracle: the module must reassemble to identical bytes at
every step. Several files here carry a note saying they were processed that way.

### Contributing

`CONTRIBUTING.md`: fork, keep each commit to one logical change, verify the
narrowest relevant recipe, and don't commit generated images, objects, maps,
listings or emulator config.

---

## 14. Where to look for what

| I want to… | Start at |
| --- | --- |
| understand a system call | `defs/os9.d`, then `level*/modules/kernel/f*.asm` |
| understand the disk format | `defs/rbf.d`, then `level1/modules/rbf.asm` |
| add a disk driver | `level1/modules/rb1773.asm` as a model; descriptor from `rbdesc.asm` |
| add a serial driver | `level1/modules/sc6551.asm`, `sc16550.asm` |
| change what's on a built disk | the recipe's `recipe.mak`, or `CMDS`/`BOOTMODS` in the platform `.mak` |
| change what's in the bootfile | `BOOTMODS` in the platform `.mak`; `<port>/bootlists/*.bl` for the annotated menu |
| add a command | drop a `.asm` in `level1/cmds/`, a `.hp` in `level1/sys/`, add both to the recipe and to `HELPFILES` |
| change the window system | `level2/coco3/modules/cowin.asm` (parsing) and `level2/cmds/grfdrv.asm` (drawing) |
| add a font or pattern | copy the GPLoad header form from `level2/sys/stdfonts.asm` |
| port to new hardware | copy a `<port>/` directory: `port.mak`, `defsfile`, a `defs/<machine>.d`, a boot module, a console driver, and a recipe |
| see what the OS reports about itself | `level1/modules/init.asm` and `level1/modules/sysgo.asm` |
| find something that used to exist | `archive/` and `archive/MANIFEST.md` |

### A caution about `archive/`

Nothing under `archive/` is built or supported. It holds third-party drivers and
file managers, experimental modules, historical packages, unfinished work,
obsolete release-engineering scripts, and project history. Material there may be
incomplete, superseded, tied to dead hardware, or under different licensing.
Treat it as a reference collection, and check provenance before reviving
anything.

---

## 15. Glossary

| Term | Meaning |
| --- | --- |
| **CO-module** | a rendering back end plugged into VTIO at Level 1 (`covdg`, `cohr`, `co80`, …) |
| **DAT** | Dynamic Address Translator — the 8-entry block-register image that defines a task's 64 KB view at Level 2 |
| **Descriptor** | a small data module describing a device: which file manager, which driver, what port, what defaults |
| **DriveWire** | serial protocol giving the machine virtual disks, clock, printing and network channels from a host PC |
| **FEU** | First Execution Unit — the Wildbits pre-OS loader and menu |
| **File manager** | the layer that gives a class of devices its semantics: RBF (disks), SCF (characters), PipeMan, RFM |
| **GIME** | the CoCo 3's custom gate array: MMU, video, interrupts |
| **GPLoad / get-put buffer** | the general image-buffer mechanism used for fonts, patterns, pointers and sprites-by-blit |
| **GrfDrv** | the Level 2 graphics driver, running in its own memory map |
| **LSN** | Logical Sector Number — RBF's 3-byte sector address |
| **Module** | the universal unit of code and data: header, body, CRC; relocatable and shareable |
| **Native mode** | the 6309's faster execution mode, enabled by the `ModNat` attribute and `-DH6309=1` builds |
| **Recipe** | a makefile directory under `recipes/` that produces one bootable product |
| **REL** | the relocation/startup module at the head of the boot track |
| **Sub-module** | `.sb`/`.io` subroutine modules called by a driver (`joydrv`, `snddrv`, `co3hires`, `cowin`) |
| **VTIO** | the CoCo video terminal I/O driver — keyboard, mouse and screen, delegating rendering to co-modules |
| **Window table / screen table** | the `Wt.`/`St.` structures that define a Level 2 window and the screen it lives on |
