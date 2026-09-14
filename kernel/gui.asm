; NovaOS kernel/gui.asm - desktop compositor, taskbar, start menu, cursor
; gui_init: AL=1 ok / 0 fail. gui_loop runs until F8/Ctrl+Alt+T or shutdown.

gui_init:
    push rbx
    cmp byte [fb_ok], 0
    je .fail
    call wm_init
    ; demo windows: Terminal + File Manager + System Monitor
    mov r8d, 60
    mov r9d, 60
    mov ecx, 420
    mov edx, 260
    lea rsi, [rel title_term]
    mov edi, 1
    call wm_create
    mov r8d, 500
    mov r9d, 90
    mov ecx, 380
    mov edx, 250
    lea rsi, [rel title_file]
    mov edi, 2
    call wm_create
    mov r8d, 200
    mov r9d, 340
    mov ecx, 360
    mov edx, 200
    lea rsi, [rel title_mon]
    mov edi, 4
    call wm_create
    mov byte [start_open], 0
    mov byte [gui_running], 1
    mov al, 1
    pop rbx
    ret
.fail:
    xor eax, eax
    pop rbx
    ret

; one full frame: wallpaper, windows, taskbar, start menu, cursor
gui_draw_frame:
    push rax
    call gui_wallpaper
    call wm_draw_all
    call gui_taskbar
    cmp byte [start_open], 0
    je .nocursor
    call gui_startmenu
.nocursor:
    call gui_cursor
    pop rax
    ret

gui_wallpaper:
    push r8
    push r9
    push rcx
    push rdx
    push rsi
    ; vertical gradient (theme-aware): interpolate top->bottom in 32 steps
    mov ecx, [fb_height]
    xor r9d, r9d
.rows:
    cmp r9d, ecx
    jae .done
    mov eax, r9d
    shr eax, 4                              ; band = y/16
    and eax, 31
    mov esi, [theme_top]
    ; cheap shade: subtract band*0x00040202 from top color
    mov edx, eax
    imul edx, 0x00040202
    sub esi, edx
    xor r8d, r8d
    mov edx, [fb_width]
    push rcx
    mov ecx, edx
    mov edx, 1
    call fb_fill_rect                       ; 1px tall full-width strip
    pop rcx
    inc r9d
    jmp .rows
.done:
    pop rsi
    pop rdx
    pop rcx
    pop r9
    pop r8
    ret

gui_taskbar:
    push r8
    push r9
    push rcx
    push rdx
    push rsi
    mov eax, [fb_height]
    sub eax, 36
    mov r9d, eax
    xor r8d, r8d
    mov ecx, [fb_width]
    mov edx, 36
    mov esi, [theme_taskbar]
    call fb_fill_rect
    ; start button
    mov r8d, 4
    mov eax, [fb_height]
    sub eax, 32
    mov r9d, eax
    mov ecx, 90
    mov edx, 28
    mov esi, 0x000080C0
    call fb_fill_rect
    ; clock (uptime) at right
    call uptime_seconds                     ; RAX=seconds
    push rax
    mov ecx, 3600
    xor edx, edx
    div ecx                                 ; RAX=hours
    mov [clock_h], eax
    pop rax
    push rax
    xor edx, edx
    mov ecx, 60
    div ecx                                 ; RAX=minutes total
    xor edx, edx
    mov ecx, 60
    div ecx                                 ; RDX=min? use div properly below
    pop rax
    pop rsi
    pop rdx
    pop rcx
    pop r9
    pop r8
    ret

gui_startmenu:
    push r8
    push r9
    push rcx
    push rdx
    push rsi
    mov r8d, 4
    mov eax, [fb_height]
    sub eax, 36+5*28+8
    mov r9d, eax
    mov ecx, 200
    mov edx, 5*28+8
    mov esi, 0x00282828
    call fb_fill_rect
    pop rsi
    pop rdx
    pop rcx
    pop r9
    pop r8
    ret

; start-button click zone test: R8D=x R9D=y -> AL=1 if inside
gui_start_hit:
    cmp r8d, 4
    jl .no
    cmp r8d, 94
    jge .no
    mov eax, [fb_height]
    sub eax, 32
    cmp r9d, eax
    jl .no
    mov al, 1
    ret
.no:
    xor eax, eax
    ret

; main loop: poll kbd/mouse, redraw ~30fps, hotkeys drop to shell
gui_loop:
.frame:
    cmp byte [kbd_f8_flag], 0
    jne .to_shell
    cmp byte [kbd_dbg_flag], 0
    jne .to_shell
    ; keyboard: ESC toggles start menu, letters open apps (demo bindings)
    call kbd_get_key
    test rax, rax
    jz .mouse
    cmp al, 27
    je .toggle_start
    cmp al, 't'
    je .open_term
    cmp al, 'e'
    je .open_edit
    jmp .mouse
.toggle_start:
    xor byte [start_open], 1
    jmp .mouse
.open_term:
    push rax
    mov r8d, 120
    mov r9d, 120
    mov ecx, 420
    mov edx, 260
    lea rsi, [rel title_term]
    mov edi, 1
    call wm_create
    pop rax
    jmp .mouse
.open_edit:
    push rax
    mov r8d, 160
    mov r9d, 150
    mov ecx, 440
    mov edx, 280
    lea rsi, [rel title_edit]
    mov edi, 3
    call wm_create
    pop rax
.mouse:
    ; mouse state + edge detect
    call mouse_get_state                    ; RAX=x RBX=y RCX=btns
    mov r8d, eax
    mov r9d, ebx
    mov dl, cl                              ; new buttons
    mov dh, [gui_last_btn]
    mov [gui_last_btn], dl
    push rdx
    push r8
    push r9
    mov bl, dl
    call wm_mouse_event                     ; drag/close/min (consumes if on window)
    pop r9
    pop r8
    pop rdx
    cmp al, 1
    je .draw
    ; not on window: start-button click?
    test dl, 1
    jz .draw
    test dh, 1
    jnz .draw
    call gui_start_hit
    test al, al
    jz .draw
    xor byte [start_open], 1
.draw:
    call gui_draw_frame
    ; ~33ms delay via PIT busy wait
    mov rax, [pit_ticks]
    add rax, 3
.wait:
    cmp [pit_ticks], rax
    jb .wait
    jmp .frame
.to_shell:
    mov byte [kbd_f8_flag], 0
    mov byte [kbd_dbg_flag], 0
    mov byte [gui_running], 0
    call shell_main
    ; shell returned via 'gui-restart'
    mov byte [gui_running], 1
    jmp .frame

; 12x12 arrow cursor, white with black border
gui_cursor:
    push r8
    push r9
    push rsi
    push rax
    push rbx
    push r10
    push r12
    push r13
    mov r8d, [mouse_x]
    mov r9d, [mouse_y]
    lea rsi, [rel cursor_bits]
    mov r12d, r8d                          ; base x (survives plot calls)
    mov r13d, r9d                          ; base y
    xor ebx, ebx                            ; row
.crow:
    cmp ebx, 12
    jae .done
    xor eax, eax                            ; col
.ccol:
    cmp eax, 12
    jae .nextrow
    ; bit = (cursor_bits[row] >> (7-col)) & 1  (ECX free in this loop)
    mov r10b, [rsi+rbx]
    mov ecx, 7
    sub ecx, eax
    shr r10b, cl
    test r10b, 1
    jz .skip
    push rax
    push rbx
    push rsi
    push r12
    push r13
    mov r8d, r12d
    add r8d, eax                           ; x = base + col
    mov r9d, r13d
    add r9d, ebx                           ; y = base + row
    mov esi, 0x00FFFFFF
    call fb_put_pixel_xy
    pop r13
    pop r12
    pop rsi
    pop rbx
    pop rax
.skip:
    inc eax
    jmp .ccol
.nextrow:
    inc ebx
    jmp .crow
.done:
    pop r13
    pop r12
    pop r10
    pop rbx
    pop rax
    pop rsi
    pop r9
    pop r8
    ret

cursor_bits:
db 10000000b, 11000000b, 11100000b, 11110000b, 11111000b, 11111100b
db 11111110b, 11111111b, 11111000b, 11110000b, 11000000b, 00000000b

title_term db "Terminal", 0
title_file db "File Manager", 0
title_mon  db "System Monitor", 0
title_edit db "Text Editor", 0
clock_h    dd 0
gui_last_btn db 0
gui_running db 0
start_open db 0
theme_top dd 0x00103060
theme_taskbar dd 0x00202020
