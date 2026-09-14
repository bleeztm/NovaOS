@echo off
REM NovaOS build.bat (Windows) - targets: all floppy esp iso run-bios run-uefi clean
REM Requires: nasm.exe, qemu-system-x86_64.exe, python.exe on PATH
setlocal
set BUILD=build
set NASM=nasm
set PY=python
if "%1"=="" set TARGET=all
if not "%1"=="" set TARGET=%1
if not exist %BUILD% mkdir %BUILD%

if "%TARGET%"=="clean" (
  rmdir /s /q %BUILD% 2>nul
  echo Cleaned.
  exit /b 0
)

:build_bins
%NASM% -f bin boot\bios\mbr.asm -o %BUILD%\mbr.bin || exit /b 1
%NASM% -f bin -I. boot\bios\stage2.asm -o %BUILD%\stage2.bin || exit /b 1
%NASM% -f bin -I. kernel\entry.asm -o %BUILD%\KERNEL.BIN || exit /b 1
%NASM% -f bin -I. boot\uefi\uefi_boot.asm -o %BUILD%\BOOTX64.EFI || exit /b 1
%NASM% -f bin -I. boot\grub\multiboot.asm -o %BUILD%\nova_stub.bin || exit /b 1
dir %BUILD%
if "%TARGET%"=="all" goto :images
if "%TARGET%"=="floppy" goto :floppy
if "%TARGET%"=="esp" goto :esp
if "%TARGET%"=="run-bios" goto :floppy
if "%TARGET%"=="run-uefi" goto :esp
if "%TARGET%"=="iso" goto :images

:images
:floppy
%PY% tools\mkimg.py floppy %BUILD%\mbr.bin %BUILD%\stage2.bin %BUILD%\KERNEL.BIN %BUILD%\floppy.img || exit /b 1
if "%TARGET%"=="floppy" exit /b 0
:esp
%PY% tools\mkimg.py esp %BUILD%\BOOTX64.EFI %BUILD%\KERNEL.BIN %BUILD%\esp.img || exit /b 1
if "%TARGET%"=="esp" exit /b 0
if "%TARGET%"=="all" exit /b 0

if "%TARGET%"=="iso" (
  echo ISO: use Rufus/balenaEtcher with floppy.img (BIOS) or esp.img (UEFI). See docs.
  exit /b 0
)
if "%TARGET%"=="iso-grub" (
  echo iso-grub needs grub-mkrescue: run in WSL with grub-pc-bin + xorriso + mtools,
  echo then: ./build.sh iso-grub   (uses boot\grub\grub.cfg + build\nova_stub.bin)
  exit /b 0
)
if "%TARGET%"=="run-bios" (
  qemu-system-x86_64 -drive file=%BUILD%\floppy.img,format=raw,if=floppy -serial stdio -m 128
  exit /b 0
)
if "%TARGET%"=="run-uefi" (
  if defined OVMF (
    qemu-system-x86_64 -drive file=%BUILD%\esp.img,format=raw -bios "%OVMF%" -serial stdio -m 128 -vga std
  ) else (
    echo Set OVMF=C:\path\to\OVMF_CODE.fd  (see docs\BOOT.md)
    exit /b 1
  )
  exit /b 0
)
echo Unknown target: %TARGET%
exit /b 1
