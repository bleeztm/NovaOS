; NovaOS apps/terminal.asm - Terminal app (window content id 1)
; Scrollback buffer + prompt. Painted inside its wm window each frame.

TERM_COLS equ 48
TERM_ROWS equ 12

term_paint:
    push rax
    push rbx
    push r8
    push r9
    push rsi
    push rdx
    ; find our window (content id 1, first visible) -> origin for text
    call term_find_window                 ; -> R8D=x R9D=y (content origin)
    ; draw scrollback lines
    lea rsi, [rel term_buf]
    mov ebx, 0
.line:
    cmp ebx, TERM_ROWS
    jae .prompt
    push rsi
    push rbx
    push r8
    push r9
    mov r9d, r9d
    mov eax, ebx
    imul eax, 16
    add r9d, eax
    mov edx, 0xFFFFFFFF
    mov esi, 0x00C0C0C0
    call fb_draw_text_line                ; RSI=line R8D=x R9D=y
    pop r9
    pop r8
    pop rbx
    pop rsi
    add rsi, TERM_COLS
    inc ebx
    jmp .line
.prompt:
    ; prompt line
    mov eax, TERM_ROWS
    imul eax, 16
    add r9d, eax
    lea rsi, [rel term_prompt]
    mov edx, 0xFFFFFFFF
    mov esi, 0x00FFFFFF
    call fb_draw_text_line
    pop rdx
    pop rsi
    pop r9
    pop r8
    pop rbx
    pop rax
    ret

; locate first visible window with content_id==1 -> R8D=x+6 R9D=y+26
term_find_window:
    push rax
    push rbx
    push rcx
    xor ecx, ecx
.scan:
    cmp cl, [wm_count]
    jae .fallback
    movzx eax, cl
    imul eax, 64
    lea rbx, [wm_table+rax]
    cmp dword [rbx+32], 1
    jne .next
    test dword [rbx+16], 1
    jz .next
    mov r8d, [rbx+0]
    add r8d, 6
    mov r9d, [rbx+4]
    add r9d, 26
    pop rcx
    pop rbx
    pop rax
    ret
.next:
    inc ecx
    jmp .scan
.fallback:
    mov r8d, 66
    mov r9d, 86
    pop rcx
    pop rbx
    pop rax
    ret

; draw ASCIIZ line: RSI=str R8D=x R9D=y ESI=fg EDX=bg
fb_draw_text_line:
    push rax
    push r8
    push r9
.ch:
    mov al, [rsi]
    inc rsi
    test al, al
    jz .done
    push rsi
    call fb_draw_char
    pop rsi
    add r8d, 8
    jmp .ch
.done:
    pop r9
    pop r8
    pop rax
    ret

term_prompt db "term> _",0
term_buf:
db "Welcome to NovaOS Terminal",0
times TERM_COLS-26 db 0
db "Type F8 for emergency shell",0
times TERM_COLS-27 db 0
times (TERM_ROWS-2)*TERM_COLS db 0
