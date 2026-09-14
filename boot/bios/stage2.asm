; NovaOS stage2 - FAT12 KERNEL.BIN loader + VBE + E820 + PM -> LM trampoline
; Load address: 0x7E00 (loaded by MBR). Assembled flat: nasm -f bin -o build/stage2.bin
; Layout (all below 640KB, clear of stage2 image @0x7E00 and stack @0x9E00):
; VBE info @0x5000, VBE mode @0x5200, E820 map @0x5400, BootInfo @0x9000,
; PML4 @0x70000. FAT scratch: root @0x6000, table @0x1000, sector @0x3000.
; Floppy layout (rsvd=17): FAT1 @ LBA17, FAT2 @ LBA26, root @ LBA35 (14s), data @ LBA49.
; NOTE: stage2 must stay under 4608 bytes (else it hits BootInfo @0x9000).
[BITS 16]
[ORG 0x7E00]
%include "include/bootinfo.inc"

STAGE2_BASE     equ 0x7E00
BOOTINFO_ADDR   equ 0x9000
VBE_INFO        equ 0x5000
VBE_MODEINFO    equ 0x5200
MMAP_ADDR       equ 0x5400
PML4_ADDR       equ 0x70000
KERNEL_PHYS     equ 0x100000
KERNEL_BOUNCE   equ 0x10000     ; (unused — kernel written via FS:EDI directly)
FAT_BUF         equ 0x6000      ; root-dir scratch (14 sectors)
FAT_TAB         equ 0x1000      ; FAT table scratch (9 sectors)
SEC_SCRATCH     equ 0x3000      ; single-sector scratch
STAGE2_STACK    equ 0x9E00      ; real-mode stack (above 16-sector load area)
FAT_LBA         equ 17          ; FAT1 start (rsvd=17)
ROOT_LBA        equ 35          ; root dir start
DATA_LBA        equ 49          ; cluster 2 start

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, STAGE2_STACK
    sti
    mov [boot_drive], dl
    mov al, 'C'
    call dbg_mark
    mov si, msg_stage2
    call print16
    call enable_a20
    call get_memory_map_e820
    mov al, 'D'
    call dbg_mark
    call vbe_setup               ; fills [vbe_width/height/pitch/bpp/fbaddr]
    mov al, 'E'
    call dbg_mark
    call fat12_load_kernel       ; loads KERNEL.BIN to 1MB via unreal mode
    mov al, 'G'
    call dbg_mark

    ; --- build BootInfo at 0x9000 ---
    mov di, BOOTINFO_ADDR
    mov dword [di+BI_MAGIC], BOOTINFO_MAGIC
    mov dword [di+BI_VERSION], BOOTINFO_VERSION
    mov eax, [vbe_fbaddr]
    mov [di+BI_FB_ADDR], eax
    mov dword [di+BI_FB_ADDR+4], 0
    mov eax, [vbe_width] 
    mov [di+BI_FB_WIDTH], eax
    mov eax, [vbe_height]
    mov [di+BI_FB_HEIGHT], eax
    mov eax, [vbe_pitch] 
    mov [di+BI_FB_PITCH], eax
    mov eax, [vbe_bpp]   
    mov [di+BI_FB_BPP], eax
    mov dword [di+BI_MMAP_ADDR], MMAP_ADDR
    mov dword [di+BI_MMAP_ADDR+4], 0
    mov eax, [mmap_count]
    mov dword [di+BI_MMAP_COUNT], eax
    mov dword [di+BI_MMAP_COUNT+4], 0
    mov dword [di+BI_MMAP_ENTSIZE], 24
    mov dword [di+BI_MMAP_ENTSIZE+4], 0
    mov dword [di+BI_RSDP], 0
    mov dword [di+BI_RSDP+4], 0
    mov dword [di+BI_BOOT_TYPE], BOOTINFO_BOOT_BIOS
    mov dword [di+BI_BOOT_TYPE+4], 0
    mov eax, [kernel_sectors]
    shl eax, 9
    mov dword [di+BI_KERNEL_SIZE], eax
    mov dword [di+BI_KERNEL_SIZE+4], 0

    mov si, msg_pm
    call print16

    ; --- enter protected mode ---
    cli
    lgdt [gdt32_desc]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp CODE32_SEL:pm32

; ============ 16-bit helpers ============
print16:
    pusha
.l: lodsb
    test al, al
    jz .d
    mov ah, 0x0E
    xor bh, bh
    int 0x10
    jmp .l
.d: popa
    ret

enable_a20:
    ; Try BIOS 0x15/0x2401, then port 0x92, then 8042
    mov ax, 0x2401
    int 0x15
    in al, 0x92
    or al, 2
    out 0x92, al
    ret

; E820 -> MMAP_ADDR, count -> [mmap_count], converts to 24B UEFI-style entries
get_memory_map_e820:
    xor ebx, ebx
    mov di, MMAP_ADDR
    mov dword [mmap_count], 0
.e820loop:
    mov eax, 0xE820
    mov ecx, 24
    mov edx, 0x534D4150
    int 0x15
    jc .done
    cmp eax, 0x534D4150
    jne .done
    ; BIOS returns: base(8) len(8) type(4) attr(4) at ES:DI — already laid out
    add di, 24
    inc dword [mmap_count]
    test ebx, ebx
    jnz .e820loop
.done:
    cmp dword [mmap_count], 0
    jne .ok
    ; fallback: single 1MB..4MB usable entry
    mov di, MMAP_ADDR
    mov dword [di+0], 0x100000
    mov dword [di+4], 0
    mov dword [di+8], 0x300000
    mov dword [di+12], 0
    mov dword [di+16], 1
    mov dword [di+20], 0
    mov dword [mmap_count], 1
.ok: ret

; VBE mode picker: tries linear 24bpp modes, validates each before setting.
; A mode is accepted only if: 0x4F01 succeeds, ModeAttributes bit7 (LFB)
; is set, MemoryModel is packed(4)/direct(6), bpp >= 15, and 0x4F02+LFB
; succeeds. (Some VBE BIOSes number modes differently; blindly trusting a
; mode number can land the display in a planar mode while we draw linear.)
; Else fbaddr=0 and the kernel falls back to the VGA text shell.
vbe_setup:
    mov dword [vbe_width], 1024
    mov dword [vbe_height], 768
    mov dword [vbe_bpp], 32
    mov dword [vbe_fbaddr], 0
    mov dword [vbe_pitch], 4096
    ; get VBE controller info (ES:DI = buffer; reset ES defensively)
    push ax
    xor ax, ax
    mov es, ax
    pop ax
    mov ax, 0x4F00
    mov di, VBE_INFO
    int 0x10
    push ax
    mov al, 'e'
    call dbg_mark
    pop ax
    push ax
    call dbg_ax
    pop ax
    cmp ax, 0x004F
    jne .novesa
    mov si, vbe_modes
.nextmode:
    mov cx, [si]                           ; candidate mode (0 = end)
    test cx, cx
    jz .novesa
    add si, 2
    push si                                ; save table pos across BIOS call
    push ax
    xor ax, ax
    mov es, ax
    pop ax
    mov ax, 0x4F01
    mov di, VBE_MODEINFO
    int 0x10
    push ax
    mov al, 'f'
    call dbg_mark
    pop ax
    push ax
    call dbg_ax
    pop ax
    cmp ax, 0x004F
    jne .skipmode
    ; validate: LFB supported? (ModeAttributes bit 7)
    mov ax, [VBE_MODEINFO+0]
    test ax, 0x0080
    jz .skipmode
    ; validate: MemoryModel packed(4) or direct(6)?
    mov al, [VBE_MODEINFO+27]
    cmp al, 4
    je .modelok
    cmp al, 6
    jne .skipmode
.modelok:
    ; validate: bpp >= 15?
    mov al, [VBE_MODEINFO+25]
    cmp al, 15
    jb .skipmode
    ; set mode with LFB bit
    pop si
    push si
    mov bx, cx
    or bx, 0x4000
    mov cx, bx
    mov ax, 0x4F02
    int 0x10
    push ax
    mov al, 'g'
    call dbg_mark
    pop ax
    push ax
    call dbg_ax
    pop ax
    cmp ax, 0x004F
    jne .skipmode
    pop si                                 ; mode accepted
    jmp .parse
.skipmode:
    pop si
    jmp .nextmode
.parse:
    ; parse ModeInfoBlock at VBE_MODEINFO (offsets per VBE 3.0 spec)
    movzx eax, word [VBE_MODEINFO+16]   ; BytesPerScanLine
    mov [vbe_pitch], eax
    movzx eax, word [VBE_MODEINFO+18]   ; XResolution
    mov [vbe_width], eax
    movzx eax, word [VBE_MODEINFO+20]   ; YResolution
    mov [vbe_height], eax
    mov al, [VBE_MODEINFO+25]           ; BitsPerPixel
    movzx eax, al
    mov [vbe_bpp], eax
    mov eax, [VBE_MODEINFO+40]          ; PhysBasePtr
    mov [vbe_fbaddr], eax
    push eax
    mov al, 'B'
    call dbg_mark
    pop eax
    push eax
    call dbg_ax
    pop eax
    ret
.novesa: ; keep fbaddr=0; do NOT set graphics mode (kernel uses VGA text shell)
    ret

; candidate VBE modes, best first (0-terminated)
vbe_modes:
    dw 0x118          ; 1024x768x24
    dw 0x11B          ; 1280x1024x24
    dw 0x115          ; 800x600x24
    dw 0x112          ; 640x480x24
    dw 0

; ---- FAT12 loader: find KERNEL.BIN in root dir, follow cluster chain ----
; Floppy geometry: 2 heads, 18 spt. Reserved=17, fats=2*9, root=14 sectors.
; Data starts at LBA 49. Loads file to 1MB using unreal/big-real mode stores.
fat12_load_kernel:
    pusha
    ; enable unreal mode (4GB data segs while in real mode)
    cli
    lgdt [gdt32_desc]
    mov eax, cr0
    or al, 1
    mov cr0, eax
    jmp $+2
    mov ax, DATA32_SEL
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov eax, cr0
    and al, 0xFE
    mov cr0, eax
    jmp $+2
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    sti
    push ax
    mov al, 'h'
    call dbg_mark
    pop ax
    ; read root dir (LBA ROOT_LBA, 14 sectors) to FAT_BUF
    mov ax, ROOT_LBA
    mov cx, 14
    mov bx, FAT_BUF
    call read_lba
    push ax
    mov al, 'i'
    call dbg_mark
    pop ax
    ; scan 224 entries for "KERNEL  BIN"
    mov si, FAT_BUF
    mov cx, 224
.find:
    push cx
    push si
    mov di, fname_kernel
    mov cx, 11
    repe cmpsb
    pop si
    pop cx
    je .found
    add si, 32
    loop .find
    mov si, msg_nokernel
    call print16
    jmp halt16
.found:
    mov ax, [si+26]             ; first cluster
    mov [cur_cluster], ax
    mov word [kernel_sectors], 0
    mov edi, KERNEL_PHYS        ; dest phys addr (unreal: DS base=0 so EDI=flat)
    push ax
    mov al, 'F'
    call dbg_mark
    pop ax
.load_chain:
    mov ax, [cur_cluster]
    cmp ax, 0xFF8               ; end of chain?
    jae .chain_done
    ; cluster N -> LBA = DATA_LBA + (N-2)
    mov bx, ax
    sub bx, 2
    movzx eax, bx
    add eax, DATA_LBA
    push edi
    mov bx, SEC_SCRATCH
    mov cx, 1
    call read_lba   ; 1 sector to scratch
    pop edi
    ; copy 512B scratch -> EDI via 32-bit
    push esi
    mov esi, SEC_SCRATCH
    mov ecx, 128                ; 128 dwords
    ; need DS=4GB seg for EDI>1MB: re-enter unreal quickly
    cli
    push ax
    lgdt [gdt32_desc]
    mov eax, cr0
    or al,1
    mov cr0, eax
    jmp $+2
    mov ax, DATA32_SEL
    mov ds, ax
    mov es, ax
    mov eax, cr0
    and al,0xFE
    mov cr0, eax
    jmp $+2
    pop ax
    sti
    ; now DS has 4GB limit? No — we cleared CR0.PE so limit reset. Use a32+fs trick:
    ; Simplest QEMU-safe: use intermediate: copy via ES(4GB)? Re-do properly:
    ; Re-enter protected-style copy: we are in real mode; set FS=4GB selector manually:
    cli
    lgdt [gdt32_desc]
    mov eax, cr0
    or al,1
    mov cr0, eax
    jmp $+2
    mov ax, DATA32_SEL
    mov fs, ax      ; FS = 4GB
    mov eax, cr0
    and al,0xFE
    mov cr0, eax
    jmp $+2
    xor ax, ax
    mov ds, ax
    mov es, ax ; DS normal, FS 4GB cached
    sti
    ; copy DS:ESI -> FS:EDI
    push edi
.copy1:
    mov eax, [esi]
    mov [fs:edi], eax
    add esi, 4
    add edi, 4
    dec ecx
    jnz .copy1
    pop edi
    add edi, 512
    pop esi
    inc word [kernel_sectors]
    ; next cluster from FAT (FAT at FAT_LBA, loaded to FAT_TAB)
    push edi
    mov ax, FAT_LBA
    mov cx, 9
    mov bx, FAT_TAB
    call read_lba
    mov ax, [cur_cluster]
    mov bx, ax
    shr bx, 1
    add bx, ax    ; ax*1.5
    mov si, FAT_TAB
    add si, bx
    mov ax, [si]
    test word [cur_cluster], 1
    jnz .odd
    and ax, 0x0FFF
    jmp .next
.odd: shr ax, 4
.next: mov [cur_cluster], ax
    pop edi
    jmp .load_chain
.chain_done:
    xor ax, ax
    mov ds, ax
    mov es, ax
    popa
    ret

; read CX sectors from LBA AX to ES:BX. Clobbers AX,CX,DX,SI.
read_lba:
    push bp
    mov bp, sp
    sub sp, 6                       ; locals: [bp-2]=lba [bp-4]=count [bp-6]=dest_off
    mov [bp-2], ax
    mov [bp-4], cx
    mov [bp-6], bx
.sector_loop:
    cmp word [bp-4], 0
    je .done
    mov ax, [bp-2]                  ; LBA
    ; DIV-free CHS: q = LBA/18 by subtraction (LBA<2880, max 160 iters).
    ; sect = LBA - q*18 + 1; head = q&1; track = q>>1.
    ; (NOTE: avoids 16-bit DIV: wrong remainder observed for q=0 on QEMU TCG.)
    mov bx, ax                      ; BX = LBA (preserved for remainder)
    xor cx, cx                      ; CX = q
.div18:
    cmp ax, 18
    jb .gotq
    sub ax, 18
    sub bx, 18
    inc cx
    jmp .div18
.gotq:                              ; CX=q, BX=remainder
    mov dl, bl
    inc dl                          ; sect = rem+1
    mov [cs:sect_tmp], dl
    mov ax, cx                      ; q
    shr ax, 1                       ; track = q>>1, CF = head
    mov [cs:track_tmp], al
    mov al, 0
    adc al, 0                       ; head = CF
    mov [cs:head_tmp], al
    mov bx, [bp-6]
    mov dl, [boot_drive]
    mov dh, [head_tmp]
    mov ch, [track_tmp]
    mov cl, [sect_tmp]
    mov ax, 0x0201
    int 0x13
    jnc .sec_ok
    xor ah, ah
    int 0x13           ; reset, retry same sector
    jmp .sector_loop
.sec_ok:
    add word [bp-6], 512
    inc word [bp-2]
    dec word [bp-4]
    jmp .sector_loop
.done:
    mov sp, bp
    pop bp
    ret

halt16:
    cli
    hlt
    jmp halt16

; AL = marker -> isa-debugcon port 0x402 (16-bit version)
dbg_mark:
    push dx
    mov dx, 0x402
    out dx, al
    pop dx
    ret

; AX -> two debugcon marks (AL then AH). Preserves AX.
dbg_ax:
    push ax
    call dbg_mark
    pop ax
    xchg al, ah
    call dbg_mark
    xchg al, ah
    ret

msg_stage2   db "NovaOS stage2...",13,10,0
msg_pm       db "Entering long mode...",13,10,0
msg_nokernel db "KERNEL.BIN not found!",13,10,0
fname_kernel db "KERNEL  BIN"
boot_drive   db 0
sect_tmp     db 0
head_tmp     db 0
track_tmp    db 0
head_div     dw 2
mmap_count   dd 0
vbe_width    dd 1024
vbe_height   dd 768
vbe_pitch    dd 4096
vbe_bpp      dd 32
vbe_fbaddr   dd 0xE0000000
cur_cluster  dw 0
kernel_sectors dw 0

%include "boot/bios/gdt16.inc"

; ============ 32-bit protected mode: setup PAE + long mode ============
[BITS 32]
pm32:
    mov ax, DATA32_SEL
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, STAGE2_STACK
    push eax
    mov dx, 0x402
    mov al, 'H'
    out dx, al
    pop eax

    ; zero PML4/PDPT/PD (0x70000,0x71000,0x72000)
    mov edi, PML4_ADDR
    mov ecx, 0x3000
    xor eax, eax
    rep stosd

    ; PML4[0] -> PDPT, PML4[256] -> PDPT (higher-half -128TB alias)
    mov eax, PML4_ADDR+0x1000+0x03   ; present|rw
    mov [PML4_ADDR], eax
    mov [PML4_ADDR+0x800], eax       ; entry 256 (0xFFFF8000... alias)

    ; PDPT[0] -> PD
    mov eax, PML4_ADDR+0x2000+0x03
    mov [PML4_ADDR+0x1000], eax

    ; PD: 32 x 2MB identity pages covering 0..64MB (present|rw|PS)
    mov edi, PML4_ADDR+0x2000
    mov eax, 0x00000083
    mov ecx, 32
.fill_pd:
    mov [edi], eax
    add eax, 0x200000
    add edi, 8
    loop .fill_pd

    ; map the 1GB region containing the VBE framebuffer (2MB pages in PD@0x73000)
    mov eax, [vbe_fbaddr]
    test eax, eax
    jz .fbmap_done
    shr eax, 30                            ; PDPT index of fb region
    cmp eax, 0
    je .fbmap_done                         ; 0..1GB already mapped
    mov ebx, eax
    shl ebx, 30                            ; region base
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
    mov eax, [vbe_fbaddr]
    shr eax, 30                            ; idx again
    mov ebx, eax
    mov eax, 0x73000+0x03
    mov [PML4_ADDR+0x1000+ebx*8], eax
.fbmap_done:

    ; enable PAE, LME, paging
    mov eax, cr4
    or eax, 1<<5
    mov cr4, eax   ; PAE
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1<<8
    wrmsr                  ; EFER.LME
    mov eax, PML4_ADDR
    mov cr3, eax
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax ; PG

    lgdt [gdt64_desc]
    jmp CODE64_SEL:lm64

    ALIGN 8
gdt64_desc:
    dw gdt32_end - gdt32_start - 1
    dq gdt32_start

; ============ 64-bit long mode: jump to kernel ============
[BITS 64]
lm64:
    mov ax, DATA64_SEL
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov rsp, 0x90000
    push rax
    mov dx, 0x402
    mov al, 'I'
    out dx, al
    pop rax
    mov rdi, BOOTINFO_ADDR
    mov rax, KERNEL_PHYS
    jmp rax                       ; -> kernel_entry(RDI=BootInfo*)
    cli
    hlt
    jmp $
