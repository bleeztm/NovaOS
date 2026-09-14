; NovaOS kernel/kbd.asm - PS/2 keyboard driver (IRQ1, Set-1 scancodes)
; Ring buffer of ASCII keys (256). Tracks Shift/Ctrl/Alt; flags F8 and Ctrl+Alt+T.

KBD_BUF_SIZE equ 256

kbd_init:
    push rax
    mov byte [kbd_shift], 0
    mov byte [kbd_ctrl], 0
    mov byte [kbd_alt], 0
    mov byte [kbd_f8_flag], 0
    mov byte [kbd_dbg_flag], 0             ; Ctrl+Alt+T shell hotkey
    mov word [kbd_head], 0
    mov word [kbd_tail], 0
    ; enable keyboard interface (controller cmd 0xAE)
    mov al, 0xAE
    out 0x64, al
    pop rax
    ret

; IRQ1 handler (called from irq1_wrap with regs saved)
kbd_irq_handler:
    push rax
    push rbx
    push rcx
    in al, 0x60                            ; scancode
    movzx ebx, al
    test bl, 0x80                          ; release?
    jnz .release
    ; make codes
    cmp bl, 0x2A
    je .shift_on
    cmp bl, 0x36
    je .shift_on
    cmp bl, 0x1D
    je .ctrl_on
    cmp bl, 0x38
    je .alt_on
    cmp bl, 0x42                           ; F8 make
    je .f8_on
    ; Ctrl+Alt+T: T = 0x14
    cmp bl, 0x14
    jne .translate
    cmp byte [kbd_ctrl], 0
    je .translate
    cmp byte [kbd_alt], 0
    je .translate
    mov byte [kbd_dbg_flag], 1
    jmp .done
.translate:
    cmp byte [kbd_shift], 0
    je .map_normal
    lea rax, [rel kbd_map_shift]
    mov cl, [rax+rbx]
    jmp .got
.map_normal:
    lea rax, [rel kbd_map]
    mov cl, [rax+rbx]
.got:
    test cl, cl
    jz .done
    movzx ebx, cl
    call kbd_push
    jmp .done
.shift_on:
    mov byte [kbd_shift], 1
    jmp .done
.ctrl_on:
    mov byte [kbd_ctrl], 1
    jmp .done
.alt_on:
    mov byte [kbd_alt], 1
    jmp .done
.f8_on:
    mov byte [kbd_f8_flag], 1
    jmp .done
.release:
    and bl, 0x7F
    cmp bl, 0x2A
    je .shift_off
    cmp bl, 0x36
    je .shift_off
    cmp bl, 0x1D
    je .ctrl_off
    cmp bl, 0x38
    je .alt_off
    jmp .done
.shift_off:
    mov byte [kbd_shift], 0
    jmp .done
.ctrl_off:
    mov byte [kbd_ctrl], 0
    jmp .done
.alt_off:
    mov byte [kbd_alt], 0
.done:
    pop rcx
    pop rbx
    pop rax
    ret

; NOTE: shifted chars use kbd_map_shift via the Shift flag above.

; push BL -> ring buffer
kbd_push: ; EBX = char (low byte used)
    push rax
    movzx eax, word [kbd_head]
    mov [kbd_buf+rax], bl
    inc ax
    and ax, KBD_BUF_SIZE-1
    mov [kbd_head], ax
    pop rax
    ret

; get key -> RAX (0 = empty). Non-blocking.
kbd_get_key:
    push rbx
    movzx eax, word [kbd_tail]
    cmp ax, [kbd_head]
    je .empty
    movzx ebx, byte [kbd_buf+rax]
    inc ax
    and ax, KBD_BUF_SIZE-1
    mov [kbd_tail], ax
    mov eax, ebx
    pop rbx
    ret
.empty:
    xor eax, eax
    pop rbx
    ret

; blocking getc -> AL
kbd_getc_block:
    call kbd_get_key
    test rax, rax
    jz kbd_getc_block
    ret

kbd_shift   db 0
kbd_ctrl    db 0
kbd_alt     db 0
kbd_f8_flag db 0
kbd_dbg_flag db 0
kbd_head    dw 0
kbd_tail    dw 0
kbd_buf: times KBD_BUF_SIZE db 0

; Set-1 make-code -> ASCII (0 = non-printable). Index = scancode.
; Row 0: 0x00-0x0F | Row 1: 0x10-0x1D | Row 2: 0x1E-0x2B | Row 3: 0x2C-0x39
kbd_map:
db 0,27,'1','2','3','4','5','6','7','8','9','0','-','=',8,9
db 'q','w','e','r','t','y','u','i','o','p','[',']',10,0
db 'a','s','d','f','g','h','j','k','l',';',"'",'`',0,'\'
db 'z','x','c','v','b','n','m',',','.','/',0,'*',0,' '
times 128-0x3A db 0
kbd_map_shift:
db 0,27,'!','@','#','$','%','^','&','*','(',')','_','+',8,9
db 'Q','W','E','R','T','Y','U','I','O','P','{','}',10,0
db 'A','S','D','F','G','H','J','K','L',':','"','~',0,'|'
db 'Z','X','C','V','B','N','M','<','>','?',0,'*',0,' '
times 128-0x3A db 0
