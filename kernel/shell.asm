; NovaOS kernel/shell.asm - Emergency Shell (failsafe text console)
; Backend: framebuffer text if fb_ok, else VGA text 0xB8000.
; Commands: help clear info mem peek poke ls cat fbinfo gui-restart reboot shutdown halt

shell_main:
    push rax
    call shell_banner
.loop:
    lea rsi, [rel prompt_str]
    call shell_puts
    lea rdi, [rel shell_line]
    call shell_getline
    call shell_exec
    jmp .loop

shell_banner:
    lea rsi, [rel banner_str]
    call shell_puts
    ret
banner_str db 10,"NovaOS Emergency Shell v0.1 (F8/Ctrl+Alt+T to enter, 'gui-restart' to leave)",10,0
prompt_str db "nova> ",0

; ---- output backend (framebuffer/VGA + serial mirror for headless debug) ----
shell_putc: ; AL=char. Preserves RAX/RBX/RSI.
    push rax
    push rbx
    push rsi
    mov bl, al
    mov al, bl
    call serial_putc                       ; mirror to COM1
    mov al, bl
    mov al, bl
    cmp byte [fb_ok], 0
    je .vga
    ; framebuffer path via fb cursor
    cmp al, 10
    je .fb_nl
    mov r8d, [fb_cursor_x]
    mov r9d, [fb_cursor_y]
    mov esi, [fb_fg]
    mov edx, [fb_bg]
    push rax
    call fb_draw_char
    pop rax
    add dword [fb_cursor_x], 8
    mov ebx, [fb_width]
    sub ebx, 8
    cmp [fb_cursor_x], ebx
    jb .out
.fb_nl:
    mov dword [fb_cursor_x], 0
    add dword [fb_cursor_y], 16
    mov ebx, [fb_height]
    sub ebx, 16
    cmp [fb_cursor_y], ebx
    jb .out
    call fb_scroll
    jmp .out
.vga:
    call vga_putc
.out:
    pop rsi
    pop rbx
    pop rax
    ret

shell_puts: ; RSI=cstr
    push rax
.loop:
    lodsb
    test al, al
    jz .done
    call shell_putc
    jmp .loop
.done:
    pop rax
    ret

; print RAX hex
shell_print_hex:
    push rax
    push rcx
    push rdx
    mov rcx, 60
.nib:
    mov rdx, rax
    shr rdx, cl
    and dl, 0xF
    add dl, '0'
    cmp dl, '9'
    jbe .ch
    add dl, 7
.ch:
    mov al, dl
    call shell_putc
    sub rcx, 4
    jns .nib
    pop rdx
    pop rcx
    pop rax
    ret

; print RAX decimal
shell_print_dec:
    push rax
    push rbx
    push rcx
    push rdx
    xor ecx, ecx
    mov rbx, 10
    test rax, rax
    jnz .div
    mov al, '0'
    call shell_putc
    jmp .done
.div:
    xor edx, edx
    div rbx                                ; RDX:RAX / 10 (RAX<2^64 ok)
    push rdx
    inc ecx
    test rax, rax
    jnz .div
.out:
    pop rax
    add al, '0'
    call shell_putc
    dec ecx
    jnz .out
.done:
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ---- VGA text backend (0xB8000, 80x25) ----
vga_putc: ; AL=char
    push rbx
    push rcx
    cmp al, 10
    je .nl
    mov ebx, [vga_pos]
    mov cl, al
    mov byte [0xB8000+rbx*2], cl
    mov byte [0xB8000+rbx*2+1], 0x07
    inc dword [vga_pos]
    cmp dword [vga_pos], 80*25
    jb .out
    call vga_scroll
    jmp .out
.nl:
    mov eax, [vga_pos]
    xor edx, edx
    mov ecx, 80
    div ecx
    inc eax
    imul eax, 80
    mov [vga_pos], eax
    cmp dword [vga_pos], 80*25
    jb .out
    call vga_scroll
.out:
    pop rcx
    pop rbx
    ret

vga_scroll:
    push rsi
    push rdi
    push rcx
    mov rsi, 0xB8000+80*2
    mov rdi, 0xB8000
    mov ecx, 80*24
.cp:
    mov ax, [rsi]
    mov [rdi], ax
    add rsi, 2
    add rdi, 2
    dec ecx
    jnz .cp
    mov ecx, 80
.cl:
    mov word [rdi], 0x0720
    add rdi, 2
    dec ecx
    jnz .cl
    sub dword [vga_pos], 80
    pop rcx
    pop rdi
    pop rsi
    ret

vga_clear:
    push rdi
    push rcx
    mov rdi, 0xB8000
    mov ecx, 80*25
.cl:
    mov word [rdi], 0x0720
    add rdi, 2
    dec ecx
    jnz .cl
    mov dword [vga_pos], 0
    pop rcx
    pop rdi
    ret
vga_pos dd 0

; ---- line input with echo + backspace ----
shell_getline: ; RDI=buf (256B)
    push rbx
    push rcx
    xor ecx, ecx
.key:
    call kbd_getc_block                    ; AL=key
    cmp al, 10
    je .enter
    cmp al, 8
    je .back
    cmp ecx, 255
    jae .key
    mov [rdi+rcx], al
    inc ecx
    call shell_putc                        ; echo
    jmp .key
.back:
    test ecx, ecx
    jz .key
    dec ecx
    mov al, 8
    call shell_putc
    mov al, ' '
    call shell_putc
    mov al, 8
    call shell_putc
    jmp .key
.enter:
    mov byte [rdi+rcx], 0
    mov al, 10
    call shell_putc
    pop rcx
    pop rbx
    ret

; ---- command dispatch ----
shell_exec:
    push rsi
    lea rsi, [rel shell_line]
    ; skip leading spaces
.skip:
    cmp byte [rsi], ' '
    jne .cmd
    inc rsi
    jmp .skip
.cmd:
    lea rdi, [rel cmd_help]
    call shell_streq_word
    test al, al
    jnz .do_help
    lea rdi, [rel cmd_clear]
    call shell_streq_word
    test al, al
    jnz .do_clear
    lea rdi, [rel cmd_info]
    call shell_streq_word
    test al, al
    jnz .do_info
    lea rdi, [rel cmd_mem]
    call shell_streq_word
    test al, al
    jnz .do_mem
    lea rdi, [rel cmd_peek]
    call shell_streq_word
    test al, al
    jnz .do_peek
    lea rdi, [rel cmd_poke]
    call shell_streq_word
    test al, al
    jnz .do_poke
    lea rdi, [rel cmd_ls]
    call shell_streq_word
    test al, al
    jnz .do_ls
    lea rdi, [rel cmd_cat]
    call shell_streq_word
    test al, al
    jnz .do_cat
    lea rdi, [rel cmd_fbinfo]
    call shell_streq_word
    test al, al
    jnz .do_fbinfo
    lea rdi, [rel cmd_gui]
    call shell_streq_word
    test al, al
    jnz .do_gui
    lea rdi, [rel cmd_reboot]
    call shell_streq_word
    test al, al
    jnz .do_reboot
    lea rdi, [rel cmd_shutdown]
    call shell_streq_word
    test al, al
    jnz .do_shutdown
    lea rdi, [rel cmd_halt]
    call shell_streq_word
    test al, al
    jnz .do_halt
    cmp byte [rsi], 0
    je .out                                ; empty line
    lea rsi, [rel msg_unknown]
    call shell_puts
    jmp .out
.do_help:    lea rsi, [rel msg_help]
    call shell_puts
    jmp .out
.do_clear:
    cmp byte [fb_ok], 0
    je .vgaclear
    mov esi, [fb_bg]
    call fb_clear
    jmp .out
.vgaclear:   call vga_clear
    jmp .out
.do_info:    lea rsi, [rel msg_info]
    call shell_puts
    jmp .out
.do_mem:     call shell_cmd_mem
    jmp .out
.do_peek:    call shell_cmd_peek
    jmp .out
.do_poke:    call shell_cmd_poke
    jmp .out
.do_ls:      call shell_cmd_ls
    jmp .out
.do_cat:     call shell_cmd_cat
    jmp .out
.do_fbinfo:  call shell_cmd_fbinfo
    jmp .out
.do_gui:     pop rsi
    ret                 ; return to gui_loop
.do_reboot:  call sys_reboot
.do_shutdown: call sys_shutdown
.do_halt:
    lea rsi, [rel msg_halt]
    call shell_puts
    cli
    hlt
    jmp .do_halt
.out:
    pop rsi
    ret

; compare first word of RSI with cstr RDI -> AL=1 match (delimiter space/0)
shell_streq_word:
    push rsi
    push rdi
    push rbx
.loop:
    mov bl, [rdi]
    test bl, bl
    jz .endcmd
    cmp [rsi], bl
    jne .no
    inc rsi
    inc rdi
    jmp .loop
.endcmd:
    cmp byte [rsi], ' '
    je .yes
    cmp byte [rsi], 0
    je .yes
.no:
    xor eax, eax
    jmp .out
.yes:
    mov al, 1
.out:
    pop rbx
    pop rdi
    pop rsi
    ret

; ---- commands ----
shell_cmd_mem:
    push rax
    call pmm_stats                            ; RAX=free pages RDX=total
    push rax
    push rdx
    lea rsi, [rel msg_memfree]
    call shell_puts
    pop rdx
    pop rax
    push rax
    push rdx
    shl rax, 12
    call shell_print_dec
    lea rsi, [rel msg_bytes]
    call shell_puts
    pop rdx
    pop rax
    lea rsi, [rel msg_memtot]
    call shell_puts
    mov rax, rdx
    shl rax, 12
    call shell_print_dec
    lea rsi, [rel msg_bytes]
    call shell_puts
    lea rsi, [rel msg_heap]
    call shell_puts
    mov rax, [heap_end]
    call shell_print_hex
    mov al, 10
    call shell_putc
    pop rax
    ret

; peek <hexaddr>: dump 16 bytes
shell_cmd_peek:
    lea rdi, [rel shell_line+5]
    call shell_skip_spaces
    call shell_parse_hex                      ; -> RAX
    test rcx, rcx
    jz .usage
    mov rsi, rax
    mov ecx, 16
.dump:
    mov al, [rsi]
    push rsi
    push rcx
    push rax
    movzx eax, al
    mov rax, rax
    call shell_print_hex_byte
    mov al, ' '
    call shell_putc
    pop rax
    pop rcx
    pop rsi
    inc rsi
    dec ecx
    jnz .dump
    mov al, 10
    call shell_putc
    ret
.usage:
    lea rsi, [rel msg_usage_peek]
    call shell_puts
    ret

; poke <hexaddr> <hexval>: write byte
shell_cmd_poke:
    lea rdi, [rel shell_line+5]
    call shell_skip_spaces
    call shell_parse_hex
    test rcx, rcx
    jz .usage
    mov rsi, rax                              ; addr
    mov rdi, rdx                              ; end ptr -> next arg
    call shell_skip_spaces_rdi
    call shell_parse_hex_rdi
    test rcx, rcx
    jz .usage
    mov [rsi], al
    lea rsi, [rel msg_ok]
    call shell_puts
    ret
.usage:
    lea rsi, [rel msg_usage_poke]
    call shell_puts
    ret

shell_cmd_ls:
    lea rsi, [rel msg_ls_head]
    call shell_puts
    ; read-only FAT: try ATA HDD MBR + first FAT entries (best effort)
    call fat_ls_stub
    ret

shell_cmd_cat:
    lea rsi, [rel msg_cat_todo]
    call shell_puts
    ret

shell_cmd_fbinfo:
    lea rsi, [rel msg_fbaddr]
    call shell_puts
    mov rax, [fb_addr]
    call shell_print_hex
    mov al, 10
    call shell_putc
    lea rsi, [rel msg_fbmode]
    call shell_puts
    mov eax, [fb_width]
    mov rax, rax
    call shell_print_dec
    mov al, 'x'
    call shell_putc
    mov eax, [fb_height]
    mov rax, rax
    call shell_print_dec
    mov al, 'x'
    call shell_putc
    mov eax, [fb_bpp]
    mov rax, rax
    call shell_print_dec
    mov al, 10
    call shell_putc
    ret

; print byte AL as 2 hex digits
shell_print_hex_byte:
    push rax
    push rcx
    mov cl, al
    shr al, 4
    call .nib
    mov al, cl
    and al, 0xF
    call .nib
    pop rcx
    pop rax
    ret
.nib:
    add al, '0'
    cmp al, '9'
    jbe .ch
    add al, 7
.ch:
    call shell_putc
    ret

; skip spaces: RDI ptr -> RDI
shell_skip_spaces:
.loop:
    cmp byte [rdi], ' '
    jne .done
    inc rdi
    jmp .loop
.done:
    ret
shell_skip_spaces_rdi:
    mov rdi, rdx
    jmp shell_skip_spaces

; parse hex at RDI -> RAX=value RCX=digits RDX=endptr
shell_parse_hex:
    mov rdi, rdi
    xor eax, eax
    xor ecx, ecx
.loop:
    mov dl, [rdi]
    cmp dl, '0'
    jb .done
    cmp dl, '9'
    jbe .dig
    cmp dl, 'a'
    jb .up
    cmp dl, 'f'
    ja .done
    sub dl, 'a'-10
    jmp .acc
.up:
    cmp dl, 'A'
    jb .done
    cmp dl, 'F'
    ja .done
    sub dl, 'A'-10
    jmp .acc
.dig:
    sub dl, '0'
.acc:
    shl rax, 4
    movzx edx, dl
    or rax, rdx
    inc rdi
    inc ecx
    jmp .loop
.done:
    mov rdx, rdi
    ret
shell_parse_hex_rdi:
    jmp shell_parse_hex

; ---- data ----
cmd_help db "help",0
cmd_clear db "clear",0
cmd_info db "info",0
cmd_mem db "mem",0
cmd_peek db "peek",0
cmd_poke db "poke",0
cmd_ls db "ls",0
cmd_cat db "cat",0
cmd_fbinfo db "fbinfo",0
cmd_gui db "gui-restart",0
cmd_reboot db "reboot",0
cmd_shutdown db "shutdown",0
cmd_halt db "halt",0
msg_help db "Commands: help clear info mem peek <addr> poke <addr> <val> ls cat <file> fbinfo gui-restart reboot shutdown halt",10,0
msg_info db "NovaOS v0.1 - x86_64 hobby OS - dual BIOS+UEFI - ASM only",10,0
msg_unknown db "Unknown command. Type 'help'.",10,0
msg_memfree db "Free RAM (bytes): ",0
msg_memtot db "Total tracked (bytes): ",0
msg_bytes db " bytes",10,0
msg_heap db "Heap end: 0x",0
msg_usage_peek db "Usage: peek <hexaddr>",10,0
msg_usage_poke db "Usage: poke <hexaddr> <hexbyte>",10,0
msg_ok db "OK",10,0
msg_ls_head db "Files (read-only FAT, ATA HDD):",10,0
msg_cat_todo db "cat: give filename - read-only viewer (see File Manager app)",10,0
msg_fbaddr db "Framebuffer @ 0x",0
msg_fbmode db "Mode: ",0
msg_halt db "Halting CPU...",10,0
shell_line times 256 db 0
