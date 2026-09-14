# NovaOS Boot Architecture (BOOT.md)

Two boot paths, one kernel. Both produce the same 64-bit kernel entry state.

## Unified BootInfo ABI (v1) — `include/bootinfo.inc`

Passed as `RDI = BootInfo*` to `kernel_entry`. 80 bytes, 8-byte aligned:

| Off | Size | Field | Notes |
|-----|------|-------|-------|
| 0 | u32 | magic | `0x534F564E` ('NVOS') |
| 4 | u32 | version | 1 |
| 8 | u64 | fb_addr | framebuffer physical address (0 = none) |
| 16 | u32 | fb_width | pixels |
| 20 | u32 | fb_height | pixels |
| 24 | u32 | fb_pitch | bytes per scanline |
| 28 | u32 | fb_bpp | 24 or 32 |
| 32 | u64 | mem_map_addr | physical address of memory-map array |
| 40 | u64 | mem_map_count | entry count |
| 48 | u64 | mem_entry_size | 24 (both paths normalize to this) |
| 56 | u64 | rsdp | ACPI RSDP (0 if unknown) |
| 64 | u64 | boot_type | 0 = BIOS, 1 = UEFI |
| 72 | u64 | kernel_size | bytes (informational) |

Memory-map entry (24 bytes): `base u64 @0, len u64 @8, type u32 @16, attr u32 @20`.
Types: 1 usable, 2 reserved, 3 ACPI-reclaim, 4 NVS, 5 bad.

## BIOS path — `boot/bios/`

* `mbr.asm` — 512-byte MBR with FAT12 BPB (`rsvd=17`: sector 0 MBR +
  sectors 1–16 raw stage2). Loads 16 sectors to `0x7E00`, jumps there.
* `stage2.asm` — 16-bit loader at `0x7E00`:
  1. A20 (`int 0x15/0x2401` + port `0x92`), stack at `0x9E00`.
  2. E820 memory map → `0x5400` (converted to 24-byte UEFI-style entries).
  3. VESA VBE: info `0x5000`, mode info `0x5200`. Tries modes
     `0x118` (1024×768×24), `0x11B` (1280×1024×24), `0x115`
     (800×600×24), `0x112` (640×480×24) in order. A mode is accepted
     only if 0x4F01 succeeds, ModeAttributes bit 7 (LFB) is set,
     MemoryModel is packed(4)/direct(6), bpp ≥ 15, and 0x4F02+LFB
     succeeds — blindly trusting a mode number can land the display in
     a planar mode while the kernel draws linear (tri-color checkerboard
     symptom). Else `fb_addr = 0` (VGA shell).
     ES is reset to 0 before every VBE call (some BIOSes clobber ES).
  4. FAT12 parser: root dir (LBA 35) → find `KERNEL.BIN` → follow cluster
     chain from DATA (LBA 49), streaming clusters to `0x100000` via
     unreal/big-real mode (`FS` with 4GB limit, `mov [fs:edi], eax`).
     CHS math is DIV-free (subtraction loop): a 16-bit `DIV` wrong-remainder
     quirk was observed on QEMU TCG, so no `DIV` is used in stage2.
  5. Builds BootInfo at `0x9000`, enters protected mode, builds 4-level
     tables at `0x70000` (identity 0..64MB with 2MB pages + a 1GB-mapped PD
     at `0x73000` for the framebuffer's region), enables PAE/LME/paging,
     jumps to 64-bit and then to `0x100000` with `RDI = 0x9000`.
* `gdt16.inc` — flat GDT (32-bit code/data + 64-bit code/data).

Low-memory map: `0x1000` FAT table, `0x3000` sector scratch, `0x5000` VBE,
`0x5200` VBE mode, `0x5400` E820 map, `0x6000` root dir, `0x70000` page
tables, `0x7E00` stage2, `0x9000` BootInfo, `0x9E00` stack.
Constraint: stage2 must stay under 4608 bytes (build-checked).

Debug: single-letter progress marks on isa-debugcon port `0x402`
(`-device isa-debugcon,iobase=0x402`). Enable with `-chardev file,path=dbg.log,id=dbg`.

## UEFI path — `boot/uefi/`

* `uefi_boot.asm` — pure-NASM PE32+ `.efi` (ImageBase 0, one `.text`
  section, subsystem EFI_APPLICATION). No C, no libc.
* `uefi.inc` — Boot Services / System Table / GOP offsets per EDK2
  (offsets **include** the 24-byte table header: e.g. GetMemoryMap=56,
  AllocatePool=64, HandleProtocol=152, ExitBootServices=232,
  LocateHandleBuffer=312, LocateProtocol=320).
* Flow: ConOut prints → LocateProtocol(GOP) → SetMode(max) → read
  Mode (width/height/pitch/BGR32 assumed) → SFS chain
  (LocateHandleBuffer → HandleProtocol → OpenVolume → Open(`\KERNEL.BIN`)
  → Read loop to staging at `0x200000`) → AllocatePages(EfiLoaderData)
  for `0x100000` + low `0x8000` → GetMemoryMap (sizing + real call) →
  **translate** EFI descriptors to 24-byte BootInfo entries at `0x8C00`
  → fill BootInfo at `0x9000` (boot_type=1) → ExitBootServices →
  `jmp 0x100000` with `RDI = 0x9000`.
* MS x64 ABI discipline: 32-byte shadow space; arg5+ stored at `[rsp+32]`
  **after** subtracting shadow. Getting this wrong faults (verified!).
* SFS type map: EFI Conventional(7)→usable(1), ACPIReclaim(9)→3,
  ACPINVS(10)→4, Unusable(8)→5, else reserved(2).

## GRUB path — `boot/grub/` (boot_type = 2)

Third way in, same kernel out — for anyone who prefers a real bootloader.

* `multiboot.asm` — pure-NASM **hand-built ELF32** (`ET_EXEC`, one
  `PT_LOAD` at `0x200000`) with a Multiboot1 header (flags
  `ALIGN|MEMINFO`, no VIDEO flag — GRUB aborts entries whose requested
  video mode it dislikes). GRUB enters 32-bit protected mode with
  `EBX = multiboot_info*`. The stub is **self-relocating** (runs wherever
  GRUB parks it), converts Multiboot mmap/framebuffer/module info to the
  unified BootInfo ABI (`boot_type=2`), copies the `KERNEL.BIN` GRUB
  module to `0x100000`, switches to long mode (own tables at `0x70000`,
  framebuffer region mapped), and jumps to `kernel_entry(RDI=BootInfo*)`.
  Serial/VGA progress marks: `G` entry, `M` mmap, `F` framebuffer,
  `K` module copied, `L` long mode.
* `grub.cfg` — `multiboot /boot/nova_stub.bin` + `module /boot/KERNEL.BIN`,
  `gfxmode`+`gfxpayload=keep`, serial debug. Needs GRUB video modules +
  font for graphics; without them it boots text mode and the kernel
  correctly falls back to the VGA shell.
* Build: `make iso-grub` / `./build.sh iso-grub` (needs `grub-mkrescue`,
  i.e. Linux/WSL with `grub-pc-bin xorriso mtools`), run with
  `make run-grub` (`qemu -cdrom novaos-grub.iso`). Verified: GRUB menu →
  stub marks → kernel → drivers → VGA shell; GUI via BIOS/UEFI paths.

## Images — `tools/mkimg.py` (pure Python, no mtools)

* `floppy` — 1.44MB FAT12 matching the BPB (`rsvd=17`, FATs at LBA 17/26,
  root at 35, data at 49) + kernel file entry starting at cluster 2.
* `esp` — 64MB disk, MBR partition table (type `0xEF` at LBA 2048) with a
  FAT32 ESP: `/EFI/BOOT/BOOTX64.EFI`, `/KERNEL.BIN`, `/startup.nsh`.
  Must be ≥65525 clusters or EDK2 treats it as FAT16 and rejects the BPB.

## Known QEMU/host quirks (documented, worked around)

1. 16-bit `DIV` (mem or reg) can return a wrong remainder when the quotient
   is 0 on some TCG builds → stage2 uses subtraction-loop CHS math.
2. 32/64-bit loads from low-RAM BootInfo observed returning stale low
   bytes while byte loads are exact → framebuffer address is assembled
   byte-wise in `fb_init`; BootInfo is copied to kernel `.bss` at entry.
3. `-display none` screenshots only capture text mode; verify graphics via
   monitor `memsave` of the framebuffer physical address.
