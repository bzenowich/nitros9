# arm6309 build recipe: NitrOS-9 Level 2 in the boot ROM.
#
# The product is one 1 MB image for the machine's SST39SF040 pair
# (arm6309 docs/machine.md 7.2):
#
#   ROM page 0        boot.bin: the arm6309 boot monitor and the vector page,
#                     from $(ARM6309DIR)/software/boot/boot.bin
#   ROM pages 1-2     rel_arm6309: "6309", the loader, and OS9Kernel
#                     (boot_romdisk padded to 1K, then krn, $E800-$FEFF)
#   ROM pages 3-127   an RBF image: OS9Boot, CMDS, SYS, startup
#
# The monitor hands off to page 1; the loader puts OS9Kernel in RAM and
# enters krn; F$Boot's module reads OS9Boot from the ROM disk, and
# rbromdisk serves the same image as /DD.

PORT ?= arm6309
RECIPE ?= arm6309
CPU ?= 6809
MACHINE ?= arm6309
MODDIR = .mods
include ../../rules.mak
-include recipe.mak

ARM6309DIR ?= $(abspath $(NITROS9DIR)/../arm6309)
BOOTBIN ?= $(ARM6309DIR)/software/boot/boot.bin

AFLAGS += -I. -I$(L2PD) -I$(L2PMD) -I$(L2MD) -I$(L2MD)/kernel
AFLAGS += -I$(L1PD) -I$(L1PMD) -I$(L1MD) -I$(L1MD)/kernel -I$(L1D)/wildbits/modules
vpath %.asm $(L1D)/wildbits/modules
AFLAGS += $(AFLAGS_EXTRA)

ifeq ($(CPU),6309)
  NOS9_LIB = libnos96309l2.a
  LINK_LIB = -lnos96309l2
else
  NOS9_LIB = libnos96809l2.a
  LINK_LIB = -lnos96809l2
endif
LIB_NAMES = $(NOS9_LIB) libnet.a libalib.a
LFLAGS += -L$(LIBDIR) $(LINK_LIB) -lnet -lalib $(LFLAGS_EXTRA)

# ---------------------------------------------------------------------------
# Modules

RBF   = rbf.mn rbromdisk.dr dd_romdisk.dd r0_romdisk.dd
SCF   = scf.mn sc16550.dr term_16550.dt nil.dr nil.dd
PIPE  = pipeman.mn piper.dr pipe.dd
CLOCK = clock clock2_soft

BOOTFILE = krnp2 krnp3_perr init ioman $(RBF) $(SCF) $(PIPE) $(CLOCK) \
           sysgo shell $(BOOTMODS_EXTRA)

CMDS = attr backup build cmp copy date dcheck debug ded deiniz del deldir \
       devs dir dirsort display dmem dmode dump echo error free help ident \
       iniz irqs link list load makdir mdir merge mfree mmap more pmap proc \
       procs printerr prompt pwd pxd rename save setime sleep smap tee tmode \
       touch unlink verify xmode $(CMDS_EXTRA)
CMDS_MERGED = shell

# Loadable modules in /DD/MODULES: the FIRQ stub's test (driver + /FT0), and
# its command in CMDS.
MODULES = firqtst
CMDS += firqtst vmodetst ps2tst memtst reboot
SHELLMODS = shellplus echo iniz link load save unlink

ROM      ?= arm6309_rom.bin
ROMDSK   ?= romdisk.dsk
ROMDSK_SECTORS = 4000

all: libs $(ROM)

# What the rules above cannot see: krn and krnp2 are dozens of `use`d files,
# and every module reads defs/arm6309.d.  Without these a changed kernel file
# rebuilds nothing and a test runs the previous kernel - which happened.
KERNEL_SRC = $(wildcard $(L2MD)/kernel/*.asm $(L1MD)/kernel/*.asm)
$(MODDIR)/krn $(MODDIR)/krnp2: $(KERNEL_SRC)
$(addprefix $(MODDIR)/,$(filter-out shell,$(BOOTFILE)) boot_romdisk krn $(CMDS) firqtst.dr ft0.dd): $(DEFSDIR)/arm6309.d
rel_arm6309: $(DEFSDIR)/arm6309.d

include ../../libs.mak

$(MODDIR)/dd_romdisk.dd: romdiskdesc.asm | $(MODDIR)
	$(AS) $(AFLAGS) -DDD=1 $< $(ASOUT)$@
$(MODDIR)/r0_romdisk.dd: romdiskdesc.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@
$(MODDIR)/nil.dr: nzdrv.asm | $(MODDIR)
	$(AS) $(AFLAGS) -DNIL=1 $(ASOUT)$@ $<
$(MODDIR)/nil.dd: nzdesc.asm | $(MODDIR)
	$(AS) $(AFLAGS) -DNIL=1 $(ASOUT)$@ $<
$(MODDIR)/tmode: xmode.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@ -DTMODE=1
$(MODDIR)/xmode: xmode.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@ -DXMODE=1
$(MODDIR)/pwd: pd.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@ -DPWD=1
$(MODDIR)/pxd: pd.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@ -DPXD=1
$(MODDIR)/firqtst.dr: firqtstdrv.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@
$(MODDIR)/ft0.dd: firqtstdesc.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@
modules_firqtst: $(MODDIR)/firqtst.dr $(MODDIR)/ft0.dd
	$(MERGE) $^ >$@
$(MODDIR)/shell: $(addprefix $(MODDIR)/,$(SHELLMODS)) | $(MODDIR)
	$(MERGE) $(addprefix $(MODDIR)/,$(SHELLMODS)) >$@

bootfile: $(addprefix $(MODDIR)/,$(BOOTFILE))
	$(MERGE) $(addprefix $(MODDIR)/,$(BOOTFILE)) >$@

# OS9Kernel: the boot module padded to 1K at $E800, then krn at $EC00.
# Both sizes are checked: the loader copies exactly Bt.Size bytes and
# krn's vector stubs must land at $FEEE.
os9kernel: $(MODDIR)/boot_romdisk $(MODDIR)/krn
	@test $$(wc -c < $(MODDIR)/boot_romdisk) -le 896 || { echo "FAIL boot_romdisk overruns the loader's stubs at \$$EB80"; exit 1; }
	@test $$(wc -c < $(MODDIR)/krn) -eq 4864 || { echo "FAIL krn is not \$$EC00-\$$FEFF"; exit 1; }
	dd if=$(MODDIR)/boot_romdisk of=$@ bs=1024 conv=sync 2>/dev/null
	cat $(MODDIR)/krn >>$@

rel_arm6309: rel_arm6309.asm os9kernel
	$(ASROM) $(AFLAGS) $< $(ASOUT)$@

$(ROMDSK): bootfile $(addprefix $(MODDIR)/,$(CMDS) $(CMDS_MERGED)) $(addprefix modules_,$(MODULES))
	$(RM) $@
	$(OS9FORMAT) -q -l$(ROMDSK_SECTORS) $@ -n"NitrOS-9/$(CPU) Level 2 arm6309"
	$(OS9GEN) $@ -b=bootfile
	$(MAKDIR) $@,CMDS
	$(OS9COPY) $(addprefix $(MODDIR)/,$(CMDS) $(CMDS_MERGED)) $@,CMDS
	$(OS9ATTR_EXEC) $(foreach f,$(CMDS) $(CMDS_MERGED),$@,CMDS/$(f))
	$(MAKDIR) $@,MODULES
	$(foreach m,$(MODULES),$(OS9COPY) modules_$(m) $@,MODULES/$(m);)
	$(OS9ATTR_EXEC) $(foreach m,$(MODULES),$@,MODULES/$(m))
	$(MAKDIR) $@,SYS
	$(CPL) $(L1D)/sys/errmsg $@,SYS/errmsg
	$(CPL) $(STARTUP) $@,startup
	$(OS9ATTR_TEXT) $@,startup

STARTUP ?= $(L2PD)/startup

# The ROM: page 0 from arm6309, pages 1-2 the loader, 3-127 the disk.
$(ROM): rel_arm6309 $(ROMDSK) $(BOOTBIN)
	@test $$(wc -c < $(BOOTBIN)) -eq 8192 || { echo "FAIL $(BOOTBIN) is not one 8K ROM page"; exit 1; }
	@test $$(wc -c < rel_arm6309) -le 16384 || { echo "FAIL rel_arm6309 overruns ROM pages 1-2"; exit 1; }
	@test $$(wc -c < $(ROMDSK)) -le $$((125*8192)) || { echo "FAIL the ROM disk overruns the ROM"; exit 1; }
	cp $(BOOTBIN) $@
	dd if=rel_arm6309 bs=16384 conv=sync 2>/dev/null >>$@
	dd if=$(ROMDSK) bs=$$((125*8192)) conv=sync 2>/dev/null >>$@
	@test $$(wc -c < $@) -eq 1048576 || { echo "FAIL $@ is not 1 MB"; exit 1; }
	@echo "wrote $@"

clean:
	$(RM) bootfile os9kernel rel_arm6309 $(ROM) $(ROMDSK) buildinfo *.list *.map modules_*
	-rm -rf $(OBJDIR) $(LIBDIR) $(MODDIR)

.PHONY: all clean libs bootfile
