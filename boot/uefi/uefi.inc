; NovaOS boot/uefi/uefi.inc - UEFI constants, GUIDs, struct offsets (x64)
; Offsets include the 24-byte EFI_TABLE_HEADER at the start of
; EFI_BOOT_SERVICES / EFI_SYSTEM_TABLE (EDK2 MdePkg layout).
%ifndef _UEFI_INC_
%define _UEFI_INC_

; --- EFI status ---
%define EFI_SUCCESS  0

; --- EFI_SYSTEM_TABLE offsets (64-bit) ---
; Hdr(24) Vendor(8) Revision(4)+pad(4) ConInHandle(8) ConIn(8)
; ConOutHandle(8) ConOut(8) StdErrHandle(8) StdErr(8) Runtime(8) Boot(8)
%define ST_CONOUT            64
%define ST_BOOTSERVICES      96

; --- EFI_BOOT_SERVICES offsets (bytes, header included) ---
%define BS_ALLOCATE_PAGES     40
%define BS_GET_MEMORY_MAP     56
%define BS_ALLOCATE_POOL      64
%define BS_HANDLE_PROTOCOL   152
%define BS_LOCATE_HANDLE_BUFFER 312
%define BS_LOCATE_PROTOCOL   320
%define BS_EXIT_BOOT_SERVICES 232

; Memory types
%define EfiLoaderData       2
%define EfiBootServicesData 4
%define EfiConventionalMemory 7
%define EfiACPIReclaimMemory 9

; AllocatePages types
%define AllocateAnyPages    0
%define AllocateAddress     2

; --- GOP GUID: {9042A9DE-23DC-4A38-96FB-7ADED080516A} ---
gop_guid:
    dd 0x9042A9DE
    dw 0x23DC, 0x4A38
    db 0x96, 0xFB, 0x7A, 0xDE, 0xD0, 0x80, 0x51, 0x6A

; --- SimpleFileSystem GUID: {0964E5B22-6459-11D2-8E39-00A0C969723B} ---
sfsp_guid:
    dd 0x0964E5B22
    dw 0x6459, 0x11D2
    db 0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B

; --- GOP struct offsets (EFI_GRAPHICS_OUTPUT_PROTOCOL) ---
%define GOP_QUERYMODE       0
%define GOP_SETMODE         8
%define GOP_BLT            16
%define GOP_MODE           24
; EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE offsets:
%define GOPM_MAXMODE       0
%define GOPM_MODE          4
%define GOPM_INFO          8
%define GOPM_SIZEINFO     16
%define GOPM_FB           24
%define GOPM_FBSIZE       32
; EFI_GRAPHICS_OUTPUT_MODE_INFORMATION offsets:
%define GOPI_VER           0
%define GOPI_WIDTH         4
%define GOPI_HEIGHT        8
%define GOPI_PIXFMT       12
%define GOPI_PITCH        32

; --- SimpleTextOut offsets ---
%define CONOUT_OUTPUTSTRING 8

; --- EFI_FILE_PROTOCOL offsets ---
%define FILE_OPEN           8
%define FILE_CLOSE         16
%define FILE_READ          32
%define FILE_GETINFO       64

%endif
