; NovaOS kernel/gdt.asm - 64-bit GDT + TSS placeholder (included into entry.asm)
; Selectors: NULL=0x00 KCODE=0x08 KDATA=0x10 UCODE=0x1B UDATA=0x23 (RPL3)

gdt_install:
    push rax
    lgdt [rel kgdt_desc]
    ; far return to reload CS: push selector then RIP
    push 0x08
    lea rax, [rel .reload_cs]
    push rax
    retfq
.reload_cs:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    pop rax
    ret

ALIGN 8
kgdt:
    dq 0x0000000000000000                 ; 0x00 null
    dq 0x00209A0000000000                 ; 0x08 kernel code (L=1, P, DPL0, exec/read)
    dq 0x0000920000000000                 ; 0x10 kernel data (P, DPL0, read/write)
    dq 0x0020FA0000000000                 ; 0x18 user code (DPL3)
    dq 0x0000F20000000000                 ; 0x20 user data (DPL3)
kgdt_end:
kgdt_desc:
    dw kgdt_end - kgdt - 1
    dq kgdt
