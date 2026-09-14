; NovaOS - Unified BootInfo ABI (v1)
; Passed in RDI to kernel_entry. Same layout for BIOS (VBE) and UEFI (GOP).
; All integers little-endian. Struct is 80 bytes, 8-byte aligned.

%ifndef _BOOTINFO_INC_
%define _BOOTINFO_INC_

BOOTINFO_MAGIC      equ 0x534F564E   ; 'NVOS' ('N'=0x4E,'V'=0x56,'O'=0x4F,'S'=0x53)
BOOTINFO_VERSION    equ 0x00000001

BOOTINFO_BOOT_BIOS  equ 0
BOOTINFO_BOOT_UEFI  equ 1

; --- struct offsets ---
%define BI_MAGIC          0    ; u32 magic
%define BI_VERSION        4    ; u32 version
%define BI_FB_ADDR        8    ; u64 framebuffer phys addr
%define BI_FB_WIDTH       16   ; u32 width px
%define BI_FB_HEIGHT      20   ; u32 height px
%define BI_FB_PITCH       24   ; u32 bytes per scanline
%define BI_FB_BPP         28   ; u32 bits per pixel
%define BI_MMAP_ADDR      32   ; u64 phys addr of mem map array
%define BI_MMAP_COUNT     40   ; u64 entry count
%define BI_MMAP_ENTSIZE   48   ; u64 entry size (24)
%define BI_RSDP           56   ; u64 ACPI RSDP phys addr (0 if none)
%define BI_BOOT_TYPE      64   ; u64 0=BIOS 1=UEFI
%define BI_KERNEL_SIZE    72   ; u64 kernel size bytes (optional)
%define BI_SIZE           80

; --- memory map entry (24 bytes, UEFI-style, E820 mapped to it) ---
%define ME_BASE           0    ; u64 base
%define ME_LEN            8    ; u64 length
%define ME_TYPE           16   ; u32: 1=usable,2=resvd,3=acpi,4=nvs,5=bad,else resvd
%define ME_ATTR           20   ; u32 (unused on BIOS)
%define ME_SIZE           24

; MEMORY types (match UEFI):
%define MEM_USABLE        1
%define MEM_RESERVED      2
%define MEM_ACPI          3

%endif
