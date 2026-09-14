#!/bin/sh
# NovaOS build.sh (Linux) - mirrors Makefile for systems without make
set -e
BUILD=build
NASM=${NASM:-nasm}
QEMU=${QEMU:-qemu-system-x86_64}
PY=${PY:-python3}
OVMF=${OVMF:-/usr/share/OVMF/OVMF_CODE.fd}
TARGET=${1:-all}
mkdir -p $BUILD
build_bins() {
  $NASM -f bin boot/bios/mbr.asm -o $BUILD/mbr.bin
  $NASM -f bin -I. boot/bios/stage2.asm -o $BUILD/stage2.bin
  sz=$(stat -c%s $BUILD/stage2.bin)
  if [ "$sz" -gt 4608 ]; then echo "ERROR: stage2 > 4608 bytes (would hit BootInfo @0x9000)"; exit 1; fi
  $NASM -f bin -I. kernel/entry.asm -o $BUILD/KERNEL.BIN
  $NASM -f bin -I. boot/uefi/uefi_boot.asm -o $BUILD/BOOTX64.EFI
  ls -l $BUILD
}
build_floppy() { $PY tools/mkimg.py floppy $BUILD/mbr.bin $BUILD/stage2.bin $BUILD/KERNEL.BIN $BUILD/floppy.img; }
build_esp() { $PY tools/mkimg.py esp $BUILD/BOOTX64.EFI $BUILD/KERNEL.BIN $BUILD/esp.img; }
case $TARGET in
  all) build_bins; build_floppy; build_esp;;
  floppy) build_bins; build_floppy;;
  esp) build_bins; build_esp;;
  iso) build_bins; build_floppy; build_esp;
       if command -v xorrisofs >/dev/null; then xorrisofs -o $BUILD/novaos.iso -b floppy.img -e esp.img $BUILD;
       else echo "xorrisofs not found - use floppy.img / esp.img directly"; exit 1; fi;;
  run-bios) build_bins; build_floppy; exec $QEMU -fda $BUILD/floppy.img -serial stdio -m 128;;
  run-uefi) build_bins; build_esp;
       [ -f "$OVMF" ] || { echo "OVMF not found at $OVMF"; exit 1; }
       exec $QEMU -drive file=$BUILD/esp.img,format=raw -bios "$OVMF" -serial stdio -m 128 -vga std;;
  clean) rm -rf $BUILD;;
  *) echo "Unknown target: $TARGET"; exit 1;;
esac
