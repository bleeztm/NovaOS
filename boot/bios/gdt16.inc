; NovaOS boot/bios/gdt16.inc - GDT helpers for 16/32/64-bit transitions
; Used by stage2.asm only (included, not assembled standalone).
%ifndef _GDT16_INC_
%define _GDT16_INC_

; Flat GDT: null, code32 (0x08), data32 (0x10), code64 (0x18), data64 (0x20)
gdt32_start:
    dq 0x0000000000000000
gdt32_code: ; base=0 limit=4GB exec/read, D=1 (32-bit)
    dw 0xFFFF, 0x0000
    db 0x00, 10011010b, 11001111b, 0x00
gdt32_data: ; base=0 limit=4GB read/write, D=1
    dw 0xFFFF, 0x0000
    db 0x00, 10010010b, 11001111b, 0x00
gdt64_code: ; L=1 (64-bit code), D=0
    dw 0xFFFF, 0x0000
    db 0x00, 10011010b, 10101111b, 0x00
gdt64_data:
    dw 0xFFFF, 0x0000
    db 0x00, 10010010b, 10101111b, 0x00
gdt32_end:

gdt32_desc:
    dw gdt32_end - gdt32_start - 1
    dd gdt32_start

CODE32_SEL equ gdt32_code - gdt32_start   ; 0x08
DATA32_SEL equ gdt32_data - gdt32_start   ; 0x10
CODE64_SEL equ gdt64_code - gdt32_start   ; 0x18
DATA64_SEL equ gdt64_data - gdt32_start   ; 0x20

%endif
