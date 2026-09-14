; NovaOS GRUB multiboot stub - Multiboot1, pure NASM, hand-built ELF32
; Build: nasm -f bin boot/grub/multiboot.asm -o build/nova_stub.bin
; The file is a minimal ET_EXEC ELF32 (written by hand, like our PE32+
; UEFI loader) with one PT_LOAD segment at 0x200000, so GRUB's standard
; ELF path places it exactly. (The ADDR-kludge flat form was observed
; being parked elsewhere by GRUB 2.06, so ELF it is.)
; GRUB enters 32-bit protected mode with EBX = multiboot_info*. The stub
; converts Multiboot info to the unified BootInfo ABI, copies the
; KERNEL.BIN GRUB module to 0x100000, switches to long mode, and jumps
; to kernel_entry(RDI=BootInfo*).
; grub.cfg loads: multiboot /boot/nova_stub.bin + module /boot/KERNEL.BIN
[BITS 32]
[ORG 0x200000]

STUB_LOAD   equ 0x200000
BOOTINFO    equ 0x9000
MMAP_BUF    equ 0x8C00
KERNEL_PHYS equ 0x100000
PML4_ADDR   equ 0x70000
GRUB_STACK  equ 0x90000

; ---- ELF32 header (52 bytes at file offset 0) ----
    db 0x7F, 'E', 'L', 'F'              ; magic
    db 1, 1, 1, 0, 0                    ; 32-bit, LE, v1, SysV, ABIver
    times 7 db 0                        ; ident pad (16 bytes total)
    dw 2                                ; e_type = EXEC
    dw 3                                ; e_machine = 386
    dd 1                                ; e_version
    dd grub_entry                       ; e_entry (absolute, ORG below applies)
    dd 52                               ; e_phoff
    dd 0                                ; e_shoff
    dd 0                                ; e_flags
    dw 52                               ; e_ehsize
    dw 32                               ; e_phentsize
    dw 1                                ; e_phnum
    dw 0, 0, 0                          ; e_shentsize, e_shnum, e_shstrndx
; ---- Program header (32 bytes): one PT_LOAD covering the whole file ----
    dd 1                                ; p_type = LOAD
    dd 0                                ; p_offset
    dd STUB_LOAD                        ; p_vaddr
    dd STUB_LOAD                        ; p_paddr
    dd stub_end - STUB_LOAD             ; p_filesz (forward ref, resolved)
    dd stub_end - STUB_LOAD             ; p_memsz
    dd 7                                ; p_flags = RWE
    dd 0x1000                           ; p_align

; (code below runs at file_offset + STUB_LOAD; header bytes above are
; never referenced at runtime, so the top-placed ORG is exact for code)
; ---- Multiboot1 header (must lie in first 8KB of the loaded image) ----
MB_MAGIC    equ 0x1BADB002
; No VIDEO flag (GRUB aborts entries whose requested mode it dislikes);
; no ADDR flag either (ELF paddr is authoritative). ALIGN|MEMINFO only.
MB_FLAGS    equ (1<<0)|(1<<1)
MB_CHECK    equ -(MB_MAGIC + MB_FLAGS)
    dd MB_MAGIC, MB_FLAGS, MB_CHECK
mb_header:

grub_entry:
    cli
    mov esp, GRUB_STACK
    ; Self-relocate: GRUB may ignore load_addr (observed: image parked
    ; high instead of 0x200000). Copy ourselves to the link address, then
    ; run there so all absolute addresses work. Position-independent head.
    call .getbase
.getbase:
    pop ebp                                ; EBP = loaded addr of .getbase
    sub ebp, (.getbase - STUB_LOAD)        ; EBP = actual load base
    cmp ebp, STUB_LOAD
    je .main
    push ebx                               ; save multiboot ptr across copy
    mov esi, ebp
    mov edi, STUB_LOAD
    mov ecx, (stub_end - STUB_LOAD)
    cld
    rep movsb
    pop ebx
    jmp STUB_LOAD + (.main - STUB_LOAD)
.main:
    mov ebp, esp
    cld
    mov al, 'G'
    call s_putchar
    push ebx                                ; multiboot info ptr
    ; ensure A20 (GRUB normally does, belt and suspenders)
    in al, 0x92
    or al, 2
    out 0x92, al
    pop ebx
    mov esi, ebx                            ; ESI = mboot info

    ; defaults (VGA shell fallback if no framebuffer)
    mov dword [fb_w], 1024
    mov dword [fb_h], 768
    mov dword [fb_bpp], 32
    mov dword [fb_addr_lo], 0
    mov dword [fb_addr_hi], 0
    mov dword [fb_pitch], 4096
    mov dword [mmap_count], 0

    ; ---- memory map (flags bit 6) ----
    mov eax, [esi+0]                        ; info flags
    test eax, 1<<6
    jz .nommap
    mov ecx, [esi+44]                       ; mmap_length
    mov edx, [esi+48]                       ; mmap_addr
    mov edi, MMAP_BUF
    xor ebx, ebx                            ; out count
.mmaploop:
    cmp ecx, 24
    jb .mmapdone
    mov eax, [edx+20]                       ; multiboot type (1 = available)
    cmp eax, 1
    je .musable
    mov dword [edi+16], 2
    jmp .mstore
.musable:
    mov dword [edi+16], 1
.mstore:
    mov eax, [edx+4]                        ; base low
    mov [edi+0], eax
    mov eax, [edx+8]                        ; base high
    mov [edi+4], eax
    mov eax, [edx+12]                       ; len low
    mov [edi+8], eax
    mov eax, [edx+16]                       ; len high
    mov [edi+12], eax
    mov dword [edi+20], 0
    add edi, 24
    inc ebx
    cmp ebx, 64                             ; cap 64 entries
    jae .mmapdone
    mov eax, [edx+0]                        ; entry size
    add eax, 4
    add edx, eax
    sub ecx, eax
    jmp .mmaploop
.mmapdone:
    mov [mmap_count], ebx
    mov al, 'M'
    call s_putchar
    jmp .fbinfo
.nommap:
    ; fallback: 0..640K + 1MB..(1MB+upper*1K) usable
    mov edi, MMAP_BUF
    mov dword [edi+0], 0x00000
    mov dword [edi+4], 0
    mov dword [edi+8], 0xA0000
    mov dword [edi+12], 0
    mov dword [edi+16], 1
    mov dword [edi+20], 0
    mov eax, [esi+8]                        ; mem_upper (KB)
    shl eax, 10                             ; bytes
    mov [edi+24+8], eax
    mov dword [edi+24+0], 0x100000
    mov dword [edi+24+4], 0
    mov dword [edi+24+12], 0
    mov dword [edi+24+16], 1
    mov dword [edi+24+20], 0
    mov dword [mmap_count], 2

.fbinfo:
    ; ---- framebuffer (flags bit 12); type 0=indexed 1=RGB 2=EGA text ----
    mov eax, [esi+0]                        ; info flags
    push esi
    call s_print_hex32
    mov al, ':'
    call s_putchar
    pop esi
    mov eax, [esi+0]
    test eax, 1<<12
    jz .nomods
    push esi
    movzx eax, byte [esi+109]               ; fb_type
    call s_print_hex8
    movzx eax, byte [esi+108]               ; bpp
    call s_print_hex8
    pop esi
    mov al, [esi+109]                       ; want RGB direct (1)
    cmp al, 1
    jne .nomods
.fbok:
    mov al, [esi+108]                       ; bpp
    cmp al, 24
    je .bppok
    cmp al, 32
    jne .nomods
.bppok:
    mov eax, [esi+88]                       ; fb_addr low
    mov [fb_addr_lo], eax
    mov eax, [esi+92]                       ; fb_addr high
    mov [fb_addr_hi], eax
    mov eax, [esi+96]                       ; pitch
    mov [fb_pitch], eax
    mov eax, [esi+100]
    mov [fb_w], eax
    mov eax, [esi+104]
    mov [fb_h], eax
    movzx eax, byte [esi+108]
    mov [fb_bpp], eax
    mov al, 'F'
    call s_putchar

.nomods:
    ; ---- copy KERNEL.BIN module (mods[0]) to 0x100000 ----
    mov eax, [esi+0]
    test eax, 1<<3
    jz .nomod
    mov ecx, [esi+20]                       ; mods_count
    test ecx, ecx
    jz .nomod
    mov edx, [esi+24]                       ; mods_addr
    mov esi, [edx+0]                        ; mod_start
    mov ecx, [edx+4]                        ; mod_end
    sub ecx, esi                            ; size
    mov [kern_size], ecx
    mov edi, KERNEL_PHYS
    rep movsb
    mov al, 'K'
    call s_putchar
    jmp .bootinfo
.nomod:
    mov dword [kern_size], 0
    mov al, '!'
    call s_putchar

.bootinfo:
    ; ---- build BootInfo @0x9000 ----
    mov edi, BOOTINFO
    mov dword [edi+0], 0x534F564E
    mov dword [edi+4], 1
    mov eax, [fb_addr_lo]
    mov [edi+8], eax
    mov eax, [fb_addr_hi]
    mov [edi+12], eax
    mov eax, [fb_w]
    mov [edi+16], eax
    mov eax, [fb_h]
    mov [edi+20], eax
    mov eax, [fb_pitch]
    mov [edi+24], eax
    mov eax, [fb_bpp]
    mov [edi+28], eax
    mov dword [edi+32], MMAP_BUF
    mov dword [edi+36], 0
    mov eax, [mmap_count]
    mov dword [edi+40], eax
    mov dword [edi+44], 0
    mov dword [edi+48], 24
    mov dword [edi+52], 0
    mov dword [edi+56], 0
    mov dword [edi+60], 0
    mov dword [edi+64], 2                   ; boot_type = GRUB
    mov dword [edi+68], 0
    mov eax, [kern_size]
    mov [edi+72], eax
    mov dword [edi+76], 0

    ; ---- long mode: identity 0..64MB + framebuffer region ----
    mov edi, PML4_ADDR
    mov ecx, 0x3000
    xor eax, eax
    rep stosd
    mov eax, PML4_ADDR+0x1000+0x03
    mov [PML4_ADDR], eax
    mov [PML4_ADDR+0x800], eax
    mov eax, PML4_ADDR+0x2000+0x03
    mov [PML4_ADDR+0x1000], eax
    mov edi, PML4_ADDR+0x2000
    mov eax, 0x00000083
    mov ecx, 32
.fill_pd:
    mov [edi], eax
    add eax, 0x200000
    add edi, 8
    loop .fill_pd
    ; map 1GB region with the framebuffer
    mov eax, [fb_addr_lo]
    test eax, eax
    jz .fbmap_done
    shr eax, 30
    cmp eax, 0
    je .fbmap_done
    mov ebx, eax
    shl ebx, 30
    mov edi, 0x73000
    mov ecx, 512
.fill_pd2:
    mov eax, ebx
    or eax, 0x83
    mov [edi], eax
    mov dword [edi+4], 0
    add ebx, 0x200000
    add edi, 8
    dec ecx
    jnz .fill_pd2
    mov eax, [fb_addr_lo]
    shr eax, 30
    mov ebx, eax
    mov eax, 0x73000+0x03
    mov [PML4_ADDR+0x1000+ebx*8], eax
.fbmap_done:
    mov eax, cr4
    or eax, 1<<5
    mov cr4, eax
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1<<8
    wrmsr
    mov eax, PML4_ADDR
    mov cr3, eax
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax
    lgdt [gdt64_ptr]
    mov al, 'L'
    call s_putchar
    jmp 0x08:lm64

[BITS 64]
lm64:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov rsp, 0x90000
    mov rdi, BOOTINFO
    mov rax, KERNEL_PHYS
    jmp rax

; ---- data ----
[BITS 32]
; AL = char -> COM1 (32-bit polled serial, for bring-up tracing)
; ALSO writes to VGA text row 24 (always works, no polling) as vga_mark.
s_putchar:
    push edx
    push ebx
    push eax
    movzx ebx, byte [rel vga_pos]
    mov edx, 0xB8000
    mov [edx+ebx*2], al
    mov byte [edx+ebx*2+1], 0x4F
    inc byte [rel vga_pos]
    pop eax
    push eax
    mov dx, 0x3FD
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    pop eax
    push eax
    mov dx, 0x3F8
    out dx, al
    pop eax
    pop ebx
    pop edx
    ret
vga_pos db 0

; EAX -> 8 hex chars on serial. Preserves all except EAX content.
s_print_hex32:
    push eax
    push ebx
    push ecx
    mov ebx, eax
    mov ecx, 8
.hh:
    rol ebx, 4
    mov al, bl
    and al, 0xF
    add al, '0'
    cmp al, '9'
    jbe .hd
    add al, 7
.hd:
    call s_putchar
    dec ecx
    jnz .hh
    pop ecx
    pop ebx
    pop eax
    ret

; AL = byte value -> 2 hex chars. Preserves EBX/ECX.
s_print_hex8:
    push eax
    push ebx
    push ecx
    mov bl, al
    shr al, 4
    call .hnib
    mov al, bl
    and al, 0xF
    call .hnib
    pop ecx
    pop ebx
    pop eax
    ret
.hnib:
    add al, '0'
    cmp al, '9'
    jbe .ho
    add al, 7
.ho:
    call s_putchar
    ret

ALIGN 8
gdt64:
    dq 0x0000000000000000
    dq 0x00209A0000000000                 ; code64
    dq 0x0000920000000000                 ; data
gdt64_end:
gdt64_ptr:
    dw gdt64_end - gdt64 - 1
    dq gdt64
fb_addr_lo dd 0
fb_addr_hi dd 0
fb_w       dd 1024
fb_h       dd 768
fb_bpp     dd 32
fb_pitch   dd 4096
mmap_count dd 0
kern_size  dd 0
stub_end:
