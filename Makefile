# NovaOS Makefile (Linux / MSYS2 / WSL)
# Targets: all floppy.img esp.img iso run-bios run-uefi clean
NASM ?= nasm
QEMU ?= qemu-system-x86_64
PY   ?= python3
BUILD = build
OVMF ?= /usr/share/OVMF/OVMF_CODE.fd

all: $(BUILD)/floppy.img $(BUILD)/esp.img

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/mbr.bin: boot/bios/mbr.asm | $(BUILD)
	$(NASM) -f bin $< -o $@

$(BUILD)/stage2.bin: boot/bios/stage2.asm boot/bios/gdt16.inc include/bootinfo.inc | $(BUILD)
	$(NASM) -f bin -I. boot/bios/stage2.asm -o $@
	@if [ $$(stat -c%s $@) -gt 4608 ]; then echo "ERROR: stage2 > 4608 bytes (would hit BootInfo @0x9000)"; exit 1; fi

$(BUILD)/KERNEL.BIN: kernel/entry.asm $(wildcard kernel/*.asm kernel/*.inc apps/*.asm include/*.inc) | $(BUILD)
	$(NASM) -f bin -I. kernel/entry.asm -o $@
	ls -l $@

$(BUILD)/BOOTX64.EFI: boot/uefi/uefi_boot.asm boot/uefi/uefi.inc include/bootinfo.inc | $(BUILD)
	$(NASM) -f bin -I. boot/uefi/uefi_boot.asm -o $@

$(BUILD)/floppy.img: $(BUILD)/mbr.bin $(BUILD)/stage2.bin $(BUILD)/KERNEL.BIN tools/mkimg.py
	$(PY) tools/mkimg.py floppy $(BUILD)/mbr.bin $(BUILD)/stage2.bin $(BUILD)/KERNEL.BIN $(BUILD)/floppy.img

$(BUILD)/esp.img: $(BUILD)/BOOTX64.EFI $(BUILD)/KERNEL.BIN tools/mkimg.py
	$(PY) tools/mkimg.py esp $(BUILD)/BOOTX64.EFI $(BUILD)/KERNEL.BIN $(BUILD)/esp.img

iso: all
	@if command -v xorrisofs >/dev/null; then \
	  xorrisofs -o $(BUILD)/novaos.iso -b floppy.img -e esp.img $(BUILD); \
	else echo "xorrisofs not found - use floppy.img (BIOS) and esp.img (UEFI) directly"; exit 1; fi

run-bios: $(BUILD)/floppy.img
	$(QEMU) -fda $(BUILD)/floppy.img -serial stdio -m 128

run-uefi: $(BUILD)/esp.img
	@if [ -f "$(OVMF)" ]; then \
	  $(QEMU) -drive file=$(BUILD)/esp.img,format=raw -bios $(OVMF) -serial stdio -m 128 -vga std; \
	else echo "OVMF not found at $(OVMF). Install ovmf (apt: ovmf) or pass OVMF=/path OVMF_CODE.fd"; exit 1; fi

clean:
	rm -rf $(BUILD)
