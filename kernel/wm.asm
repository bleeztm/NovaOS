; NovaOS kernel/wm.asm - window manager (draggable windows, focus, min/close)
; Window struct (64B): x,y,w,h,flags,title_ptr,content_id,pad*9
; flags bit0=visible bit1=focused bit2=minimized bit3=closed

WM_MAX equ 8
WM_SIZE equ 64
WM_F_VISIBLE equ 1
WM_F_FOCUSED equ 2
WM_F_MIN     equ 4
WM_F_CLOSED  equ 8

wm_init:
    push rax
    push rcx
    push rdi
    lea rdi, [rel wm_table]
    mov rcx, WM_MAX*WM_SIZE/8
    xor eax, eax
    rep stosq
    mov byte [wm_count], 0
    mov byte [wm_focus], 0xFF
    mov byte [wm_drag], 0
    pop rdi
    pop rcx
    pop rax
    ret

; create: R8D=x R9D=y ECX=w EDX=h RSI=title EDI=content_id -> AL=index (0xFF fail)
wm_create:
    push rbx
    push rcx
    push rdx
    movzx ebx, byte [wm_count]
    cmp ebx, WM_MAX
    jae .fail
    imul ebx, WM_SIZE
    lea rax, [wm_table+rbx]
    mov [rax+0], r8d
    mov [rax+4], r9d
    mov [rax+8], ecx
    mov [rax+12], edx
    mov dword [rax+16], WM_F_VISIBLE | WM_F_FOCUSED
    mov [rax+24], rsi                      ; title ptr (64-bit store via qword)
    mov [rax+32], edi                      ; content id
    ; unfocus others
    push rax
    lea rdx, [rel wm_table]
    xor ecx, ecx
.unf:
    cmp ecx, WM_MAX
    jae .unfdone
    cmp rdx, rax
    je .unfnext
    and dword [rdx+16], ~WM_F_FOCUSED
.unfnext:
    add rdx, WM_SIZE
    inc ecx
    jmp .unf
.unfdone:
    pop rax
    movzx eax, byte [wm_count]
    mov [wm_focus], al
    inc byte [wm_count]
    pop rdx
    pop rcx
    pop rbx
    ret
.fail:
    mov al, 0xFF
    pop rdx
    pop rcx
    pop rbx
    ret

; close window AL=index
wm_close:
    push rbx
    movzx ebx, al
    imul ebx, WM_SIZE
    or dword [wm_table+rbx+16], WM_F_CLOSED
    and dword [wm_table+rbx+16], ~WM_F_VISIBLE
    pop rbx
    ret

; minimize toggle AL=index
wm_minimize:
    push rbx
    movzx ebx, al
    imul ebx, WM_SIZE
    xor dword [wm_table+rbx+16], WM_F_MIN
    pop rbx
    ret

; hit test: R8D=x R9D=y -> AL=index or 0xFF. Topmost (highest index) wins.
wm_hit_test:
    push rbx
    push rcx
    movzx ecx, byte [wm_count]
    test ecx, ecx
    jz .none
    dec ecx                                ; start from top
.loop:
    push rcx
    imul ecx, WM_SIZE
    lea rbx, [wm_table+rcx]
    test dword [rbx+16], WM_F_VISIBLE
    jz .next
    test dword [rbx+16], WM_F_MIN | WM_F_CLOSED
    jnz .next
    mov eax, [rbx+0]
    cmp r8d, eax
    jl .next
    add eax, [rbx+8]
    cmp r8d, eax
    jge .next
    mov eax, [rbx+4]
    cmp r9d, eax
    jl .next
    add eax, [rbx+12]
    cmp r9d, eax
    jge .next
    pop rcx
    mov eax, ecx
    pop rcx
    pop rbx
    ret
.next:
    pop rcx
    dec ecx
    jns .loop
.none:
    mov al, 0xFF
    pop rcx
    pop rbx
    ret

; mouse event: R8D=x R9D=y BL=buttons(new) BH=buttons(old)
; Handles title-bar drag + close/minimize buttons. Returns AL=1 if consumed.
wm_mouse_event:
    push rbx
    push rcx
    push rdx
    ; track drag in progress
    cmp byte [wm_drag], 0
    je .nodrag
    test bl, 1                             ; button still held?
    jz .enddrag
    ; move dragged window by delta
    movzx eax, byte [wm_drag_win]
    imul eax, WM_SIZE
    lea rdx, [wm_table+rax]
    mov eax, r8d
    sub eax, [wm_last_x]
    add [rdx+0], eax
    mov eax, r9d
    sub eax, [wm_last_y]
    add [rdx+4], eax
    mov [wm_last_x], r8d
    mov [wm_last_y], r9d
    mov al, 1
    jmp .out
.enddrag:
    mov byte [wm_drag], 0
    mov al, 1
    jmp .out
.nodrag:
    ; new press? (bit0 rising)
    test bl, 1
    jz .notconsumed
    test bh, 1
    jnz .notconsumed
    push rbx
    call wm_hit_test                       ; R8D/R9D preserved? R8/R9 untouched by call target regs? assume yes
    pop rbx
    cmp al, 0xFF
    je .notconsumed
    mov [wm_focus_tmp], al
    ; which zone? title bar = top 20px
    movzx ecx, al
    imul ecx, WM_SIZE
    lea rdx, [wm_table+rcx]
    mov eax, [rdx+4]
    add eax, 20
    cmp r9d, eax
    jge .focusonly
    ; title bar: check buttons (right side): [X] last 20px, [_] before it
    mov eax, [rdx+0]
    add eax, [rdx+8]
    sub eax, 20
    cmp r8d, eax
    jge .closeit
    sub eax, 20
    cmp r8d, eax
    jge .minit
    ; start drag
    mov al, [wm_focus_tmp]
    mov [wm_drag_win], al
    mov byte [wm_drag], 1
    mov [wm_last_x], r8d
    mov [wm_last_y], r9d
.focusonly:
    mov al, [wm_focus_tmp]
    mov [wm_focus], al
    mov al, 1
    jmp .out
.closeit:
    mov al, [wm_focus_tmp]
    call wm_close
    mov al, 1
    jmp .out
.minit:
    mov al, [wm_focus_tmp]
    call wm_minimize
    mov al, 1
    jmp .out
.notconsumed:
    xor eax, eax
.out:
    pop rdx
    pop rcx
    pop rbx
    ret

; draw all windows (frames + title bars + content dispatch)
wm_draw_all:
    push rax
    push rbx
    push rcx
    xor ecx, ecx
.win:
    cmp cl, [wm_count]
    jae .done
    push rcx
    movzx eax, cl
    imul eax, WM_SIZE
    lea rbx, [wm_table+rax]
    test dword [rbx+16], WM_F_VISIBLE
    jz .next
    test dword [rbx+16], WM_F_MIN | WM_F_CLOSED
    jnz .next
    call wm_draw_one                        ; RBX=window*
.next:
    pop rcx
    inc ecx
    jmp .win
.done:
    pop rcx
    pop rbx
    pop rax
    ret

; draw one window: RBX=window*. Border, title bar (focused=color), buttons, content.
wm_draw_one:
    push r8
    push r9
    push rsi
    push rdx
    push rcx
    mov r8d, [rbx+0]
    mov r9d, [rbx+4]
    mov ecx, [rbx+8]
    mov edx, [rbx+12]
    mov esi, 0x00C0C0C0                    ; frame gray
    call fb_fill_rect
    ; title bar
    mov r8d, [rbx+0]
    mov r9d, [rbx+4]
    mov ecx, [rbx+8]
    mov edx, 20
    test dword [rbx+16], WM_F_FOCUSED
    jz .unf
    mov esi, [theme_title]                 ; focused title color (theme)
    jmp .tbar
.unf:
    mov esi, 0x00808080
.tbar:
    call fb_fill_rect
    ; title text
    mov rax, [rbx+24]                      ; title ptr
    test rax, rax
    jz .buttons
    call wm_draw_title_text                ; RBX=window*
.buttons:
    ; minimize [_]
    mov r8d, [rbx+0]
    add r8d, [rbx+8]
    sub r8d, 40
    mov r9d, [rbx+4]
    add r9d, 2
    mov ecx, 16
    mov edx, 16
    mov esi, 0x00E0E000
    call fb_fill_rect
    ; close [X]
    mov r8d, [rbx+0]
    add r8d, [rbx+8]
    sub r8d, 20
    mov r9d, [rbx+4]
    add r9d, 2
    mov ecx, 16
    mov edx, 16
    mov esi, 0x00E03030
    call fb_fill_rect
    ; content area = inset 2px + below title
    mov r8d, [rbx+0]
    add r8d, 2
    mov r9d, [rbx+4]
    add r9d, 22
    mov ecx, [rbx+8]
    sub ecx, 4
    mov edx, [rbx+12]
    sub edx, 24
    mov esi, [theme_winbg]
    call fb_fill_rect
    ; dispatch content painter by id
    mov eax, [rbx+32]
    cmp eax, 1
    je .c_term
    cmp eax, 2
    je .c_file
    cmp eax, 3
    je .c_edit
    cmp eax, 4
    je .c_mon
    jmp .out
.c_term: call term_paint
    jmp .out
.c_file: call fileman_paint
    jmp .out
.c_edit: call editor_paint
    jmp .out
.c_mon:  call mon_paint
.out:
    pop rcx
    pop rdx
    pop rsi
    pop r9
    pop r8
    ret

; title text char loop: RBX=window*
wm_draw_title_text:
    push rsi
    push r8
    push r9
    push rax
    push rdx
    mov rsi, [rbx+24]                      ; title c-string
    mov r8d, [rbx+0]
    add r8d, 6
    mov r9d, [rbx+4]
    add r9d, 3
.ch:
    mov al, [rsi]
    inc rsi
    test al, al
    jz .done
    push rsi
    mov esi, 0x00FFFFFF                    ; white text
    mov edx, 0xFFFFFFFF                    ; transparent bg
    call fb_draw_char
    pop rsi
    add r8d, 8
    jmp .ch
.done:
    pop rdx
    pop rax
    pop r9
    pop r8
    pop rsi
    ret

wm_table: times WM_MAX*WM_SIZE db 0
wm_count db 0
wm_focus db 0xFF
wm_drag db 0
wm_drag_win db 0
wm_last_x dd 0
wm_last_y dd 0
wm_focus_tmp db 0
theme_title dd 0x000080C0                  ; set by Settings (default Nova blue)
theme_winbg dd 0x00181818
