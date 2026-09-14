; NovaOS kernel/ata.asm - ATA PIO LBA28 sector reads (primary master)
; Used by File Manager / shell ls+cat. Polling, no DMA in v0.1.

ATA_DATA     equ 0x1F0
ATA_ERR      equ 0x1F1
ATA_SECCOUNT equ 0x1F2
ATA_LBA_LO   equ 0x1F3
ATA_LBA_MID  equ 0x1F4
ATA_LBA_HI   equ 0x1F5
ATA_DRIVE    equ 0x1F6
ATA_STATUS   equ 0x1F7
ATA_CMD      equ 0x1F7
ATA_CMD_READ equ 0x20

ata_init:
    push rax
    push rdx
    ; select master, float check
    mov dx, ATA_DRIVE
    mov al, 0xE0
    out dx, al
    mov dx, ATA_STATUS
    in al, dx
    mov [ata_present], al
    pop rdx
    pop rax
    ret
ata_present db 0

; wait BSY=0, returns AL=status (bit0 ERR checked by caller)
ata_wait_ready:
    push rcx
    push rdx
    mov ecx, 1000000
    mov dx, ATA_STATUS
.poll:
    in al, dx
    test al, 0x80                          ; BSY?
    jz .ready
    dec ecx
    jnz .poll
    pop rdx
    pop rcx
    mov al, 0xFF
    ret
.ready:
    pop rdx
    pop rcx
    ret

; read sectors: EAX=LBA28, CX=count (1..256), RDI=dest buffer. -> EAX=0 ok, 1 err.
ata_read_lba:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    mov esi, eax                           ; LBA
    mov ebx, ecx                           ; count
    call ata_wait_ready
.sector:
    ; select drive/head
    mov dx, ATA_DRIVE
    mov eax, esi
    shr eax, 24
    and al, 0x0F
    or al, 0xE0                            ; master, LBA mode
    out dx, al
    ; count + LBA bytes
    mov dx, ATA_SECCOUNT
    mov al, 1
    out dx, al
    mov dx, ATA_LBA_LO
    mov eax, esi
    out dx, al
    mov dx, ATA_LBA_MID
    mov eax, esi
    shr eax, 8
    out dx, al
    mov dx, ATA_LBA_HI
    mov eax, esi
    shr eax, 16
    out dx, al
    ; command
    mov dx, ATA_CMD
    mov al, ATA_CMD_READ
    out dx, al
    call ata_wait_ready
    test al, 0x01                          ; ERR?
    jnz .err
    test al, 0x08                          ; DRQ?
    jz .nodrq
    ; transfer 256 words
    mov dx, ATA_DATA
    mov ecx, 256
.words:
    in ax, dx
    mov [rdi], ax
    add rdi, 2
    dec ecx
    jnz .words
    inc esi
    dec ebx
    jnz .sector
    xor eax, eax
    jmp .out
.nodrq:
    call ata_wait_ready
    test al, 0x08
    jnz .sector_words_retry
    jmp .err
.sector_words_retry:
    sub rdi, 0                             ; already positioned
    mov dx, ATA_DATA
    mov ecx, 256
.w2:
    in ax, dx
    mov [rdi], ax
    add rdi, 2
    dec ecx
    jnz .w2
    inc esi
    dec ebx
    jnz .sector
    xor eax, eax
    jmp .out
.err:
    mov eax, 1
.out:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret
