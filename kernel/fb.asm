; NovaOS kernel/fb.asm - framebuffer abstraction (VBE + GOP unified)
; Backed by BootInfo. Supports 32bpp fast path + 24bpp. Text console on top.
%include "kernel/font.inc"

; state (mirrored to mouse clamps)
fb_addr   dq 0
fb_width  dd 0
fb_height dd 0
fb_pitch  dd 0
fb_bpp    dd 0
fb_ok     db 0
fb_cursor_x dd 0
fb_cursor_y dd 0
fb_fg     dd 0x00FFFFFF
fb_bg     dd 0x00000000

; RDI = BootInfo*. Returns AL=1 graphics ok, 0 = VGA-text fallback.
; NOTE: fb_addr is assembled byte-wise: 32/64-bit loads from low-RAM
; BootInfo were observed returning stale low bytes under QEMU TCG, while
; byte loads are always correct. All other fields use normal dword loads.
fb_init:
    push rbx
    push rsi
    cmp dword [rdi+0], 0x534F564E
    jne .fail
    lea rsi, [rdi+8]
    xor ebx, ebx                           ; result accumulator (RBX)
    xor ecx, ecx                           ; shift counter 0,8,...,56
.bcopy:
    lodsb                                  ; AL = next byte (little-endian order)
    movzx eax, al
    shl rax, cl
    or rbx, rax
    add ecx, 8
    cmp ecx, 64
    jb .bcopy
    mov [fb_addr], rbx
    test rbx, rbx
    jz .fail
    pop rsi
    mov eax, [rdi+16]
    mov [fb_width], eax 
    mov [fb_width_var], eax
    mov eax, [rdi+20]
    mov [fb_height], eax
    mov [fb_height_var], eax
    mov eax, [rdi+24]
    mov [fb_pitch], eax
    mov eax, [rdi+28]
    mov [fb_bpp], eax
    test eax, eax
    jz .fail
    mov byte [fb_ok], 1
    mov al, 1
    pop rbx
    ret
.fail:
    mov byte [fb_ok], 0
    xor eax, eax
    pop rsi
    pop rbx
    ret

; plot: R8D=x R9D=y ESI=color(0xRRGGBB)
fb_put_pixel_xy:
    push rax
    push rbx
    push rcx
    push rdx
    push rdi
    cmp byte [fb_ok], 0
    je .out
    mov eax, r8d
    cmp eax, [fb_width]
    jae .out
    mov ebx, r9d
    cmp ebx, [fb_height]
    jae .out
    mov rdi, [fb_addr]
    mov ecx, ebx
    imul ecx, [fb_pitch]                   ; y*pitch
    mov edx, eax
    imul edx, 4                            ; assume 32bpp layout (x*4)
    cmp dword [fb_bpp], 24
    jne .b32
    imul edx, eax, 3
    add rdi, rcx
    add rdi, rdx
    mov [rdi+0], sil
    shr esi, 8
    mov [rdi+1], sil
    shr esi, 8
    mov [rdi+2], sil
    jmp .out
.b32:
    add rdi, rcx
    add rdi, rdx
    mov [rdi], esi
.out:
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; fill rect: R8D=x R9D=y ECX=w EDX=h ESI=color
fb_fill_rect:
    push rbx
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    mov r10d, r8d                          ; x0
    mov r11d, r9d                          ; y0
    mov r12d, ecx                          ; w
    mov r13d, edx                          ; h
    mov r14d, esi                          ; color
    mov r15d, r11d                         ; y cursor
.yloop:
    mov eax, r11d
    add eax, r13d
    cmp r15d, eax
    jge .done
    mov ebx, r10d                          ; x cursor
.xloop:
    mov eax, r10d
    add eax, r12d
    cmp ebx, eax
    jge .nextrow
    mov r8d, ebx
    mov r9d, r15d
    mov esi, r14d
    call fb_put_pixel_xy
    inc ebx
    jmp .xloop
.nextrow:
    inc r15d
    jmp .yloop
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop rbx
    ret

; line: R8D=x0 R9D=y0 ECX=x1 EDX=y1 ESI=color (Bresenham)
fb_draw_line:
    push rbx
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    mov r10d, r8d                          ; x0
    mov r11d, r9d                          ; y0
    mov r12d, ecx                          ; x1
    mov r13d, edx                          ; y1
    mov r14d, esi                          ; color
    mov eax, r12d
    sub eax, r10d
    movsx r15, eax
    cmp r15, 0
    jge .dxok
    neg r15
.dxok:                                     ; R15 = |dx|
    mov eax, r13d
    sub eax, r11d
    movsx rbx, eax
    cmp rbx, 0
    jge .dyok
    neg rbx
.dyok:                                     ; RBX = |dy|
    mov r8d, r10d
    mov r9d, r11d
    mov esi, r14d
    cmp r15, rbx
    jb .vline
.hline:                                    ; step in x
    mov eax, r12d
    cmp r10d, eax
    jg .hback
.hfwd:
    cmp r10d, r12d
    jg .ldone
    mov r8d, r10d
    call fb_put_pixel_xy
    inc r10d
    jmp .hfwd
.hback:
    cmp r10d, r12d
    jl .ldone
    mov r8d, r10d
    call fb_put_pixel_xy
    dec r10d
    jmp .hback
.vline:                                    ; step in y
    mov r9d, r11d
    cmp r11d, r13d
    jg .vback
.vfwd:
    cmp r11d, r13d
    jg .ldone
    mov r9d, r11d
    call fb_put_pixel_xy
    inc r11d
    jmp .vfwd
.vback:
    cmp r11d, r13d
    jl .ldone
    mov r9d, r11d
    call fb_put_pixel_xy
    dec r11d
    jmp .vback
.ldone:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop rbx
    ret

; draw char: AL=char R8D=x R9D=y ESI=fg EDX=bg (bg=0xFFFFFFFF => transparent)
; Preserves RSI (callers pass string pointers in RSI/R15).
fb_draw_char:
    push rsi
    push rbx
    push rcx
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    movzx ebx, al
    shl ebx, 4                             ; glyph offset = c*16
    lea r14, [font_data+rbx]               ; glyph base (abs: kernel < 2GB)
    mov r10d, r8d                          ; x0
    mov r11d, r9d                          ; y0
    mov r12d, esi                          ; fg
    mov r13d, edx                          ; bg
    xor r15d, r15d                         ; row = 0
.row:
    cmp r15d, 16
    jae .done
    mov bl, [r14+r15]                      ; row bits
    xor ecx, ecx                           ; col = 0
.col:
    cmp ecx, 8
    jae .nextrow
    mov eax, 0x80
    shr eax, cl
    test bl, al
    jz .bgpix
    mov r8d, r10d
    add r8d, ecx
    mov r9d, r11d
    add r9d, r15d
    mov esi, r12d
    call fb_put_pixel_xy
    jmp .nextcol
.bgpix:
    cmp r13d, 0xFFFFFFFF
    je .nextcol
    mov r8d, r10d
    add r8d, ecx
    mov r9d, r11d
    add r9d, r15d
    mov esi, r13d
    call fb_put_pixel_xy
.nextcol:
    inc ecx
    jmp .col
.nextrow:
    inc r15d
    jmp .row
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop rcx
    pop rbx
    pop rsi
    ret

; print string: RSI=cstr, uses fb_cursor_x/y + fb_fg/bg, wraps + scrolls.
fb_print_string:
    push rax
    push r8
    push r9
    push rdx
    push r15
    mov r15, rsi                           ; string pointer (RSI reused for color arg)
.loop:
    mov al, [r15]
    inc r15
    test al, al
    jz .done
    cmp al, 10
    je .newline
    mov r8d, [fb_cursor_x]
    mov r9d, [fb_cursor_y]
    mov esi, [fb_fg]
    mov edx, [fb_bg]
    push r15
    call fb_draw_char
    pop r15
    add dword [fb_cursor_x], 8
    mov eax, [fb_width]
    sub eax, 8
    cmp [fb_cursor_x], eax
    jb .loop
.newline:
    mov dword [fb_cursor_x], 0
    add dword [fb_cursor_y], 16
    mov eax, [fb_height]
    sub eax, 16
    cmp [fb_cursor_y], eax
    jb .loop
    call fb_scroll                         ; keep cursor visible
    jmp .loop
.done:
    pop r15
    pop rdx
    pop r9
    pop r8
    pop rax
    ret

; scroll text area up by 16px (memmove rows). 32bpp only; 24bpp TODO.
fb_scroll:
    push rax
    push rcx
    push rsi
    push rdi
    cmp dword [fb_bpp], 32
    jne .reset_cursor
    mov rsi, [fb_addr]
    mov eax, [fb_pitch]
    lea rsi, [rsi+rax]                     ; src = row 16
    mov rdi, [fb_addr]                     ; dst = row 0
    mov ecx, [fb_height]
    sub ecx, 16
    imul ecx, [fb_pitch]
    shr ecx, 3                             ; qwords
    rep movsq
    ; clear last line
    mov rdi, [fb_addr]
    mov eax, [fb_height]
    sub eax, 16
    imul eax, [fb_pitch]
    add rdi, rax
    mov ecx, [fb_pitch]
    shr ecx, 3
    mov eax, [fb_bg]                       ; 0x00RRGGBB -> replicate to 64-bit fill
    mov rdx, rax
    shl rdx, 32
    or rax, rdx
.fill:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .fill
.reset_cursor:
    sub dword [fb_cursor_y], 16
    pop rdi
    pop rsi
    pop rcx
    pop rax
    ret

; clear whole screen to ESI color
fb_clear:
    push rcx
    push r8
    push r9
    xor r8d, r8d
    xor r9d, r9d
    mov ecx, [fb_width]
    mov edx, [fb_height]
    call fb_fill_rect
    mov dword [fb_cursor_x], 0
    mov dword [fb_cursor_y], 0
    pop r9
    pop r8
    pop rcx
    ret

; blit: copy ESI(src phys, pitch in ECX) WxH (EBX,EDX) to R8D,R9D. 32bpp.
fb_blit:
    push rax
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    mov rdi, [fb_addr]
    mov eax, r9d
    imul eax, [fb_pitch]
    add rdi, rax
    mov eax, r8d
    shl eax, 2
    add rdi, rax
    mov eax, ebx                           ; w
    shl eax, 2                             ; row bytes
    test ebx, ebx
    jz .done
    test edx, edx
    jz .done
.rows:
    push rsi
    push rdi
    push rcx
    mov ecx, eax
    rep movsb
    pop rcx
    pop rdi
    pop rsi
    add rsi, rcx
    add rdi, [fb_pitch]
    dec edx
    jnz .rows
.done:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret
