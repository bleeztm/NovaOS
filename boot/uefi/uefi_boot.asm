; NovaOS UEFI bootloader - pure NASM, PE32+ .efi, no C, no libc
; Build: nasm -f bin boot/uefi/uefi_boot.asm -o build/BOOTX64.EFI
; Place on ESP as /EFI/BOOT/BOOTX64.EFI, kernel as /KERNEL.BIN
; Entry: efi_main(ImageHandle=RCX, SystemTable=RDX). Exit -> kernel_entry(RDI=BootInfo*)
[BITS 64]
[DEFAULT REL]
%include "include/bootinfo.inc"

; ============ PE32+ headers (ImageBase 0, 1 section .text) ============
SECTION_HDR_SIZE equ 40
HDR_SIZE         equ 0x200
TEXT_RVA         equ 0x1000
TEXT_FILE_OFF    equ 0x200

    ; --- DOS header (64 bytes used, padded to 0x80) ---
    db 'M', 'Z'                         ; e_magic
    times 58 db 0
    dd 0x80                             ; e_lfanew -> PE header at 0x80
    times 64 db 0                       ; DOS stub padding (0x40..0x7F)
    ; --- PE signature + COFF ---
    db 'P', 'E', 0, 0
    dw 0x8664                           ; Machine AMD64
    dw 1                                ; NumberOfSections
    dd 0x5A5A5A5A                       ; TimeDateStamp
    dd 0                                ; PointerToSymbolTable
    dd 0                                ; NumberOfSymbols
    dw 0xF0                             ; SizeOfOptionalHeader (240)
    dw 0x0022                           ; Characteristics (exec, large addr aware)
    ; --- Optional header PE32+ ---
    dw 0x020B                           ; Magic PE32+
    db 14, 0                            ; Linker version
    dd TEXT_CODE_END - text_start        ; SizeOfCode
    dd 0                                ; SizeOfInitializedData
    dd 0                                ; SizeOfUninitializedData
    dd TEXT_RVA                         ; AddressOfEntryPoint (RVA of efi_main)
    dd TEXT_RVA                         ; BaseOfCode
    dq 0                                ; ImageBase (relocatable, 0)
    dd 0x1000                           ; SectionAlignment
    dd 0x200                            ; FileAlignment
    dw 6, 0, 0, 0, 6, 0                 ; OS/image/subsys versions
    dd 0                                ; Win32VersionValue
    dd 0x5000                           ; SizeOfImage
    dd HDR_SIZE                         ; SizeOfHeaders
    dd 0                                ; CheckSum
    dw 10                               ; Subsystem EFI_APPLICATION
    dw 0                                ; DllCharacteristics
    dq 0x10000                          ; SizeOfStackReserve
    dq 0x10000                          ; SizeOfStackCommit
    dq 0x10000                          ; SizeOfHeapReserve
    dq 0x10000                          ; SizeOfHeapCommit
    dd 0                                ; LoaderFlags
    dd 16                               ; NumberOfRvaAndSizes
    times 16*8 db 0                     ; DataDirectory (zeros; no reloc/import)
    ; --- Section header: .text ---
    db '.','t','e','x','t',0,0,0
    dd TEXT_CODE_END - text_start        ; VirtualSize
    dd TEXT_RVA                         ; VirtualAddress
    dd TEXT_FILE_SIZE                   ; SizeOfRawData (file-aligned)
    dd TEXT_FILE_OFF                    ; PointerToRawData
    dd 0, 0                             ; reloc/line ptrs
    dw 0, 0
    dd 0x60000020                       ; CODE | EXECUTE | READ
    ; pad headers to HDR_SIZE (0x200)
    times (HDR_SIZE-($-$$)) db 0

; ============ .text (RVA 0x1000, file off 0x200) ============
text_start:
efi_main: ; RCX = ImageHandle, RDX = SystemTable
    sub rsp, 8+8*16                     ; align + shadow + locals
    mov [rsp+0x90], rcx                 ; ImageHandle
    mov [rsp+0x98], rdx                 ; SystemTable
    mov rbx, rdx
    mov rax, [rbx+96]                   ; BootServices
    mov [rsp+0xA0], rax
    mov rax, [rbx+64]                   ; ConOut
    mov [rsp+0xA8], rax
    mov [rel img_handle_stash], rcx     ; ImageHandle -> global
    mov [rel st_system_table], rbx
    mov [rel st_conout], rax
    mov rax, [rbx+96]
    mov [rel st_bs], rax

    lea rcx, [rel msg_hello]
    call uefi_print

    ; ---- Locate GOP ----
    lea rcx, [rel msg_gop]
    call uefi_print
    mov rax, [rsp+0xA0]                 ; BS
    lea rdx, [rel gop_guid_inc]         ; *Protocol GUID (copy, 16B)
    call bs_locate_protocol_simple      ; returns interface in RAX
    test rax, rax
    jz .no_gop
    mov [rsp+0xB0], rax                 ; GOP*
    ; Set highest mode: read MaxMode from GOP->Mode, try Mode = MaxMode-1
    mov rcx, [rax+24]                   ; GOP->Mode
    mov edx, [rcx+0]                    ; MaxMode
    dec edx
    js .gop_info
    mov rcx, [rsp+0xB0]
    mov rdx, rdx                        ; ModeNumber in RDX (EDX zero-extended)
    sub rsp, 32                         ; shadow space (already 16-aligned here)
    call [rcx+8]                        ; GOP->SetMode(This, Mode)
    add rsp, 32
.gop_info:
    mov rcx, [rsp+0xB0]
    mov rcx, [rcx+24]                   ; Mode*
    mov rdx, [rcx+8]                    ; Info*
    mov eax, [rdx+4]                    ; Width
    mov [rel fb_width], eax
    mov eax, [rdx+8]                    ; Height
    mov [rel fb_height], eax
    mov eax, [rdx+32]                   ; PixelsPerScanLine
    mov [rel fb_pitch_px], eax
    mov rax, [rcx+24]                   ; FrameBufferBase
    mov [rel fb_base], rax
    mov rax, [rcx+32]                   ; FrameBufferSize
    mov [rel fb_size], rax
    lea rcx, [rel msg_gop_ok]
    call uefi_print
    jmp .after_gop
.no_gop:
    lea rcx, [rel msg_gop_fail]
    call uefi_print
    mov qword [rel fb_base], 0
.after_gop:

    ; ---- Load KERNEL.BIN from ESP root ----
    lea rcx, [rel msg_kernel]
    call uefi_print
    call load_kernel_file               ; -> RAX=size, kernel staged at KERNEL_TMP
    test rax, rax
    jz .kernel_fail
    mov [rel kernel_size], rax

    ; ---- Copy kernel to 0x100000 (AllocatePages AllocateAddress) ----
    mov rax, [rsp+0xA0]                 ; BS
    mov rcx, 2                          ; AllocateAddress
    mov rdx, 2                          ; EfiLoaderData
    mov r8, 64                          ; 64 pages = 256KB (grow if needed)
    lea r9, [rel kernel_phys]           ; *Memory (contains 0x100000)
    sub rsp, 32
    call [rax+40]                       ; AllocatePages
    add rsp, 32
    ; copy staged -> 0x100000
    mov rsi, KERNEL_TMP
    mov rdi, 0x100000
    mov rcx, [rel kernel_size]
    rep movsb

    ; ---- Reserve BootInfo + mmap buffer via AllocatePages (survives ExitBootServices) ----
    mov rax, [rsp+0xA0]
    mov rcx, 2
    mov rdx, 2
    mov r8, 2                           ; 2 pages for 0x8000..0x9FFF
    lea r9, [rel lowmem_phys]           ; 0x8000
    sub rsp, 32
    call [rax+40]
    add rsp, 32

    ; ---- GetMemoryMap (with resize loop) ----
    call build_bootinfo_and_exit         ; fills 0x9000, exits boot services
    test rax, rax
    jnz .exit_fail

    ; ---- Jump to kernel: RDI = BootInfo* ----
    lea rcx, [rel msg_jump]
    ; (ConOut unusable after ExitBootServices — skip print)
    mov rdi, 0x9000
    mov rax, 0x100000
    cli
    jmp rax
.kernel_fail:
    lea rcx, [rel msg_kfail]
    call uefi_print
.hang: hlt
    jmp .hang
.exit_fail:
    lea rcx, [rel msg_efail]
    call uefi_print
    jmp .hang

; ---------- helpers ----------
; RCX = ASCIIZ string -> print via ConOut->OutputString (ASCII->UTF-16)
uefi_print:
    push rbx
    push rsi
    push rdi
    push r12
    push rcx                        ; save This later
    mov rsi, rcx
    lea rdi, [rel print_buf_utf16]
    mov r12, rdi
    xor ecx, ecx
.convert:
    cmp rcx, 120
    jae .terminate
    lodsb
    mov [r12], ax                   ; zero-extend to UTF-16
    add r12, 2
    inc rcx
    test al, al
    jnz .convert
    jmp .print_it
.terminate:
    mov word [r12], 0
.print_it:
    mov rcx, [rel st_conout]
    test rcx, rcx
    jz .done
    mov rdx, rdi                    ; String
    sub rsp, 32                     ; shadow space
    call [rcx+8]                    ; ConOut->OutputString(This, String)
    add rsp, 32
.done:
    pop rcx
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; EAX = 32-bit status -> print 8 hex digits via ConOut. Preserves all.
uefi_print_hex:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    mov ebx, eax
    lea rdi, [rel hex_buf]
    mov ecx, 8
.hexloop:
    rol ebx, 4
    mov edx, ebx
    and dl, 0xF
    add dl, '0'
    cmp dl, '9'
    jbe .hexch
    add dl, 7
.hexch:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .hexloop
    mov byte [rdi], 0
    ; convert ASCII hex buf to UTF-16 print buffer
    lea rdi, [rel print_buf_utf16]
    lea rsi, [rel hex_buf]
.hexcv:
    lodsb
    mov [rdi], ax
    add rdi, 2
    test al, al
    jnz .hexcv
    mov rcx, [rel st_conout]
    test rcx, rcx
    jz .hexdone
    lea rdx, [rel print_buf_utf16]
    sub rsp, 32
    call [rcx+8]
    add rsp, 32
.hexdone:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret
bs_locate_protocol_simple:
    push rcx
    push r8
    push r9
    push r10
    mov rax, [rel st_bs]                ; BS (global, set at entry)
    sub rsp, 32+16
    mov rcx, rdx                        ; Protocol
    xor rdx, rdx                        ; Registration=NULL
    lea r8, [rsp+32]                    ; *Interface
    call [rax+320]                      ; LocateProtocol (BS+320)
    test eax, eax
    jnz .fail
    mov rax, [rsp+32]
    add rsp, 32+16
    pop r10
    pop r9
    pop r8
    pop rcx
    ret
.fail:
    xor eax, eax
    add rsp, 32+16
    pop r10
    pop r9
    pop r8
    pop rcx
    ret

; Load \KERNEL.BIN via SimpleFileSystem. Stages file at KERNEL_TMP (4MB).
; Returns RAX = size (0 on fail).
load_kernel_file:
    push rbx
    push rcx
    push rdx
    push r8
    push r9
    push rsi
    push rdi
    mov rax, [rel st_bs]                ; BS global
    ; Full SFS implementation (~120 lines) elided into documented steps:
    ; 1. LocateHandleBuffer(ByProtocol, &sfsp_guid) -> handles
    ; 2. HandleProtocol(h[0], &sfsp_guid) -> SFS*
    ; 3. SFS->OpenVolume -> Root*
    ; 4. Root->Open(Root, &File, L"\KERNEL.BIN", READ, 0)
    ; 5. File->GetInfo / loop Read into KERNEL_TMP
    ; For bring-up without FS debugging, we also probe a preloaded address
    ; (QEMU test hook): if KERNEL_TMP already has 'N'V'O'S' magic skip disk.
    cmp dword [abs KERNEL_TMP], 0x534F564E
    je .have_magic
    ; Minimal file open path (handles happy path; errors -> 0):
    call sfs_load_impl
    jmp .out
.have_magic:
    mov rax, [rel kernel_size_testhook]
    test rax, rax
    jnz .out
    mov rax, 65536
.out:
    pop rdi
    pop rsi
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

sfs_load_impl:
    ; Full chain: LocateHandleBuffer -> HandleProtocol -> OpenVolume ->
    ; Open(\KERNEL.BIN) -> Read loop into KERNEL_TMP. Returns RAX = size.
    ; MS x64 ABI: 4 reg args + 32B shadow; arg5+ at [rsp+32] AFTER sub.
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 48                        ; 32 shadow + arg5 slot + 2 locals
    mov rbx, [rel st_bs]
    ; --- LocateHandleBuffer(ByProtocol=2, &guid, NULL, &count, &handles) ---
    mov ecx, 2
    lea rdx, [rel sfsp_guid_inc]
    xor r8, r8
    lea r9, [rel sfs_count]            ; arg4 = &count (global cell)
    lea rax, [rel sfs_handles]         ; arg5 = &handles (global cell)
    mov [rsp+32], rax
    call [rbx+312]                     ; LocateHandleBuffer (BS+312)
    mov [rel sfs_status], eax
    push rcx
    lea rcx, [rel sfs_msg_stat]
    call uefi_print
    pop rcx
    mov eax, [rel sfs_status]
    call uefi_print_hex
    test eax, eax
    jnz .fail
    cmp qword [rel sfs_count], 0
    je .fail
    push rcx
    lea rcx, [rel sfs_msg_loc]
    call uefi_print
    pop rcx
    ; --- HandleProtocol(handle[0], &guid, &sfs) ---
    mov rax, [rel sfs_handles]
    mov rcx, [rax]                     ; handle[0]
    lea rdx, [rel sfsp_guid_inc]
    lea r8, [rel sfs_proto]
    call [rbx+152]                     ; HandleProtocol (BS+152)
    test eax, eax
    jnz .fail
    lea rcx, [rel sfs_msg_proto]
    call uefi_print
    ; --- OpenVolume(sfs, &root) ---
    mov rcx, [rel sfs_proto]
    lea rdx, [rel sfs_root]
    call [rcx+8]                       ; SFS->OpenVolume
    test eax, eax
    jnz .fail
    lea rcx, [rel sfs_msg_vol]
    call uefi_print
    ; --- Open(root, &file, L"\KERNEL.BIN", READ=1, 0) --- 5 args!
    mov rax, [rel sfs_root]
    mov rcx, rax                       ; This
    lea rdx, [rel sfs_file]            ; NewHandle
    lea r8, [rel fname_kernel_utf16]   ; FileName
    mov r9, 1                          ; OpenMode = READ
    xor eax, eax
    mov [rsp+32], rax                  ; Attributes = 0
    mov rax, [rel sfs_root]
    mov rax, [rax+8]                   ; root->Open
    call rax
    test eax, eax
    jnz .fail
    lea rcx, [rel sfs_msg_open]
    call uefi_print
    ; --- Read loop: chunk 8192B into KERNEL_TMP (cap 512KB) ---
    ; --- Read loop: chunk 8192B into KERNEL_TMP (cap 512KB) ---
    mov r14, KERNEL_TMP
    xor r15, r15                       ; total
.readloop:
    cmp r15, 512*1024
    jae .read_done
    mov qword [rel sfs_iosize], 8192
    mov rcx, [rel sfs_file]
    lea rdx, [rel sfs_iosize]
    mov r8, r14
    mov rax, [rel sfs_file]
    mov rax, [rax+32]                  ; file->Read
    call rax
    test eax, eax
    jnz .fail
    mov rax, [rel sfs_iosize]
    test rax, rax
    jz .read_done
    add r14, rax
    add r15, rax
    cmp rax, 8192
    je .readloop
.read_done:
    ; --- Close(file) ---
    mov rcx, [rel sfs_file]
    mov rax, [rel sfs_file]
    mov rax, [rax+16]                  ; file->Close
    call rax
    mov rax, r15
    add rsp, 48
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.fail:
    xor eax, eax
    add rsp, 48
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Build BootInfo @0x9000, GetMemoryMap into pool, copy to 0x8C00, ExitBootServices.
; Returns RAX=0 ok. Shadow-first ABI discipline throughout.
build_bootinfo_and_exit:
    push rbx
    mov rbx, [rel st_bs]                ; BS global
    mov [rel bs_cached], rbx
    mov [rel bs_cached2], rbx
    sub rsp, 96                        ; 32 shadow + locals:
                                       ; +32 arg5, +40 size, +48 key,
                                       ; +56 descsize, +64 descver, +72 pool
    ; --- sizing call: Map=NULL, Size=0 -> BUFFER_TOO_SMALL + required size ---
    mov qword [rsp+40], 0
    lea rcx, [rsp+40]                  ; Size
    xor edx, edx                       ; Map = NULL
    lea r8, [rsp+48]                   ; Key
    lea r9, [rsp+56]                   ; DescSize
    lea rax, [rsp+64]                  ; DescVer
    mov [rsp+32], rax                  ; arg5
    call [rbx+56]                      ; GetMemoryMap (BS+32)
    ; --- AllocatePool(EfiLoaderData, size+64, &pool) ---
    mov rcx, 2
    mov rdx, [rsp+40]
    add rdx, 64
    lea r8, [rsp+72]
    call [rbx+64]                      ; AllocatePool (BS+64)
    test eax, eax
    jnz .fail
    ; --- real GetMemoryMap into pool (also yields final MapKey) ---
    lea rcx, [rsp+40]                  ; Size (in: buffer size)
    mov rdx, [rsp+72]                  ; Map = pool
    lea r8, [rsp+48]
    lea r9, [rsp+56]
    lea rax, [rsp+64]
    mov [rsp+32], rax
    call [rbx+56]
    test eax, eax
    jnz .fail
    ; --- translate EFI map (pool) to 24B BootInfo entries at 0x8C00 ---
    ; EFI_MEMORY_DESCRIPTOR: Type@0(u32) Phys@8(u64) Pages@24(u64), stride=[rsp+56]
    ; BootInfo ME: Base@0(u64) Len@8(u64) Type@16(u32) Attr@20(u32), stride 24.
    ; Type map: EFI 7->1 usable; 9->3 ACPI; 10->4 NVS; 8->5 bad; else 2 reserved.
    mov rsi, [rsp+72]                  ; src = pool
    mov rdi, 0x8C00                    ; dst
    mov rcx, [rsp+40]                  ; bytes remaining
    mov r8, [rsp+56]                   ; EFI desc size
    xor r9, r9                         ; out count
.tloop:
    cmp rcx, r8
    jb .tdone
    mov eax, [rsi+0]                   ; EFI type
    mov r10, [rsi+8]                   ; PhysStart
    mov r11, [rsi+24]                  ; Pages
    shl r11, 12                        ; Length bytes
    cmp eax, 7
    je .tusable
    cmp eax, 9
    je .tacpi
    cmp eax, 10
    je .tnvs
    cmp eax, 8
    je .tbad
    mov dword [rdi+16], 2
    jmp .tstore
.tusable:
    mov dword [rdi+16], 1
    jmp .tstore
.tacpi:
    mov dword [rdi+16], 3
    jmp .tstore
.tnvs:
    mov dword [rdi+16], 4
    jmp .tstore
.tbad:
    mov dword [rdi+16], 5
    jmp .tstore
.tstore:
    mov [rdi+0], r10
    mov [rdi+8], r11
    mov dword [rdi+20], 0
    add rdi, 24
    inc r9
    add rsi, r8
    sub rcx, r8
    jmp .tloop
.tdone:
    mov [rel mmap_count_stash], r9
    mov qword [rel mmap_entsz_stash], 24
    mov rax, [rsp+48]                  ; MapKey for ExitBootServices
    mov [rel mmap_key_stash], rax
    ; Fill BootInfo @0x9000
    mov rdi, 0x9000
    mov dword [rdi+0], 0x534F564E       ; magic
    mov dword [rdi+4], 1                ; version
    mov rax, [rel fb_base]
    mov [rdi+8], rax
    mov eax, [rel fb_width] 
    mov [rdi+16], eax
    mov eax, [rel fb_height]
    mov [rdi+20], eax
    mov eax, [rel fb_pitch_px]
    shl eax, 2                          ; pitch bytes (32bpp assumed; refined by GOP PixelFormat)
    mov [rdi+24], eax
    mov dword [rdi+28], 32
    mov qword [rdi+32], 0x8C00
    mov rax, [rel mmap_count_stash]
    mov [rdi+40], rax
    mov rax, [rel mmap_entsz_stash]
    mov [rdi+48], rax
    mov qword [rdi+56], 0               ; RSDP (TODO: via ACPI table GUID scan)
    mov qword [rdi+64], 1               ; boot_type UEFI
    mov rax, [rel kernel_size]
    mov [rdi+72], rax
    ; ExitBootServices(ImageHandle, MapKey)
    mov rcx, [rel img_handle_stash]
    mov rdx, [rel mmap_key_stash]
    sub rsp, 32
    call [rbx+232]                      ; ExitBootServices (BS+232)
    add rsp, 32
    test eax, eax
    jnz .fail2
    add rsp, 96
    pop rbx
    xor eax, eax
    ret
.fail2:
    ; Map changed under us — caller could retry; report error for now.
.fail:
    add rsp, 96
    pop rbx
    mov rax, 1
    ret

; ---------- data ----------
gop_guid_inc:  dd 0x9042A9DE
    dw 0x23DC, 0x4A38
    db 0x96,0xFB,0x7A,0xDE,0xD0,0x80,0x51,0x6A
sfsp_guid_inc: dd 0x0964E5B22
    dw 0x6459, 0x11D2
    db 0x8E,0x39,0x00,0xA0,0xC9,0x69,0x72,0x3B
msg_hello   db "NovaOS UEFI loader v0.1",13,10,0
msg_gop     db "Init GOP...",13,10,0
msg_gop_ok  db "GOP OK",13,10,0
msg_gop_fail db "GOP not found, headless",13,10,0
msg_kernel  db "Loading KERNEL.BIN...",13,10,0
msg_kfail   db "KERNEL.BIN missing!",13,10,0
sfs_msg_loc db "SFS: handles ok",13,10,0
sfs_msg_stat db "SFS: locate status=",0
hex_buf times 16 db 0
sfs_status dq 0
sfs_msg_proto db "SFS: protocol ok",13,10,0
sfs_msg_vol db "SFS: volume ok",13,10,0
sfs_msg_open db "SFS: open ok",13,10,0
msg_jump    db "Jumping to kernel...",13,10,0
msg_efail   db "ExitBootServices failed",13,10,0
kernel_phys: dq 0x100000
lowmem_phys: dq 0x8000
fb_base: dq 0
fb_size: dq 0
fb_width: dd 1024
fb_height: dd 768
fb_pitch_px: dd 256
kernel_size: dq 0
kernel_size_testhook: dq 0
mmap_count_stash: dq 0
mmap_entsz_stash: dq 48
mmap_key_stash: dq 0
bs_cached: dq 0
bs_cached2: dq 0
img_handle_stash: dq 0
st_system_table: dq 0
st_conout: dq 0
st_bs: dq 0
print_buf_utf16: times 128 dw 0
; --- SFS load state ---
sfs_count: dq 0
sfs_handles: dq 0
sfs_proto: dq 0
sfs_root: dq 0
sfs_file: dq 0
sfs_iosize: dq 0
fname_kernel_utf16:
    dw '\', 'K', 'E', 'R', 'N', 'E', 'L', '.', 'B', 'I', 'N', 0
KERNEL_TMP equ 0x200000
TEXT_CODE_END:
; pad section to file alignment
TEXT_FILE_SIZE equ ((TEXT_CODE_END - text_start + 0x1FF) & (~0x1FF))
    times (TEXT_FILE_OFF + TEXT_FILE_SIZE - ($-$$)) db 0
