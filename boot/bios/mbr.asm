; NovaOS MBR stage1 - 512 bytes, FAT12-aware, loads stage2 (16 sectors) to 0x7E00
; Build with: nasm -f bin boot/bios/mbr.asm -o build/mbr.bin
; Loaded by BIOS at 0x7C00. Includes 1.44MB FAT12 BPB so image mounts as floppy.
[BITS 16]
[ORG 0x7C00]

    jmp short start
    nop
; ---- FAT12 BPB (3.5 inch 1.44MB, rsvd=17: MBR + 16 raw stage2 sectors) ----
oem_name        db "NOVAOS  "
bytes_per_sec   dw 512
sec_per_clust   db 1
rsvd_secs       dw 17
num_fats        db 2
root_entries    dw 224
total_secs16    dw 2880
media_type      db 0xF0
fat_size16      dw 9
sec_per_track   dw 18
num_heads       dw 2
hidden_secs     dd 0
total_secs32    dd 0
drive_num       db 0
reserved1       db 0
bootsig         db 0x29
vol_id          dd 0x4E4F5641
vol_label       db "NOVAOS     "
fs_type         db "FAT12   "

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    mov [boot_drive], dl
    mov al, 'A'
    call dbg_mark
    mov si, msg_loading
    call print16
    mov ah, 0x02
    mov al, 16
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [boot_drive]
    mov bx, 0x7E00
    int 0x13
    jc disk_error
    mov si, msg_ok
    call print16
    mov al, 'B'
    call dbg_mark
    jmp 0x0000:0x7E00

disk_error:
    mov si, msg_diskerr
    call print16
    xor ah, ah
    int 0x16
    int 0x19

; SI = zero-terminated string
print16:
    pusha
ploop:
    lodsb
    test al, al
    jz pdone
    mov ah, 0x0E
    mov bh, 0
    mov bl, 0x07
    int 0x10
    jmp ploop
pdone:
    popa
    ret

msg_loading db "NovaOS MBR...", 13, 10, 0
msg_ok      db "Stage2 OK", 13, 10, 0
msg_diskerr db "Disk error! Press key...", 13, 10, 0
boot_drive  db 0

; AL = marker byte -> isa-debugcon (QEMU -device isa-debugcon,iobase=0x402)
dbg_mark:
    push dx
    mov dx, 0x402
    out dx, al
    pop dx
    ret

    times 510-($-$$) db 0
    dw 0xAA55
