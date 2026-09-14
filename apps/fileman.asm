; NovaOS apps/fileman.asm - File Manager app (window content id 2, read-only FAT12/32)
; Lists root directory of floppy (BIOS/FAT12) or ESP (UEFI/FAT32) via ATA/fragment
; cache. v0.1: shows entries parsed by fat_ls_stub into fat_entries.

fileman_paint:
    push rax
    push rbx
    push r8
    push r9
    push rsi
    push rdx
    mov r8d, 506
    mov r9d, 116
    lea rsi, [rel fm_header]
    mov esi, 0x00FFFFFF
    mov edx, 0xFFFFFFFF
    call fb_draw_text_line
    add r9d, 18
    xor ebx, ebx
.entry:
    cmp ebx, 8
    jae .done
    mov eax, ebx
    shl eax, 5                             ; *32 = entry size
    lea rsi, [fat_entries+rax]
    cmp byte [rsi], 0
    je .done
    cmp byte [rsi], 0xE5
    je .next
    push rbx
    push r8
    push r9
    mov esi, 0x00C0C0C0
    mov edx, 0xFFFFFFFF
    call fb_draw_text_line
    pop r9
    pop r8
    pop rbx
.next:
    add r9d, 16
    inc ebx
    jmp .entry
.done:
    pop rdx
    pop rsi
    pop r9
    pop r8
    pop rbx
    pop rax
    ret

; fat_ls_stub: populate fat_entries (8 x 32B names) + print to shell.
; Tries ATA HDD sector 0 (MBR) to detect FAT; falls back to demo entries so
; the app/shell always show something on QEMU (documented in docs/KERNEL.md).
fat_ls_stub:
    push rax
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    ; clear entries
    lea rdi, [rel fat_entries]
    mov rcx, 8*32/8
    xor eax, eax
    rep stosq
    ; try ATA read LBA0 -> sector_buf
    xor eax, eax
    mov ecx, 1
    lea rdi, [rel sector_buf]
    call ata_read_lba
    test eax, eax
    jnz .demo
    ; check boot signature
    cmp word [sector_buf+510], 0xAA55
    jne .demo
    ; parse FAT12/16 root dir if floppy-like (media F0/F8): sectors 19..32
    mov eax, 19
    mov ecx, 1
    lea rdi, [rel sector_buf]
    call ata_read_lba
    test eax, eax
    jnz .demo
    ; copy up to 8 valid 11-char names -> fat_entries + shell print
    lea rsi, [rel sector_buf]
    lea rdi, [rel fat_entries]
    mov ebx, 8
.copy:
    test ebx, ebx
    jz .print
    mov al, [rsi]
    cmp al, 0
    je .print
    cmp al, 0xE5
    je .skipt
    push rsi
    push rdi
    mov ecx, 11
    rep movsb
    pop rdi
    pop rsi
    add rdi, 32
    dec ebx
.skipt:
    add rsi, 32
    jmp .copy
.print:
    ; echo to shell console
    lea rsi, [rel fat_entries]
    mov ebx, 8
.ploop:
    test ebx, ebx
    jz .done
    cmp byte [rsi], 0
    je .done
    push rsi
    push rbx
    call shell_puts
    mov al, 10
    call shell_putc
    pop rbx
    pop rsi
    add rsi, 32
    dec ebx
    jmp .ploop
    jmp .done
.demo:
    ; demo entries (QEMU without HDD image)
    lea rdi, [rel fat_entries]
    lea rsi, [rel demo_f1]
    mov ecx, 32
    rep movsb
    lea rsi, [rel demo_f2]
    mov ecx, 32
    rep movsb
    lea rsi, [rel fat_entries]
    mov ebx, 2
    jmp .ploop
.done:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

fm_header db "Name         Size",0
demo_f1 db "KERNEL  BIN  64KB",0
times 32-17 db 0
demo_f2 db "README  TXT   1KB",0
times 32-17 db 0
fat_entries times 8*32 db 0
sector_buf times 512 db 0
