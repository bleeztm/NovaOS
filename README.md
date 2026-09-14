# NovaOS — hobby x86-64 OS in pure NASM assembly

<p align="center">
  <img src="./assets/novaos.gif" width="400" alt="Demo">
</p>

Dual BIOS + UEFI boot, one 64-bit assembly kernel: GUI desktop, window
manager, emergency shell, PS/2 + ATA + RTC + serial + speaker drivers.
No C, no libc. QEMU-tested on both boot paths.

## Layout

```
boot/bios/   MBR (mbr.asm), stage2 loader (stage2.asm), GDT (gdt16.inc)
boot/uefi/   UEFI app (uefi_boot.asm), offsets/GUIDs (uefi.inc)
include/     unified BootInfo ABI (bootinfo.inc)
kernel/      entry, gdt, idt, mm, sys, fb, kbd, mouse, ata, wm, gui, shell, font
apps/        terminal, fileman, editor (+monitor/settings in editor.asm)
tools/       mkimg.py (FAT12/FAT32 image builder), genfont.py (PSF converter)
docs/        BOOT.md KERNEL.md SHELL.md GUI.md
site/        GitHub Pages static site (no Jekyll)
```

## Prerequisites

* NASM (`nasm`), QEMU (`qemu-system-x86_64`), Python 3.
* UEFI run needs OVMF (`OVMF_CODE.fd`): Linux `apt install ovmf`
  (`OVMF=/usr/share/OVMF/OVMF_CODE.fd`), Windows copy
  `edk2-x86_64-code.fd` from QEMU's `share/` and use `-pflash`
  (see `build.bat run-uefi` / `Makefile run-uefi`).

## Build & run

Windows (`build.bat [target]`) or Linux (`make [target]`, `./build.sh [target]`):

| Target | Effect |
|--------|--------|
| `all` (default) | `build/floppy.img` (BIOS FAT12) + `build/esp.img` (UEFI FAT32) |
| `floppy` / `esp` | single image |
| `run-bios` | QEMU floppy boot, serial on stdio |
| `run-uefi` | QEMU + OVMF ESP boot |
| `iso-grub` / `run-grub` | GRUB multiboot ISO / QEMU CDROM boot (needs grub-mkrescue; Linux/WSL) |
| `iso` | ISO via `xorrisofs` if present |
| `clean` | remove `build/` |

Quick start: `build.bat run-bios` (Windows) or `make run-bios` (Linux).
Press **F8** in the GUI for the emergency shell; `help` lists commands.

Real hardware: write `floppy.img` (BIOS/CSM, USB-FDD ok) or `esp.img`
(UEFI, Secure Boot off) with Rufus/balenaEtcher — see `site/docs.html`.

## Website

Static site in `site/` deploys to GitHub Pages via
`.github/workflows/pages.yml` on push to `main` (see `site/` + workflow).
Live docs: install guide (`docs.html`), roadmap (`roadmap.html`).

## Verified

* BIOS/QEMU: MBR → stage2 → VBE 1280×1024×24 → kernel → GUI (VRAM dump),
  F8 → shell → `help` executes, serial log clean.
* UEFI/OVMF: BOOTX64 → GOP → SFS kernel load → same kernel → GUI.
* See `docs/BOOT.md` for ABI details and QEMU quirks found along the way.
