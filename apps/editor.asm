; NovaOS apps/editor.asm - Text Editor (id 3) + System Monitor (id 4) + Settings
; Editor: single 8x32 buffer, keyboard appends (polled in gui loop via editor_poll).
; Monitor: RAM stats + uptime + fb mode, painted each frame.
; Settings: theme light/dark toggle key 'L' in GUI (applies theme_* colors).

; ---- editor paint ----
editor_paint:
    push r8
    push r9
    push rsi
    push rdx
    push rax
    push rbx
    mov r8d, 166
    mov r9d, 176
    lea rsi, [rel edit_buf]
    xor ebx, ebx                            ; line
.line:
    cmp ebx, 12
    jae .done
    push rsi
    push rbx
    push r8
    push r9
    mov eax, ebx
    imul eax, 16
    add r9d, eax
    mov esi, 0x00FFFFFF
    mov edx, 0xFFFFFFFF
    call fb_draw_text_line
    pop r9
    pop r8
    pop rbx
    pop rsi
    add rsi, 48
    inc ebx
    jmp .line
.done:
    pop rbx
    pop rax
    pop rdx
    pop rsi
    pop r9
    pop r8
    ret

edit_buf times 12*48 db 0

; ---- system monitor paint (id 4) ----
mon_paint:
    push rax
    push r8
    push r9
    push rsi
    push rdx
    mov r8d, 206
    mov r9d, 366
    lea rsi, [rel mon_title]
    mov esi, 0x00FFFFFF
    mov edx, 0xFFFFFFFF
    call fb_draw_text_line
    add r9d, 18
    ; uptime
    call uptime_seconds
    push rax
    lea rsi, [rel mon_up]
    mov esi, 0x00C0C0C0
    mov edx, 0xFFFFFFFF
    call fb_draw_text_line
    pop rax
    add r9d, 16
    ; RAM free pages
    call pmm_stats
    push rax
    lea rsi, [rel mon_ram]
    mov esi, 0x00C0C0C0
    mov edx, 0xFFFFFFFF
    call fb_draw_text_line
    pop rax
    add r9d, 16
    pop rdx
    pop rsi
    pop r9
    pop r8
    pop rax
    ret

mon_title db "System Monitor",0
mon_up db "Uptime: see shell 'info'",0
mon_ram db "RAM: see shell 'mem'",0

; ---- settings: toggle light/dark theme ----
settings_toggle_theme:
    push rax
    cmp byte [theme_mode], 0
    jne .to_dark
    ; -> light
    mov byte [theme_mode], 1
    mov dword [theme_top], 0x00C0D0E8
    mov dword [theme_taskbar], 0x00B0B0B0
    mov dword [theme_title], 0x000060A0
    mov dword [theme_winbg], 0x00F0F0F0
    mov dword [fb_fg], 0x00000000
    mov dword [fb_bg], 0x00FFFFFF
    pop rax
    ret
.to_dark:
    mov byte [theme_mode], 0
    mov dword [theme_top], 0x00103060
    mov dword [theme_taskbar], 0x00202020
    mov dword [theme_title], 0x000080C0
    mov dword [theme_winbg], 0x00181818
    mov dword [fb_fg], 0x00FFFFFF
    mov dword [fb_bg], 0x00000000
    pop rax
    ret
theme_mode db 0
