# arm6309 Build Recipes

NitrOS-9 Level 2 for arm6309, a 6809E/6309 backplane machine with a GIME-shaped
32 MB map, a 640-wide 8bpp video card and a TL16C550C console.

```sh
export NITROS9DIR=$HOME/code/nitros9
cd l2 && make            # -> arm6309_rom.bin, the machine's 1 MB boot ROM
```

`ARM6309DIR` (default: `$NITROS9DIR/../arm6309`) supplies ROM page 0, the machine's
boot monitor, as `software/boot/boot.bin`. The arm6309 repository's
`software/nitros9/README.md` describes the boot, what differs from a CoCo 3, and
`run-emu.sh`, which boots this ROM on its host emulator and checks the shell.

| ROM page | Holds |
| --- | --- |
| 0 | the boot monitor and the vector page (from arm6309) |
| 1-2 | `rel_arm6309`: "6309", the loader, and OS9Kernel (Boot padded to 1K, then krn) |
| 3-127 | an RBF image: OS9Boot, CMDS, SYS, startup, served by `rbromdisk` as /DD |

`CPU = 6309` with `AFLAGS_EXTRA += -DH6309=1` builds the native-mode kernel; only
the 6809 build has been run.
